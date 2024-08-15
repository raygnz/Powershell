<#
.SYNOPSIS
Starts a stopped service on a remote computer(s).
.DESCRIPTION
Connects to a remote computer. Checks for a stopped service and then starts it.
.NOTES
$ServerList = "<target computername>"
$Cred = <Admin account with permissions to run the script>"
$ServiceName = <Windows Service you wish to start"
Author: Phil Gray
Email: philiphgray@gmail.com
URL: https://github.com/raygnz/Powershell
Version 1.0 - 16/08/24 - Initial
#>

$ServerList = "C:\Temp\ServerList.txt"
$Creds = "adm-pgray@rayg.local"
$ServiceName = "wuauserv"


$Computername = (Get-Content -path $ServerList)
foreach ( $computer in $Computername ) {Invoke-Command -ComputerName $computer -Credential $Creds {
    Get-Service $using:ServiceName | Where-Object {$_.status -eq 'stopped'} | Start-Service }
 }