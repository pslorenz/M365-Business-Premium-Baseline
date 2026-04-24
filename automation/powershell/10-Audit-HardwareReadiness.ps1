<#
.SYNOPSIS
    Audits the Windows fleet for VBS, Credential Guard, and TPM 2.0 hardware readiness.

.DESCRIPTION
    Runbook 10 - VBS, Credential Guard, and TPM Hardware Enforcement, Step 1.
    Applies to: All variants.

    Queries Intune for enrolled Windows devices and reports per device: manufacturer,
    model, OS version, OS edition, TPM specification version, Secure Boot state, and
    a VBS readiness classification.

.PARAMETER OutputPath
    Output CSV path. Default: timestamped filename in current directory.

.EXAMPLE
    ./10-Audit-HardwareReadiness.ps1 -OutputPath "./hardware-audit-$(Get-Date -Format 'yyyyMMdd').csv"

.NOTES
    Required Graph scopes:
        DeviceManagementManagedDevices.Read.All
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "./hardware-audit-$(Get-Date -Format 'yyyyMMdd').csv"
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Hardware Readiness Audit ===" -ForegroundColor Cyan
Write-Host ""

# Basic device inventory from managed devices
$devices = Get-MgDeviceManagementManagedDevice -All | Where-Object {
    $_.OperatingSystem -eq "Windows"
}

Write-Host "Windows devices: $($devices.Count)"
Write-Host ""

$results = @()

foreach ($d in $devices) {
    # Try to get additional detail from Intune device inventory
    # Note: TPM info and VBS status may not be in the basic managed device object;
    # for full detail, the per-device inventory endpoint is required. This script
    # reports what is available from the primary inventory.

    # Readiness classification (best-effort)
    $readiness = "Unknown"
    if ($d.OSVersion -like "10.0.22*" -or $d.OSVersion -like "10.0.26*") {
        # Windows 11
        $readiness = "Likely ready"
    } elseif ($d.OSVersion -like "10.0.19*") {
        # Windows 10 22H2
        $readiness = "Hardware-dependent"
    } else {
        $readiness = "Below minimum OS"
    }

    $results += [PSCustomObject]@{
        DeviceName     = $d.DeviceName
        UPN            = $d.UserPrincipalName
        Manufacturer   = $d.Manufacturer
        Model          = $d.Model
        OSVersion      = $d.OSVersion
        SkuFamily      = $d.SkuFamily
        Compliance     = $d.ComplianceState
        LastSync       = $d.LastSyncDateTime
        Readiness      = $readiness
    }
}

$results | Sort-Object Manufacturer, Model | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Audit written to: $OutputPath" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "Readiness summary:" -ForegroundColor Cyan
$results | Group-Object Readiness | ForEach-Object {
    $pct = [math]::Round(($_.Count / $results.Count) * 100, 1)
    Write-Host "  $($_.Name): $($_.Count) ($pct%)"
}

Write-Host ""
Write-Host "Note: TPM version and Secure Boot state require per-device query or endpoint agent data." -ForegroundColor Yellow
Write-Host "For full audit including TPM specification, consider Defender for Endpoint inventory or device-side scripting." -ForegroundColor Yellow
