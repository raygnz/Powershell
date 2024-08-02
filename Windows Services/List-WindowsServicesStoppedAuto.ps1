<#
.SYNOPSIS
Get list of stopped services that have startup type of automatic on a remote computer
.DESCRIPTION
Connect to remote computer and get a list of Windows Services which are currently stopped
with a startup type of Automatic.
.NOTES
$RemoteComputer = "<target computername>"
$Cred = <Admin account with permissions to run the script>"
Author: Phil Gray
Email: philiphgray@gmail.com
URL: https://github.com/raygnz/Powershell
Version 1.0 - 01/08/24 - Initial
#>
# Define Variables
$RemoteComputer = Read-Host "Enter Remote Computername"
$Cred = Read-Host "Enter Admin Username"

# Get list of stopped services with startup type 'automatic'
Invoke-Command -ComputerName "$RemoteComputer" -Credential "$Cred" -ScriptBlock {  
    Get-Service |
    Where-Object {$_.Status -eq 'Stopped'-and $_.StartType -eq 'Automatic'} |
    Select-Object Name,DisplayName,Status,StartType |
    Format-Table
} 