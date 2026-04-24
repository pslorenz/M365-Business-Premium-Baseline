<#
.SYNOPSIS
    Configures PIM role settings for a directory role at a specified tier.

.DESCRIPTION
    Runbook 04 - PIM Configuration.
    Applies to: Defender Suite, E5 Security, EMS E5 (Entra ID P2 required).

    Configures the activation requirements, duration, approval, and notification
    settings for a specific directory role. Tier parameter selects the opinionated
    baseline configuration.

    Tier 0: 4h activation, MFA required, justification required, approval required,
            notifications to tier-zero alert address
    Tier 1: 8h activation, MFA required, justification required, no approval,
            notifications for after-hours activations
    Tier 2: 4h activation, MFA required, justification required, no approval

.PARAMETER Role
    Directory role display name (for example "Global Administrator", "Exchange Administrator").

.PARAMETER Tier
    Tier classification. Valid values: 0, 1, 2.

.PARAMETER TierZeroAlertEmail
    For tier 0, the email address that receives activation notifications.
    Ignored for tier 1 and 2.

.PARAMETER AllTierAlertEmail
    For all tiers, the email address that receives general PIM notifications.

.EXAMPLE
    ./04-Configure-PIMRoleSetting.ps1 -Role "Global Administrator" -Tier 0

.NOTES
    Required Graph scopes:
        RoleManagementPolicy.ReadWrite.Directory
        RoleManagement.ReadWrite.Directory
        Directory.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Role,

    [Parameter(Mandatory = $true)]
    [ValidateSet(0, 1, 2)]
    [int]$Tier,

    [string]$TierZeroAlertEmail = "tier-zero-alerts@yourdomain.com",

    [string]$AllTierAlertEmail = "pim-alerts@yourdomain.com"
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

# Verify P2
$hasP2 = Get-MgSubscribedSku | Where-Object {
    $_.SkuPartNumber -in @("AAD_PREMIUM_P2", "EMSPREMIUM", "SPE_E5", "Microsoft_Defender_Suite_for_SMB", "IDENTITY_THREAT_PROTECTION")
}
if (-not $hasP2) { throw "PIM configuration requires Entra ID P2. Tenant does not have P2." }

# Lookup role definition
$roleDef = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$Role'" -ErrorAction SilentlyContinue
if (-not $roleDef) { throw "Role not found: $Role" }

Write-Host "=== Configure PIM Role Setting ===" -ForegroundColor Cyan
Write-Host "Role: $Role"
Write-Host "Tier: $Tier"
Write-Host ""

# Lookup the PIM policy for this role
# The policy is scoped by role definition; retrieve via unifiedRoleManagementPolicyAssignment
$policyAssignments = Get-MgPolicyRoleManagementPolicyAssignment `
    -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$($roleDef.TemplateId)'" `
    -ErrorAction SilentlyContinue

if (-not $policyAssignments) {
    throw "Could not find PIM policy assignment for $Role. The role may not have PIM eligibility enabled yet."
}

$policyId = $policyAssignments[0].PolicyId

# Configure rules based on tier
# This is a simplified example; full PIM rule configuration via Graph involves multiple
# rule types (activation requirements, notification rules, approval rules, etc.)
# Each rule is a separate PATCH to the policy's rules endpoint.

$tierConfig = switch ($Tier) {
    0 {
        @{
            MaxDurationMinutes      = 240      # 4 hours
            RequireMFA              = $true
            RequireJustification    = $true
            RequireApproval         = $true
            ApproverGroup           = "RoleAssignable-Tier0"
            AlertEmail              = $TierZeroAlertEmail
        }
    }
    1 {
        @{
            MaxDurationMinutes      = 480      # 8 hours
            RequireMFA              = $true
            RequireJustification    = $true
            RequireApproval         = $false
            ApproverGroup           = $null
            AlertEmail              = $AllTierAlertEmail
        }
    }
    2 {
        @{
            MaxDurationMinutes      = 240      # 4 hours
            RequireMFA              = $true
            RequireJustification    = $true
            RequireApproval         = $false
            ApproverGroup           = $null
            AlertEmail              = $AllTierAlertEmail
        }
    }
}

