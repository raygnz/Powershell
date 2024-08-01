<#
.SYNOPSIS
Resets Citrix Workspace App on a remote computer.
.DESCRIPTION
Connects to a remote computer. Creates a scheduled task to reset Citrix Workspace App. The scheduled taske is set to run 2 mins after creation.
The script waits for 4 mins to allow the scheduled task to run, then deletes the scheduled task.
.NOTES
$RemoteComputer = "<target computername>"
$Cred = <Admin account with permissions to run the script>"
-UserId user account that will run the scheduled task. This must be the user you are trying to reset Citrix Workspace App for.
Author: Phil Gray
Email: philiphgray@gmail.com
URL: https://github.com/raygnz/Powershell
Version 1.0 - 31/07/24 - Initial
Version 1.1 - 31/07/24 - Add $Settings so scheduled task runs even if on battery mode.
#>
$RemoteComputer = Read-Host "Enter remote computername"
$Cred = Read-Host "Enter admin username"
# Connect to remote computer
Invoke-Command -ComputerName "$RemoteComputer" -Credential "$Cred" -ScriptBlock {
# Create scheduled task on remote computer
    $Path = "C:\Program Files (x86)\Citrix\ICA Client\SelfServicePlugin\Cleanup.exe"
    $Action = New-ScheduledTaskAction -Execute "$Path" -Argument "/silent -cleanUser"
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2)
    $Principal = New-ScheduledTaskPrincipal -UserId "<domain\user>" -LogonType Interactive
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask "Reset-CWA" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
# Sleep for 4 mins while scheduled task runs
    Start-Sleep -Seconds 240
# Remove scheduled task
    Unregister-ScheduledTask -TaskName "Reset-CWA" -Confirm:$false
}
Write-Host "Citrix Workspace App has been reset on $RemoteComputer"