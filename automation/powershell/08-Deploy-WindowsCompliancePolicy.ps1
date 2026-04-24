<#
.SYNOPSIS
    Deploys the Windows compliance policy.

.DESCRIPTION
    Runbook 08 - Windows Device Compliance Policy, Step 2.
    Applies to: All variants.

    Creates the primary Windows compliance policy with baseline settings (BitLocker,
    Secure Boot, Code Integrity, OS version, password, firewall, antivirus) and assigns
    it to all Windows devices. Non-compliance actions are initially set to notify-only;
    graduated enforcement is configured by 08-Configure-ComplianceActions.ps1 after
    observation.

.PARAMETER PolicyName
    Display name for the compliance policy.

.PARAMETER MinimumOSVersion
    Minimum Windows OS version. Default: 10.0.19045 (Windows 10 22H2).
    Use 10.0.22631 for Windows 11 23H2 as the minimum.

.PARAMETER NonComplianceActionMode
    NotifyOnly (default for initial deployment) or Graduated (for production).

.PARAMETER AssignToAllDevices
    Assigns policy to all Windows devices. Without this switch, policy is created but unassigned.

.EXAMPLE
    ./08-Deploy-WindowsCompliancePolicy.ps1 `
        -PolicyName "Windows Compliance Baseline" `
        -NonComplianceActionMode "NotifyOnly" `
        -AssignToAllDevices

.NOTES
    Required Graph scopes:
        DeviceManagementConfiguration.ReadWrite.All
#>

[CmdletBinding()]
param(
    [string]$PolicyName = "Windows Compliance Baseline",
    [string]$MinimumOSVersion = "10.0.19045",
    [ValidateSet("NotifyOnly", "Graduated")]
    [string]$NonComplianceActionMode = "NotifyOnly",
    [switch]$AssignToAllDevices
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Deploy Windows Compliance Policy ===" -ForegroundColor Cyan
Write-Host "Policy: $PolicyName"
Write-Host "Minimum OS: $MinimumOSVersion"
Write-Host ""

# Check if policy already exists
$existing = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" -ErrorAction SilentlyContinue
$conflict = $existing.value | Where-Object { $_.displayName -eq $PolicyName }
if ($conflict) {
    Write-Host "Policy '$PolicyName' already exists. Modify the existing policy or choose a different name." -ForegroundColor Yellow
    exit 1
}

# Build the compliance policy body
$body = @{
    "@odata.type" = "#microsoft.graph.windows10CompliancePolicy"
    displayName = $PolicyName
    description = "Created by Runbook 08. Baseline Windows compliance requirements."

    # Device Health
    bitLockerEnabled = $true
    secureBootEnabled = $true
    codeIntegrityEnabled = $true

    # Device Properties
    osMinimumVersion = $MinimumOSVersion
    osMaximumVersion = $null
    mobileOsMinimumVersion = $null
    mobileOsMaximumVersion = $null

    # System Security - password
    passwordRequired = $true
    passwordBlockSimple = $true
    passwordMinimumLength = 12
    passwordRequiredType = "deviceDefault"
    passwordMinutesOfInactivityBeforeLock = 15
    passwordExpirationDays = 365
    passwordPreviousPasswordBlockCount = 5
    passwordRequiredToUnlockFromIdle = $true

    # System Security - storage encryption
    storageRequireEncryption = $true

    # System Security - firewall and defender
    activeFirewallRequired = $true
    antivirusRequired = $true
    antiSpywareRequired = $true
    defenderEnabled = $true
    signatureOutOfDate = $false
    rtpEnabled = $true

    # TPM is added by Runbook 10; not set here
    tpmRequired = $false

    # Required: scheduled actions for rule
    scheduledActionsForRule = @(
        @{
            ruleName = "PasswordRequired"
            scheduledActionConfigurations = @(
                @{
                    actionType = "block"
                    gracePeriodHours = 168  # 7 days grace period
                    notificationTemplateId = ""
                    notificationMessageCCList = @()
                }
            )
        }
    )
}

Write-Host "Creating compliance policy..." -ForegroundColor Cyan

try {
    $policy = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"

    Write-Host "Policy created: $($policy.id)" -ForegroundColor Green
} catch {
    Write-Host "Failed to create policy: $_" -ForegroundColor Red
    exit 1
}

# Assign to all devices if requested
if ($AssignToAllDevices) {
    Write-Host "Assigning policy to all devices..." -ForegroundColor Cyan

    $assignment = @{
        assignments = @(
            @{
                target = @{
                    "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
                }
            }
        )
    }

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
            -Body ($assignment | ConvertTo-Json -Depth 10) `
            -ContentType "application/json"

        Write-Host "Policy assigned." -ForegroundColor Green
    } catch {
        Write-Warning "Policy created but assignment failed: $_"
    }
}

Write-Host ""
Write-Host "Next:" -ForegroundColor Cyan
Write-Host "  1. Monitor compliance for 7 days: ./08-Monitor-WindowsCompliance.ps1"
Write-Host "  2. Resolve failure patterns"
Write-Host "  3. Configure graduated non-compliance actions: ./08-Configure-ComplianceActions.ps1"
Write-Host "  4. Enforce CA007: ./08-Enforce-CA007.ps1"
Write-Host ""

[PSCustomObject]@{
    PolicyId = $policy.id
    PolicyName = $PolicyName
    Assigned = [bool]$AssignToAllDevices
} | ConvertTo-Json
