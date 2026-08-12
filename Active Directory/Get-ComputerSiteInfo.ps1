<#
.SYNOPSIS
Get AD Site, Domain Controller and IP Address from Remote Computers
.DESCRIPTION
Connect to supplied list of remote computers, run nltest /dsgetsite collect IP address of computer and output to csv file.
.NOTES
Author: Phil Gray
Email: philiphgray@gmail.com
URL: https://github.com/raygnz/Powershell
Version 1.0 - 12/08/26 - Initial
#>

$ComputerList = "C:\Temp\computers.txt"
$CsvOutput    = "C:\Temp\computer-sites.csv"

# Read computers and remove blank lines
$Computers = Get-Content $ComputerList | Where-Object {
    $_ -and $_.Trim().Length -gt 0
}

$Results = foreach ($Computer in $Computers) {

    $Computer = $Computer.Trim()

    Write-Host "Processing $Computer..." -ForegroundColor Cyan

    try {

        $Data = Invoke-Command -ComputerName $Computer -ScriptBlock {

            # Get AD Site
            $SiteOutput = nltest /dsgetsite 2>$null | Select-Object -First 1

            if ($SiteOutput) {
                $SiteName = $SiteOutput.Trim()
            }
            else {
                $SiteName = "Unknown"
            }

            # Get first active IPv4 address
            $IPAddress = Get-CimInstance Win32_NetworkAdapterConfiguration |
                Where-Object { $_.IPEnabled } |
                ForEach-Object { $_.IPAddress } |
                Where-Object {
                    $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and
                    $_ -ne '127.0.0.1' -and
                    $_ -notlike '169.254.*'
                } |
                Select-Object -First 1

            if (-not $IPAddress) {
                $IPAddress = "Unknown"
            }

            # Get DC from secure channel
            $DomainController = "Unknown"

            $SCOutput = nltest /sc_query:$env:USERDOMAIN 2>$null

            foreach ($Line in $SCOutput) {

                if ($Line -match '^Trusted DC Name\s+\\\\(.+)$') {

                    $DomainController = $Matches[1]
                    break
                }
            }

            [PSCustomObject]@{
                SiteName         = $SiteName
                IPAddress        = $IPAddress
                DomainController = $DomainController
            }

        } -ErrorAction Stop

        [PSCustomObject]@{
            ComputerName     = $Computer
            IPAddress        = $Data.IPAddress
            SiteName         = $Data.SiteName
            DomainController = $Data.DomainController
            Status           = "Success"
        }
    }
    catch {

        [PSCustomObject]@{
            ComputerName     = $Computer
            IPAddress        = ""
            SiteName         = ""
            DomainController = ""
            Status           = $_.Exception.Message
        }
    }
}

$Results | Export-Csv `
    -Path $CsvOutput `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host ""
Write-Host "Report saved to $CsvOutput" -ForegroundColor Green
