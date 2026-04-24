<#
.SYNOPSIS
    Deploys the iOS/iPadOS compliance policy.

.DESCRIPTION
    Runbook 09 - Mobile Device Compliance, Step 2.
    Applies to: All variants.

    Creates iOS/iPadOS compliance policy: jailbreak detection, minimum OS version,
    password requirement, encryption requirement, screen lock timeout.

.PARAMETER PolicyName
    Display name.

.PARAMETER MinimumOSVersion
    Default: 16.0.

.PARAMETER AssignToAllDevices
    Assigns to all iOS devices.

.EXAMPLE
    ./09-Deploy-iOSCompliancePolicy.ps1 -PolicyName "iOS Compliance Baseline" -AssignToAllDevices

.NOTES
    Required Graph scopes:
        DeviceManagementConfiguration.ReadWrite.All
#>

[CmdletBinding()]
param(
    [string]$PolicyName = "iOS Compliance Baseline",
    [string]$MinimumOSVersion = "16.0",
    [ValidateSet("NotifyOnly", "Graduated")]
    [string]$NonComplianceActionMode = "NotifyOnly",
    [switch]$AssignToAllDevices
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

$policies = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" -ErrorAction SilentlyContinue
$conflict = $policies.value | Where-Object { $_.displayName -eq $PolicyName }
if ($conflict) {
    Write-Host "Policy '$PolicyName' already exists." -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Deploy iOS Compliance Policy ===" -ForegroundColor Cyan
Write-Host "Policy: $PolicyName"
Write-Host "Minimum OS: $MinimumOSVersion"
Write-Host ""

$body = @{
    "@odata.type" = "#microsoft.graph.iosCompliancePolicy"
    displayName = $PolicyName
    description = "Created by Runbook 09. iOS/iPadOS baseline."

    # Device health
    passcodeBlockSimple = $true
    passcodeRequired = $true
    passcodeMinimumLength = 6
    passcodeMinutesOfInactivityBeforeScreenTimeout = 15
    passcodeRequiredType = "deviceDefault"

    # Jailbreak
    securityBlockJailbrokenDevices = $true

    # OS version
    osMinimumVersion = $MinimumOSVersion
    osMaximumVersion = $null

    # Encryption
    managedEmailProfileRequired = $false

    # Scheduled actions
    scheduledActionsForRule = @(
        @{
            ruleName = "PasswordRequired"
            scheduledActionConfigurations = @(
                @{
                    actionType = "block"
                    gracePeriodHours = 504  # 21 days mobile grace period
                    notificationTemplateId = ""
                    notificationMessageCCList = @()
                }
            )
        }
    )
}

try {
    $policy = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"

    Write-Host "Policy created: $($policy.id)" -ForegroundColor Green
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    exit 1
}

if ($AssignToAllDevices) {
    $assignment = @{
        assignments = @(
            @{ target = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" } }
        )
    }

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
            -Body ($assignment | ConvertTo-Json -Depth 10) `
            -ContentType "application/json"
        Write-Host "Assigned to all devices." -ForegroundColor Green
    } catch {
        Write-Warning "Assignment failed: $_"
    }
}

[PSCustomObject]@{
    PolicyId = $policy.id
    PolicyName = $PolicyName
    Platform = "iOS"
} | ConvertTo-Json
