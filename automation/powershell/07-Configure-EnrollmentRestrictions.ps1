<#
.SYNOPSIS
    Configures Intune enrollment restrictions for platform and OS version.

.DESCRIPTION
    Runbook 07 - Intune Enrollment Strategy, Step 8.
    Applies to: All variants.

    Sets platform and version restrictions on device enrollment. Restrictions prevent
    enrollment of devices that cannot meet baseline compliance (outdated OS versions,
    disallowed ownership types). Paired with the BYOD position documented in the
    runbook.

.PARAMETER BlockPersonalAndroid
    If true, personal Android devices cannot enroll (corporate-owned only).

.PARAMETER BlockPersonaliOS
    If true, personal iOS devices cannot enroll.

.PARAMETER BlockPersonalWindows
    If true, personal Windows devices cannot enroll. Default: true (most SMBs do not support Windows BYOD).

.PARAMETER BlockPersonalMacOS
    If true, personal macOS devices cannot enroll. Default: true.

.PARAMETER MinimumWindowsVersion
    Minimum Windows 10/11 version. Example: "10.0.19045" (Windows 10 22H2).

.PARAMETER MinimumiOSVersion
    Minimum iOS/iPadOS version. Example: "16.0".

.PARAMETER MinimumAndroidVersion
    Minimum Android version. Example: "11.0".

.EXAMPLE
    ./07-Configure-EnrollmentRestrictions.ps1 `
        -BlockPersonalAndroid $false `
        -BlockPersonaliOS $false `
        -BlockPersonalWindows $true `
        -BlockPersonalMacOS $true `
        -MinimumWindowsVersion "10.0.19045" `
        -MinimumiOSVersion "16.0" `
        -MinimumAndroidVersion "11.0"

.NOTES
    Required Graph scopes:
        DeviceManagementServiceConfig.ReadWrite.All
#>

[CmdletBinding()]
param(
    [bool]$BlockPersonalAndroid = $false,
    [bool]$BlockPersonaliOS = $false,
    [bool]$BlockPersonalWindows = $true,
    [bool]$BlockPersonalMacOS = $true,
    [string]$MinimumWindowsVersion = "10.0.19045",
    [string]$MinimumiOSVersion = "16.0",
    [string]$MinimumAndroidVersion = "11.0"
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Enrollment Restrictions ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Personal device enrollment:"
Write-Host "  Android:  $(if ($BlockPersonalAndroid) { 'BLOCKED' } else { 'ALLOWED' })"
Write-Host "  iOS:      $(if ($BlockPersonaliOS) { 'BLOCKED' } else { 'ALLOWED' })"
Write-Host "  Windows:  $(if ($BlockPersonalWindows) { 'BLOCKED' } else { 'ALLOWED' })"
Write-Host "  macOS:    $(if ($BlockPersonalMacOS) { 'BLOCKED' } else { 'ALLOWED' })"
Write-Host ""
Write-Host "Minimum OS versions:"
Write-Host "  Windows:  $MinimumWindowsVersion"
Write-Host "  iOS:      $MinimumiOSVersion"
Write-Host "  Android:  $MinimumAndroidVersion"
Write-Host ""

$confirm = Read-Host "Proceed? (type 'yes')"
if ($confirm -ne "yes") { Write-Host "Aborted."; exit 1 }

# Update the default platform restrictions policy
# Default policy ID follows a standard pattern; retrieve it first
try {
    $policies = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=deviceEnrollmentConfigurationType eq 'platformRestrictions'"

    $defaultPolicy = $policies.value | Where-Object { $_.priority -eq 0 } | Select-Object -First 1
    if (-not $defaultPolicy) {
        throw "Default platform restrictions policy not found."
    }

    $policyId = $defaultPolicy.id
    Write-Host "Updating default platform restrictions policy: $policyId" -ForegroundColor Cyan
} catch {
    Write-Host "Failed to locate policy: $_" -ForegroundColor Red
    exit 1
}

$body = @{
    "@odata.type" = "#microsoft.graph.defaultDeviceEnrollmentPlatformRestrictionsConfiguration"
    displayName = $defaultPolicy.displayName
    description = "Updated by Runbook 07. Platform and version restrictions per baseline."
    priority = 0
    iosRestriction = @{
        platformBlocked = $false
        personalDeviceEnrollmentBlocked = $BlockPersonaliOS
        osMinimumVersion = $MinimumiOSVersion
        osMaximumVersion = $null
        blockedManufacturers = @()
    }
    windowsRestriction = @{
        platformBlocked = $false
        personalDeviceEnrollmentBlocked = $BlockPersonalWindows
        osMinimumVersion = $MinimumWindowsVersion
        osMaximumVersion = $null
        blockedManufacturers = @()
    }
    androidRestriction = @{
        platformBlocked = $false
        personalDeviceEnrollmentBlocked = $BlockPersonalAndroid
        osMinimumVersion = $MinimumAndroidVersion
        osMaximumVersion = $null
        blockedManufacturers = @()
    }
    androidForWorkRestriction = @{
        platformBlocked = $false
        personalDeviceEnrollmentBlocked = $BlockPersonalAndroid
        osMinimumVersion = $MinimumAndroidVersion
        osMaximumVersion = $null
        blockedManufacturers = @()
    }
    macOSRestriction = @{
        platformBlocked = $false
        personalDeviceEnrollmentBlocked = $BlockPersonalMacOS
        osMinimumVersion = $null
        osMaximumVersion = $null
        blockedManufacturers = @()
    }
    macRestriction = @{
        platformBlocked = $false
        personalDeviceEnrollmentBlocked = $BlockPersonalMacOS
        osMinimumVersion = $null
        osMaximumVersion = $null
    }
}

try {
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$policyId" `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"

    Write-Host ""
    Write-Host "Enrollment restrictions updated." -ForegroundColor Green
    Write-Host "New devices attempting to enroll will be evaluated against the new restrictions." -ForegroundColor Cyan
    Write-Host "Devices already enrolled are not affected." -ForegroundColor Cyan
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    exit 1
}
