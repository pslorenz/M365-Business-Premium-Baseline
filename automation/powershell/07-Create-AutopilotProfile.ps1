<#
.SYNOPSIS
    Creates a Windows Autopilot deployment profile.

.DESCRIPTION
    Runbook 07 - Intune Enrollment Strategy, Step 3.
    Applies to: All variants.

    Creates an Autopilot deployment profile for zero-touch Windows provisioning.
    User-driven is the default for most SMB deployments; self-deploying is used
    for kiosks and shared-use devices.

.PARAMETER ProfileName
    Display name for the profile.

.PARAMETER DeploymentMode
    "UserDriven" (default, for assigned-user devices) or "SelfDeploying" (for kiosks).

.PARAMETER JoinType
    "EntraJoin" (cloud-only, default) or "EntraHybridJoin" (hybrid with on-prem AD).

.PARAMETER DeviceNamePattern
    Naming pattern using %SERIAL% or %RAND:<N>% tokens. Max 15 characters.
    Example: "CORP-%RAND:5%" produces CORP-A3F2K, CORP-9B7XM, etc.

.EXAMPLE
    ./07-Create-AutopilotProfile.ps1 `
        -ProfileName "Corporate Windows 11 - User-driven" `
        -DeploymentMode "UserDriven" `
        -JoinType "EntraJoin" `
        -DeviceNamePattern "CORP-%RAND:5%"

.NOTES
    Required Graph scopes:
        DeviceManagementServiceConfig.ReadWrite.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfileName,

    [ValidateSet("UserDriven", "SelfDeploying")]
    [string]$DeploymentMode = "UserDriven",

    [ValidateSet("EntraJoin", "EntraHybridJoin")]
    [string]$JoinType = "EntraJoin",

    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 15)]
    [string]$DeviceNamePattern
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Create Autopilot Deployment Profile ===" -ForegroundColor Cyan
Write-Host "Profile: $ProfileName"
Write-Host "Mode:    $DeploymentMode"
Write-Host "Join:    $JoinType"
Write-Host "Name:    $DeviceNamePattern"
Write-Host ""

# Map to Graph API types
$odataType = switch ($DeploymentMode) {
    "UserDriven"     { "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile" }
    "SelfDeploying"  { "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile" }
}

$deploymentProfileMode = switch ($DeploymentMode) {
    "UserDriven"     { "user-driven" }
    "SelfDeploying"  { "shared" }
}

$body = @{
    "@odata.type" = $odataType
    displayName = $ProfileName
    description = "Created by Runbook 07 ($DeploymentMode, $JoinType)"
    language = "os-default"
    locale = "os-default"
    extractHardwareHash = $true
    deviceNameTemplate = $DeviceNamePattern
    deviceType = "windowsPc"
    enableWhiteGlove = $true
    outOfBoxExperienceSetting = @{
        hidePrivacySettings = $true
        hideEULA = $false
        userType = "standard"
        deviceUsageType = $deploymentProfileMode
        skipKeyboardSelectionPage = $false
        hideEscapeLink = $true
    }
    enrollmentStatusScreenSettings = @{
        hideInstallationProgress = $false
        allowDeviceUseBeforeProfileAndAppInstallComplete = $false
        blockDeviceSetupRetryByUser = $false
        allowLogCollectionOnInstallFailure = $true
        customErrorMessage = ""
        installProgressTimeoutInMinutes = 60
        allowDeviceUseOnInstallFailure = $true
    }
    hybridAzureADJoinSkipConnectivityCheck = $false
}

try {
    $result = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles" `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"

    Write-Host "Profile created successfully." -ForegroundColor Green
    Write-Host "Profile ID: $($result.id)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next: assign profile to a device group in Intune admin center" -ForegroundColor Cyan
    Write-Host "  Intune > Devices > Windows > Windows Autopilot deployment profiles > $ProfileName > Assignments" -ForegroundColor Cyan

    [PSCustomObject]@{
        ProfileId = $result.id
        ProfileName = $ProfileName
        DeploymentMode = $DeploymentMode
        JoinType = $JoinType
    } | ConvertTo-Json
} catch {
    Write-Host "Failed to create Autopilot profile: $_" -ForegroundColor Red
    exit 1
}
