<#
.SYNOPSIS
    Deploys the custom anti-phishing policy with impersonation protection.

.DESCRIPTION
    Runbook 11 - Anti-phishing and Anti-malware Policies, Step 2.
    Applies to: All variants.

    Creates an anti-phish policy with user impersonation protection for named
    executives, domain impersonation protection for sending domains and partner
    domains, spoof intelligence, mailbox intelligence, and aggressive phish threshold.

.PARAMETER PolicyName
    Display name. Default: "SMB Baseline Anti-Phish".

.PARAMETER UsersToProtect
    Array of hashtables with Name and Email keys. Example:
        @(
            @{ Name = "Jane CEO";  Email = "jane@contoso.com" },
            @{ Name = "Bob CFO";   Email = "bob@contoso.com" }
        )

.PARAMETER DomainsToProtect
    Array of sending domains to protect from impersonation.

.PARAMETER PartnerDomainsToProtect
    Array of external partner domains commonly impersonated against the organization.

.PARAMETER PhishThreshold
    1 (Standard), 2 (Aggressive), 3 (More aggressive), 4 (Most aggressive).
    Default: 3.

.PARAMETER AssignToAllRecipients
    Creates the rule assigning the policy to all recipients.

.EXAMPLE
    ./11-Deploy-AntiPhishPolicy.ps1 `
        -PolicyName "SMB Baseline Anti-Phish" `
        -UsersToProtect @(
            @{ Name = "Jane CEO"; Email = "jane@contoso.com" },
            @{ Name = "Bob CFO";  Email = "bob@contoso.com" }
        ) `
        -DomainsToProtect @("contoso.com") `
        -PartnerDomainsToProtect @("accounting-firm.com") `
        -PhishThreshold 3 `
        -AssignToAllRecipients

.NOTES
    Required Exchange Online role: Security Administrator or higher.
#>

[CmdletBinding()]
param(
    [string]$PolicyName = "SMB Baseline Anti-Phish",

    [Parameter(Mandatory = $true)]
    [array]$UsersToProtect,

    [Parameter(Mandatory = $true)]
    [string[]]$DomainsToProtect,

    [string[]]$PartnerDomainsToProtect = @(),

    [ValidateRange(1, 4)]
    [int]$PhishThreshold = 3,

    [switch]$AssignToAllRecipients
)

$ErrorActionPreference = "Stop"

try {
    $null = Get-OrganizationConfig -ErrorAction Stop
} catch {
    throw "Not connected to Exchange Online."
}

Write-Host "=== Deploy Anti-Phish Policy ===" -ForegroundColor Cyan
Write-Host "Policy: $PolicyName"
Write-Host "Phish threshold: $PhishThreshold"
Write-Host "Users to protect: $($UsersToProtect.Count)"
Write-Host "Domains to protect: $($DomainsToProtect.Count)"
Write-Host "Partner domains: $($PartnerDomainsToProtect.Count)"
Write-Host ""

# Check for existing policy
$existing = Get-AntiPhishPolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Policy '$PolicyName' already exists. Updating..." -ForegroundColor Yellow
    $action = "Update"
} else {
    $action = "Create"
}

# Build TargetedUsersToProtect in the format anti-phish expects
$targetedUsers = @()
foreach ($u in $UsersToProtect) {
    $targetedUsers += "$($u.Name);$($u.Email)"
}

$allDomains = @($DomainsToProtect) + @($PartnerDomainsToProtect) | Select-Object -Unique

$policyParams = @{
    Name = $PolicyName
    Enabled = $true

    # Threshold
    PhishThresholdLevel = $PhishThreshold

    # Mailbox intelligence
    EnableMailboxIntelligence = $true
    EnableMailboxIntelligenceProtection = $true
    MailboxIntelligenceProtectionAction = "Quarantine"

    # User impersonation
    EnableTargetedUserProtection = ($UsersToProtect.Count -gt 0)
    TargetedUsersToProtect = $targetedUsers
    TargetedUserProtectionAction = "Quarantine"

    # Domain impersonation
    EnableTargetedDomainsProtection = ($allDomains.Count -gt 0)
    TargetedDomainsToProtect = $allDomains
    TargetedDomainProtectionAction = "Quarantine"
    EnableOrganizationDomainsProtection = $true

    # Spoof intelligence
    EnableSpoofIntelligence = $true
    AuthenticationFailAction = "MoveToJmf"  # Junk folder for spoof failures
    HonorDmarcPolicy = $true
    DmarcQuarantineAction = "Quarantine"
    DmarcRejectAction = "Reject"

    # Safety tips
    EnableFirstContactSafetyTips = $true
    EnableSimilarUsersSafetyTips = $true
    EnableSimilarDomainsSafetyTips = $true
    EnableUnusualCharactersSafetyTips = $true
    EnableUnauthenticatedSender = $true
    EnableViaTag = $true

    # Quarantine tags
    TargetedUserQuarantineTag = "AdminOnlyAccessPolicy"
    MailboxIntelligenceQuarantineTag = "AdminOnlyAccessPolicy"
    TargetedDomainQuarantineTag = "AdminOnlyAccessPolicy"
    SpoofQuarantineTag = "DefaultFullAccessWithNotificationPolicy"
}

try {
    if ($action -eq "Create") {
        $policy = New-AntiPhishPolicy @policyParams
        Write-Host "Policy created." -ForegroundColor Green
    } else {
        # Update uses Set-AntiPhishPolicy with Identity instead of Name
        $policyParams.Remove("Name") | Out-Null
        $policyParams["Identity"] = $PolicyName
        Set-AntiPhishPolicy @policyParams
        Write-Host "Policy updated." -ForegroundColor Green
    }
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    exit 1
}

# Create or update the rule
if ($AssignToAllRecipients) {
    $ruleName = "$PolicyName - All Recipients"
    $existingRule = Get-AntiPhishRule -Identity $ruleName -ErrorAction SilentlyContinue

    $ruleParams = @{
        Name = $ruleName
        AntiPhishPolicy = $PolicyName
        RecipientDomainIs = (Get-AcceptedDomain | Select-Object -ExpandProperty DomainName)
        Priority = 0
        Enabled = $true
    }

    try {
        if ($existingRule) {
            $ruleParams.Remove("Name") | Out-Null
            $ruleParams["Identity"] = $ruleName
            Set-AntiPhishRule @ruleParams
            Write-Host "Rule updated." -ForegroundColor Green
        } else {
            New-AntiPhishRule @ruleParams | Out-Null
            Write-Host "Rule created; policy assigned to all recipients in accepted domains." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Policy created but rule assignment failed: $_"
    }
}

Write-Host ""
Write-Host "Next:" -ForegroundColor Cyan
Write-Host "  1. Monitor for 7 days: ./11-Monitor-EmailThreats.ps1"
Write-Host "  2. Tune based on false positives"
Write-Host "  3. Deploy anti-malware: ./11-Deploy-AntiMalwarePolicy.ps1"
