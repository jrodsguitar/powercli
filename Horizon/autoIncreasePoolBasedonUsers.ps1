#This script will autamtically increaese the Maximum amount of Machines in a Linked CLone Pool based on the number of entitled users. It increases the total by a user specificied setting.
#Jose Rodriguez (jrodsguitar)
#https://get-cj.com

#Change these settings to match your environment ###########################################################
$viewserver = "NAME_OF_SERVER" 

#$poolDisplayName = 'DISPLAY_NAME_OF_POOL'

#Buffer number of machines to increase pool by. Change this based on your estimated needs.

#The script will increase the max number of machines by (Total Amount of entitled users - The difference of Total Machines in pool) + $machineBuffer
#So if the total amount of machines is 3 and the total number of entitled users is 5. We need 2 machines right? So the script will add 2 machines + $machineBuffer.
$machineBuffer = 1

#If totla machines to add is greater or equal to 50 don't do it. This is a precautionary measure in case someone adds too many users to the entitled AD group.
$threshold = 2
###########################################################################################################

if($cred -eq $null){

    $cred = Get-Credential

}

if($connect -eq $null){

    $connect = Connect-HVServer -server $viewserver

}

$session = New-PSSession -Computername $viewserver

#Define a scriptblock to run - $computer is set to the first argument, $variable to the second 

$scriptBlock = { 

    #Initialize variables and load modules for horizon on remote connection server.

    Set-Variable product_name "VMware View PowerCLI" -scope Private
    Set-Variable view_snapin_name "VMware.View.Broker" -scope Private
    Set-Variable powercli_snapin_name "VMware.VimAutomation.Core" -scope Private
    Set-Variable powercli_product_name "VI Toolkit / VSphere PowerCLI" -scope Private

    # Load View Snapin
    $ViewSnapinLoaded = Get-PSSnapin | Where-Object { $_.Name -eq $view_snapin_name }
    if(!$ViewSnapinLoaded){

        write-host "Loading $product_name"

        # Install or Re-register View Cmdlets
        $installpath = (get-itemproperty "HKLM:\Software\VMware, Inc.\VMware VDM").ServerInstallPath

        $NetFrameworkDirectory = $([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory())
        set-alias installUtil (Join-Path $NetFrameworkDirectory "InstallUtil.exe")

        $null = (installUtil ($installpath  + "\bin\PowershellServiceCmdlets.dll"))

        add-PSSnapin $view_snapin_name

        }
     
    else {

        write-host "$product_name snapin already loaded."

    }

    # Load VI Toolkit/PowerCLI if available
    $VimAutomationInstalled = Get-PSSnapin -Registered | Where-Object { $_.Name -eq $powercli_snapin_name }

    if($VimAutomationInstalled){

        $VimAutomationLoaded = Get-PSSnapin | Where-Object { $_.Name -eq $powercli_snapin_name }

    if(!$VimAutomationLoaded){

        write-host "Loading $powercli_product_name"
        add-PSSnapin $powercli_snapin_name

    } 

    else {

        write-host "$powercli_product_name already loaded"

    }

}

    Remove-Variable product_name -scope Private
    Remove-Variable view_snapin_name -scope Private
    Remove-Variable powercli_snapin_name -scope Private
    Remove-Variable powercli_product_name -scope Private
    Add-PSSnapin vmware.view.broker 

}  

#Run script to intialize remote session
Invoke-Command -Session $session -ScriptBlock $scriptBlock

#Import remote session and prefix commands with 'VDI'
$importsession = Import-PSSession -Session $session -Prefix VDI -Module VMware*

$pools = get-vdipool

foreach($pool in $pools){

    #Gather Pool data
    #$pool = (Get-VDIPool -DisplayName $poolDisplayName)

    $PoolEntitlments = Get-VDIPoolEntitlement -Pool_id $pool.pool_id

    $maxmachines = $pool.maximumCount

    $userGroupCheck = $null
    $poolUsers = $null
    $poolGroups = $null
    $entitledusers = $null

    #Counts the number of users in the AD group that is entitled to the pool
    $userGroupCheck =  ($PoolEntitlments | foreach-object {Get-ADObject $_})

    $poolUsers = @($userGroupCheck |   Where-Object {$_.objectclass -eq 'user'}).Count

    $poolGroups =  @($userGroupCheck |   Where-Object {$_.objectclass -eq 'group'}).Count

    $entitledusers = $poolUsers + $poolGroups

    #If entitled users is greater than the amount of entitles users than increase the max machines in the pool by $newMaxIncrease
    if($entitledusers -ge $maxmachines ){

        $newMaxMachines = ($entitledusers - $maxmachines) + $machineBuffer

        $total = $newMaxMachines + $maxmachines

    If($total -le $threshold){

        Update-VDIAutomaticLinkedClonePool -MaximumCount $newMaxMachines -MinimumCount $newMaxMachines -Pool_id $pool.pool_id
        #Update-VDIAutomaticPool -MaximumCount $newMaxMachines -MinimumCount $newMaxMachines -Pool_id $pool.pool_id
        Write-Output "Increasing Max machines $($pool.pool_id) from $maxmachines to $total machines"

    }

    else{

        Write-output "$threshold is too big. Aborting the process"


        }

    }

}

 
Get-PSSession | Remove-PSSession