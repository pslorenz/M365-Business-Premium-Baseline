<#
.SYNOPSIS
    Deploys the Safe Links policy with time-of-click URL protection.

.DESCRIPTION
    Runbook 12 - Safe Links and Safe Attachments, Step 1.
    Applies to: All variants.

.PARAMETER PolicyName
    Default: "SMB Baseline Safe Links".

.PARAMETER AssignToAllRecipients
    Creates the rule assigning the policy to all recipients.

.PARAMETER ExcludedGroups
    Optional groups to exclude from the policy.

.EXAMPLE
    ./12-Deploy-SafeLinks.ps1 -PolicyName "SMB Baseline Safe Links" -AssignToAllRecipients

.NOTES
    Required Exchange Online role: Security Administrator.
#>

[CmdletBinding()]
param(
    [string]$PolicyName = "SMB Baseline Safe Links",
    [switch]$AssignToAllRecipients,
    [string[]]$ExcludedGroups = @()
)

$ErrorActionPreference = "Stop"

try {
    $null = Get-OrganizationConfig -ErrorAction Stop
} catch {
    throw "Not connected to Exchange Online."
}

Write-Host "=== Deploy Safe Links Policy ===" -ForegroundColor Cyan
Write-Host "Policy: $PolicyName"
Write-Host ""

$existing = Get-SafeLinksPolicy -Identity $PolicyName -ErrorAction SilentlyContinue
$action = if ($existing) { "Update" } else { "Create" }

$policyParams = @{
    Name = $PolicyName

    # Email URL protection
    EnableSafeLinksForEmail = $true
    ScanUrls = $true
    DeliverMessageAfterScan = $true
    EnableForInternalSenders = $true
    DisableUrlRewrite = $false

    # User click handling
    TrackClicks = $true
    AllowClickThrough = $false

    # Teams protection
    EnableSafeLinksForTeams = $true

    # Office apps protection
    EnableSafeLinksForOffice = $true

    # Notification
    EnableOrganizationBranding = $false

    # Do-not-rewrite list (empty by default; organizations with specific internal apps
    # can add URLs here, documented with justification)
    DoNotRewriteUrls = @()
}

try {
    if ($action -eq "Create") {
        New-SafeLinksPolicy @policyParams | Out-Null
        Write-Host "Policy created." -ForegroundColor Green
    } else {
        $policyParams.Remove("Name") | Out-Null
        $policyParams["Identity"] = $PolicyName
        Set-SafeLinksPolicy @policyParams
        Write-Host "Policy updated." -ForegroundColor Green
    }
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    exit 1
}

# Rule assignment
if ($AssignToAllRecipients) {
    $ruleName = "$PolicyName - All Recipients"
    $existingRule = Get-SafeLinksRule -Identity $ruleName -ErrorAction SilentlyContinue

    $ruleParams = @{
        Name = $ruleName
        SafeLinksPolicy = $PolicyName
        RecipientDomainIs = (Get-AcceptedDomain | Select-Object -ExpandProperty DomainName)
        Priority = 0
        Enabled = $true
    }

    if ($ExcludedGroups.Count -gt 0) {
        $ruleParams["ExceptIfSentToMemberOf"] = $ExcludedGroups
    }

    try {
        if ($existingRule) {
            $ruleParams.Remove("Name") | Out-Null
            $ruleParams["Identity"] = $ruleName
            Set-SafeLinksRule @ruleParams
        } else {
            New-SafeLinksRule @ruleParams | Out-Null
        }
        Write-Host "Rule assigned." -ForegroundColor Green
        if ($ExcludedGroups.Count -gt 0) {
            Write-Host "  Excluded groups: $($ExcludedGroups -join ', ')" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Policy created but rule assignment failed: $_"
    }
}

Write-Host ""
Write-Host "Safe Links takes effect for new inbound messages immediately." -ForegroundColor Cyan
Write-Host "Teams and Office app protection may take a few hours to propagate." -ForegroundColor Cyan
