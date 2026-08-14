#requires -version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Repairs Windows Update components on Windows.

.DESCRIPTION
    Stops Windows Update-related services, clears update caches, optionally
    removes Windows Update policy keys, resets update components, restarts
    services and writes detailed logging. Protected Catroot2 GUID folders generate warnings and do not terminate
    the repair. Service startup types are configured with Set-Service. Service
    security descriptors and DcomLaunch configuration are not modified.
.NOTES
Author: Phil Gray
Email: philiphgray@gmail.com
URL: https://github.com/raygnz/Powershell
Version 1.0 - 14/08/26 - Initial
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$LogPath = 'C:\Temp\Windows-updates-repair.log',
    [switch]$NoRestart,
    [switch]$SkipPolicyReset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logDirectory = Split-Path -Path $LogPath -Parent
if (-not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')] [string]$Level = 'INFO'
    )

    $entry = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $entry | Tee-Object -FilePath $LogPath -Append | Write-Host
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter()] [string[]]$ArgumentList = @(),
        [switch]$IgnoreExitCode
    )

    Write-Log "Running: $FilePath $($ArgumentList -join ' ')"
    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        if ($null -ne $line -and -not [string]::IsNullOrWhiteSpace($line.ToString())) {
            Write-Log $line.ToString()
        }
    }

    if ($exitCode -ne 0) {
        $message = "Command returned exit code {0}: {1}" -f $exitCode, $FilePath
        if ($IgnoreExitCode) {
            Write-Log $message 'WARN'
        }
        else {
            throw $message
        }
    }

    return $exitCode
}

function Stop-ServiceWithRetry {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$DisplayName,
        [int]$MaximumAttempts = 3
    )

    $service = Get-Service -Name $Name -ErrorAction Stop
    if ($service.Status -eq 'Stopped') {
        Write-Log "Service '$DisplayName' ($Name) is already stopped."
        return
    }

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        Write-Log "Stopping '$DisplayName' ($Name). Attempt $attempt of $MaximumAttempts."
        try {
            Stop-Service -Name $Name -Force -ErrorAction Stop
            (Get-Service -Name $Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            Write-Log "Service '$DisplayName' ($Name) stopped." 'SUCCESS'
            return
        }
        catch {
            Write-Log "Unable to stop '$DisplayName' ($Name) on attempt $attempt. $($_.Exception.Message)" 'WARN'
            Start-Sleep -Seconds 3
        }
    }

    throw "Cannot reset Windows Update because '$DisplayName' ($Name) failed to stop. Restart the computer and try again."
}

function Start-ServiceSafe {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$DisplayName
    )

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        if ($service.Status -ne 'Running') {
            Write-Log "Starting '$DisplayName' ($Name)."
            Start-Service -Name $Name -ErrorAction Stop
            (Get-Service -Name $Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
        }
        Write-Log "Service '$DisplayName' ($Name) is running." 'SUCCESS'
    }
    catch {
        Write-Log "Failed to start '$DisplayName' ($Name). $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Remove-ItemsByPattern {
    param([Parameter(Mandatory)] [string]$Path)

    $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
    if (-not $items) {
        Write-Log "No items found for: $Path"
        return
    }

    foreach ($item in $items) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            Write-Log "Removed: $($item.FullName)"
        }
        catch {
            Write-Log "Failed to remove '$($item.FullName)'. $($_.Exception.Message)" 'WARN'
        }
    }
}

function Clear-FolderContents {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [int]$MaximumAttempts = 3
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Folder not found, skipping: $Path" 'WARN'
        return
    }

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        Write-Log "Clearing contents of '$Path'. Attempt $attempt of $MaximumAttempts."

        $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
        if ($items.Count -eq 0) {
            Write-Log "Folder is already empty: $Path" 'SUCCESS'
            return
        }

        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                Write-Log "Removed: $($item.FullName)"
            }
            catch {
                Write-Log "Could not remove '$($item.FullName)' on attempt $attempt. $($_.Exception.Message)" 'WARN'
            }
        }

        $remaining = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) {
            Write-Log "Cleared contents of '$Path'." 'SUCCESS'
            return
        }

        if ($attempt -lt $MaximumAttempts) {
            Write-Log "Items remain in '$Path'. Waiting before retry." 'WARN'
            Start-Sleep -Seconds 5
        }
    }

    $remainingNames = @(
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    )

    if ($remainingNames.Count -gt 0) {
        if ($Path -like '*Catroot2*') {
            Write-Log ("Catroot2 contains protected cryptographic database folders: {0}" -f ($remainingNames -join ', ')) 'WARN'
            Write-Log 'Continuing Windows Update repair because protected Catroot2 folders are treated as a warning on this Citrix version.' 'WARN'
            return
        }

        throw ("Unable to fully clear '{0}'. Remaining items: {1}" -f $Path, ($remainingNames -join ', '))
    }

    Write-Log "Successfully cleared '$Path'." 'SUCCESS'
}

