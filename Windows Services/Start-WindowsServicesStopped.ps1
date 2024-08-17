<#
.SYNOPSIS
Starts a stopped service on a remote computer(s).
.DESCRIPTION
Connects to a remote computer. Checks for a stopped service and then starts it.
.NOTES
$ServerList = "<target computername>"
$ServiceName = "<Windows Service you wish to start"
Author: Phil Gray
Email: philiphgray@gmail.com
URL: https://github.com/raygnz/Powershell
Version 1.0 - 16/08/24 - Initial
Version 1.1 - 17/08/24 - Add Test Connection to verify remote server
#>

# Variables
$ServerList = Get-Content "C:\Temp\ServerList.txt"
$ServiceName = Read-Host "Enter Windows Service Name"

# Test connection to remote servers
foreach ( $Server in $ServerList ) {
   if (Test-Connection -TargetName $Server -Count 1 -Quiet) {
# Connect to remote server and start stopped service
     try {
        Invoke-Command -ComputerName $Server {Get-Service $using:ServiceName |
        Where-Object {$_.status -eq 'stopped'} | Start-Service}
     }
    catch { Write-Host "Failed to connect to $Server"
        }
    }
}