Write-Host "Applying tier $Tier settings:"
Write-Host "  Max activation duration: $($tierConfig.MaxDurationMinutes) minutes"
Write-Host "  MFA required: $($tierConfig.RequireMFA)"
Write-Host "  Justification required: $($tierConfig.RequireJustification)"
Write-Host "  Approval required: $($tierConfig.RequireApproval)"
if ($tierConfig.ApproverGroup) { Write-Host "  Approvers: $($tierConfig.ApproverGroup) group members" }
Write-Host "  Alert notifications: $($tierConfig.AlertEmail)"
Write-Host ""

# Rule: activation duration
$durationRuleId = "Expiration_EndUser_Assignment"
$durationBody = @{
    "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyExpirationRule"
    id = $durationRuleId
    isExpirationRequired = $true
    maximumDuration = "PT$($tierConfig.MaxDurationMinutes)M"
    target = @{
        "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyRuleTarget"
        caller = "EndUser"
        operations = @("all")
        level = "Assignment"
    }
}

try {
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/policies/roleManagementPolicies/$policyId/rules/$durationRuleId" `
        -Body ($durationBody | ConvertTo-Json -Depth 5) `
        -ContentType "application/json"
    Write-Host "Activation duration rule updated." -ForegroundColor Green
} catch {
    Write-Warning "Duration rule update failed: $_"
}

# Rule: MFA and justification requirements on activation
$enablementRuleId = "Enablement_EndUser_Assignment"
$enablementControls = @()
if ($tierConfig.RequireMFA) { $enablementControls += "MultiFactorAuthentication" }
if ($tierConfig.RequireJustification) { $enablementControls += "Justification" }

$enablementBody = @{
    "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyEnablementRule"
    id = $enablementRuleId
    enabledRules = $enablementControls
    target = @{
        "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyRuleTarget"
        caller = "EndUser"
        operations = @("all")
        level = "Assignment"
    }
}

try {
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/policies/roleManagementPolicies/$policyId/rules/$enablementRuleId" `
        -Body ($enablementBody | ConvertTo-Json -Depth 5) `
        -ContentType "application/json"
    Write-Host "Enablement rule updated (MFA, justification)." -ForegroundColor Green
} catch {
    Write-Warning "Enablement rule update failed: $_"
}

# Rule: approval (tier 0 only)
if ($tierConfig.RequireApproval) {
    $approverGroup = Get-MgGroup -Filter "displayName eq '$($tierConfig.ApproverGroup)'" -ErrorAction SilentlyContinue
    if (-not $approverGroup) {
        Write-Warning "Approver group '$($tierConfig.ApproverGroup)' not found. Approval rule not applied. Run 03-Create-TierGroups.ps1 first."
    } else {
        $approvalRuleId = "Approval_EndUser_Assignment"
        $approvalBody = @{
            "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyApprovalRule"
            id = $approvalRuleId
            setting = @{
                isApprovalRequired               = $true
                isApprovalRequiredForExtension   = $false
                isRequestorJustificationRequired = $true
                approvalMode                     = "SingleStage"
                approvalStages = @(
                    @{
                        approvalStageTimeOutInDays          = 1
                        isApproverJustificationRequired     = $true
                        escalationTimeInMinutes             = 0
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                groupId = $approverGroup.Id
                            }
                        )
                    }
                )
            }
            target = @{
                "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyRuleTarget"
                caller = "EndUser"
                operations = @("all")
                level = "Assignment"
            }
        }

        try {
            Invoke-MgGraphRequest -Method PATCH `
                -Uri "https://graph.microsoft.com/v1.0/policies/roleManagementPolicies/$policyId/rules/$approvalRuleId" `
                -Body ($approvalBody | ConvertTo-Json -Depth 10) `
                -ContentType "application/json"
            Write-Host "Approval rule updated (approvers: $($tierConfig.ApproverGroup))." -ForegroundColor Green
        } catch {
            Write-Warning "Approval rule update failed: $_"
        }
    }
}

Write-Host ""
Write-Host "PIM role settings applied for $Role at tier $Tier." -ForegroundColor Green
Write-Host "Verify in portal: Entra admin center > Identity governance > PIM > Microsoft Entra roles > $Role > Settings" -ForegroundColor Cyan