function Remove-RegistryKeyIfPresent {
    param([Parameter(Mandatory)] [string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Removed registry key: $Path"
    }
    else {
        Write-Log "Registry key not present: $Path"
    }
}

$services = @(
    @{ Name = 'bits';     DisplayName = 'Background Intelligent Transfer Service' },
    @{ Name = 'wuauserv'; DisplayName = 'Windows Update' },
    @{ Name = 'appidsvc'; DisplayName = 'Application Identity' },
    @{ Name = 'cryptsvc'; DisplayName = 'Cryptographic Services' }
)

try {
    Write-Log ('=' * 78)
    Write-Log "Windows Update repair started on $env:COMPUTERNAME by $env:USERNAME."
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"

    foreach ($service in $services) {
        Stop-ServiceWithRetry -Name $service.Name -DisplayName $service.DisplayName
    }

    Invoke-NativeCommand -FilePath 'ipconfig.exe' -ArgumentList '/flushdns' | Out-Null

    Remove-ItemsByPattern -Path (Join-Path $env:ALLUSERSPROFILE 'Application Data\Microsoft\Network\Downloader\qmgr*.dat')
    Remove-ItemsByPattern -Path (Join-Path $env:ALLUSERSPROFILE 'Microsoft\Network\Downloader\qmgr*.dat')
    Remove-ItemsByPattern -Path (Join-Path $env:SystemRoot 'Logs\WindowsUpdate\*')

    $pendingXml = Join-Path $env:SystemRoot 'WinSxS\pending.xml'
    $pendingXmlBackup = "$pendingXml.bak"
    if (Test-Path -LiteralPath $pendingXmlBackup) {
        Remove-Item -LiteralPath $pendingXmlBackup -Force -ErrorAction Stop
        Write-Log "Removed existing backup: $pendingXmlBackup"
    }
    if (Test-Path -LiteralPath $pendingXml) {
        Invoke-NativeCommand -FilePath 'takeown.exe' -ArgumentList @('/f', $pendingXml) | Out-Null
        Invoke-NativeCommand -FilePath 'attrib.exe' -ArgumentList @('-r', '-s', '-h', $pendingXml) -IgnoreExitCode | Out-Null
        Rename-Item -LiteralPath $pendingXml -NewName 'pending.xml.bak' -Force -ErrorAction Stop
        Write-Log "Renamed pending.xml to pending.xml.bak." 'SUCCESS'
    }

    # Citrix-friendly approach: preserve the parent folders and remove only their contents.
    # Windows recreates the required update data after the services start.
    Clear-FolderContents -Path (Join-Path $env:SystemRoot 'SoftwareDistribution')
    Clear-FolderContents -Path (Join-Path $env:SystemRoot 'System32\Catroot2')

    if (-not $SkipPolicyReset) {
        Write-Log 'Resetting Windows Update policy registry keys.' 'WARN'
        @(
            'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate',
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate'
        ) | ForEach-Object { Remove-RegistryKeyIfPresent -Path $_ }

        Invoke-NativeCommand -FilePath 'gpupdate.exe' -ArgumentList '/force' -IgnoreExitCode | Out-Null
    }
    else {
        Write-Log 'Windows Update policy reset skipped because -SkipPolicyReset was specified.' 'WARN'
    }

    Write-Log 'Skipping BITS and Windows Update service security descriptor resets on the Citrix version.' 'INFO'

    $dlls = @(
        'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll',
        'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll',
        'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'dssenh.dll',
        'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
        'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll',
        'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll', 'wups.dll', 'wups2.dll',
        'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll',
        'wuwebv.dll', 'wudriver.dll'
    )

    foreach ($dll in $dlls) {
        $dllPath = Join-Path $env:SystemRoot "System32\$dll"
        if (Test-Path -LiteralPath $dllPath) {
            Invoke-NativeCommand -FilePath 'regsvr32.exe' -ArgumentList @('/s', $dllPath) -IgnoreExitCode | Out-Null
        }
        else {
            Write-Log "DLL not present, skipping registration: $dllPath" 'WARN'
        }
    }

    Invoke-NativeCommand -FilePath 'netsh.exe' -ArgumentList @('winsock', 'reset') | Out-Null
    Invoke-NativeCommand -FilePath 'netsh.exe' -ArgumentList @('winhttp', 'reset', 'proxy') -IgnoreExitCode | Out-Null

    # Use native PowerShell service management rather than sc.exe config.
    # DcomLaunch is intentionally not modified on this Citrix version.
    foreach ($serviceName in @('wuauserv', 'bits')) {
        try {
            Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            Write-Log ("Set startup type for '{0}' to Automatic." -f $serviceName) 'SUCCESS'
        }
        catch {
            Write-Log ("Unable to set startup type for '{0}' to Automatic. Continuing repair. {1}" -f $serviceName, $_.Exception.Message) 'WARN'
        }
    }

    foreach ($service in $services) {
        Start-ServiceSafe -Name $service.Name -DisplayName $service.DisplayName
    }

    Write-Log 'Windows Update repair completed successfully.' 'SUCCESS'

    if ($NoRestart) {
        Write-Log 'Restart skipped because -NoRestart was specified. Restart the computer to complete the repair.' 'WARN'
    }
    else {
        $answer = Read-Host 'A restart is required to complete the repair. Restart now? (Y/N)'
        if ($answer -match '^(Y|YES)$') {
            Write-Log 'Restart approved. Restarting the computer now.' 'WARN'
            Restart-Computer -Force
        }
        else {
            Write-Log 'Restart deferred by the user. Restart the computer as soon as practical.' 'WARN'
        }
    }
}
catch {
    Write-Log "Windows Update repair failed: $($_.Exception.Message)" 'ERROR'
    Write-Log "Failure location: $($_.InvocationInfo.PositionMessage)" 'ERROR'
    throw
}
finally {
    Write-Log "Windows Update repair script ended. Log: $LogPath"
    Write-Log ('=' * 78)
}
