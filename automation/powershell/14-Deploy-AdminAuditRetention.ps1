<#
.SYNOPSIS
    Deploys an extended-retention policy for administrative audit events.

.DESCRIPTION
    Runbook 14 - Unified Audit Log Verification and Retention, Step 3.
    Applies to: All variants.

    Creates a UnifiedAuditLogRetentionPolicy targeting administrative events that
    warrant longer retention than default user activity. Default 365 days; with
    -RequireAuditPremium the script verifies Audit Premium licensing and supports
    up to 3650 days (10 years).

.PARAMETER PolicyName
    Display name for the policy.

.PARAMETER RetentionDays
    Retention duration. Valid: 180, 365, 1095 (3 years), 2555 (7 years), 3650 (10 years).
    Values above 365 require E5 with Audit Premium licensing.

.PARAMETER RequireAuditPremium
    Verifies Audit Premium licensing before creating policy with >365-day retention.

.EXAMPLE
    ./14-Deploy-AdminAuditRetention.ps1 -PolicyName "Administrative Events Extended Retention" -RetentionDays 365

.NOTES
    Required role: Compliance Administrator.
    Run Connect-IPPSSession before running this script.
#>

[CmdletBinding()]
param(
    [string]$PolicyName = "Administrative Events Extended Retention",

    [ValidateSet(180, 365, 1095, 2555, 3650)]
    [int]$RetentionDays = 365,

    [switch]$RequireAuditPremium
)

$ErrorActionPreference = "Stop"

# Retention > 365 days requires Audit Premium
if ($RetentionDays -gt 365 -and $RequireAuditPremium) {
    try {
        $skus = Get-MgSubscribedSku -ErrorAction SilentlyContinue
        $hasAuditPremium = $skus | Where-Object {
            $_.SkuPartNumber -in @("M365_AUDIT_PLATFORM", "Microsoft_365_E5_Insider_Risk_Management")
        }
        if (-not $hasAuditPremium) {
            throw "Audit Premium licensing not detected. Cannot apply retention beyond 365 days without Audit Premium."
        }
    } catch {
        throw "Licensing verification failed: $_"
    }
}

Write-Host "=== Deploy Administrative Audit Retention ===" -ForegroundColor Cyan
Write-Host "Policy: $PolicyName"
Write-Host "Retention: $RetentionDays days"
Write-Host ""

# Record types and operations to target
$recordTypes = @(
    "AzureActiveDirectory",           # Entra ID events
    "AzureActiveDirectoryAccountLogon",
    "AzureActiveDirectoryStsLogon",
    "MicrosoftStream",                # Streams sharing events
    "ExchangeAdmin",                  # Exchange admin actions
    "ExchangeItem",                   # For mailbox permission changes
    "ExchangeItemGroup",
    "SharePointFileOperation",        # Limited to file-permission changes
    "ThreatIntelligence",
    "SecurityComplianceCenterEOPCmdlet"
)

$operations = @(
    "Add member to role.",
    "Remove member from role.",
    "Add delegated permission grant.",
    "Consent to application.",
    "Add application.",
    "Update application.",
    "Add service principal.",
    "Update service principal.",
    "Add service principal credentials.",
    "Remove service principal credentials.",
    "Update StsRefreshTokenValidFrom Timestamp.",
    "Update user.",
    "Change user password.",
    "Reset user password.",
    "Set-ConditionalAccessPolicy",
    "New-ConditionalAccessPolicy",
    "Remove-ConditionalAccessPolicy",
    "Set-InboxRule",
    "New-InboxRule"
)

$existingPolicy = Get-UnifiedAuditLogRetentionPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

try {
    if ($existingPolicy) {
        Write-Host "Policy already exists; updating..." -ForegroundColor Yellow
        Set-UnifiedAuditLogRetentionPolicy `
            -Identity $PolicyName `
            -RetentionDuration $RetentionDays `
            -Priority 1
        Write-Host "Policy updated." -ForegroundColor Green
    } else {
        New-UnifiedAuditLogRetentionPolicy `
            -Name $PolicyName `
            -Description "Runbook 14 administrative events. Retention $RetentionDays days." `
            -RetentionDuration $RetentionDays `
            -Priority 1 `
            -RecordTypes $recordTypes `
            -Operations $operations
        Write-Host "Policy created." -ForegroundColor Green
    }
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "  - Not connected to Security and Compliance PowerShell (run Connect-IPPSSession)"
    Write-Host "  - Insufficient licensing for requested retention duration"
    exit 1
}

Write-Host ""
Write-Host "Administrative events are now retained for $RetentionDays days." -ForegroundColor Green
Write-Host "User activity events retain at the tenant's default retention." -ForegroundColor Cyan
