<#
.SYNOPSIS
    Deploys indicators of compromise to Defender for Endpoint.

.DESCRIPTION
    Runbook 28 - EDR Tuning, Step 4.

    Imports IOCs from a CSV file into Defender. Supports domain, IP, file SHA256,
    and certificate indicators. Each indicator has severity and action.

    CSV format:
    IndicatorType,Indicator,Severity,Action,Description,ExpireOn

.PARAMETER IOCFilePath
    Path to IOC CSV.

.EXAMPLE
    ./28-Deploy-IOCs.ps1 -IOCFilePath "./iocs.csv"

.NOTES
    Required Graph scopes: SecurityActions.ReadWrite.All or Ti.ReadWrite (Defender XDR).
    API: https://graph.microsoft.com/v1.0/security/tiIndicators
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IOCFilePath
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

if (-not (Test-Path $IOCFilePath)) {
    # Generate template if file doesn't exist
    $template = @"
IndicatorType,Indicator,Severity,Action,Description,ExpireOn
Domain,bad-example.com,High,Block,Known phishing infrastructure,2027-01-01
IP,192.0.2.100,High,Block,Incident 2026-01-15 attacker IP,2027-01-01
FileSHA256,0000000000000000000000000000000000000000000000000000000000000000,High,Block,Malware from incident 2026-01-15,2027-01-01
"@
    $template | Out-File -FilePath $IOCFilePath -Encoding UTF8
    Write-Host "IOC template written to $IOCFilePath" -ForegroundColor Yellow
    Write-Host "Populate with tenant-specific IOCs and re-run." -ForegroundColor Yellow
    exit 0
}

$iocs = Import-Csv $IOCFilePath

Write-Host "=== Deploy IOCs ===" -ForegroundColor Cyan
Write-Host "IOCs in file: $($iocs.Count)"
Write-Host ""

$deployed = 0
$failed = 0

foreach ($ioc in $iocs) {
    # Skip template rows
    if ($ioc.Indicator -match "^0+$" -or $ioc.Indicator -eq "bad-example.com") {
        continue
    }

    $body = @{
        action = $ioc.Action.ToLower()
        severity = $ioc.Severity.ToLower()
        description = $ioc.Description
        expirationDateTime = $ioc.ExpireOn
        targetProduct = "Microsoft Defender ATP"
        indicatorType = switch ($ioc.IndicatorType) {
            "Domain"      { "domainName" }
            "IP"          { "networkIPv4" }
            "FileSHA256"  { "fileHash" }
            "Certificate" { "certificateSha256" }
        }
    }

    if ($ioc.IndicatorType -eq "Domain") { $body["domainName"] = $ioc.Indicator }
    elseif ($ioc.IndicatorType -eq "IP") { $body["networkIPv4"] = $ioc.Indicator }
    elseif ($ioc.IndicatorType -eq "FileSHA256") { $body["fileHashType"] = "sha256"; $body["fileHashValue"] = $ioc.Indicator }

    try {
        $uri = "https://graph.microsoft.com/v1.0/security/tiIndicators"
        Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($body | ConvertTo-Json -Depth 5) -ErrorAction Stop | Out-Null
        Write-Host "  Deployed: $($ioc.IndicatorType) $($ioc.Indicator)" -ForegroundColor Green
        $deployed++
    } catch {
        Write-Host "  Failed: $($ioc.Indicator) - $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Summary: $deployed deployed, $failed failed." -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
