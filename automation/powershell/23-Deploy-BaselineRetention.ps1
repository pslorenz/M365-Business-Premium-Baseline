<#
.SYNOPSIS
    Deploys the three baseline retention policies.

.DESCRIPTION
    Runbook 23 - Retention and Records Management, Step 2.

    Creates:
    - Business Communications Retention (Exchange, 7 years retain)
    - Collaboration Content Retention (SharePoint, OneDrive, 7 years retain)
    - Teams Chat Retention (Teams chat, 3 years retain-then-delete)

.PARAMETER EmailRetentionYears
    Default: 7.

.PARAMETER CollaborationRetentionYears
    Default: 7.

.PARAMETER TeamsChatRetentionYears
    Default: 3.

.PARAMETER EmailAction
    Default: Retain. Options: Retain (preserve only), RetainThenDelete.

.PARAMETER CollaborationAction
    Default: Retain.

.PARAMETER TeamsChatAction
    Default: RetainThenDelete.

.EXAMPLE
    ./23-Deploy-BaselineRetention.ps1 -EmailRetentionYears 7 -TeamsChatAction RetainThenDelete

.NOTES
    Required: Connect-IPPSSession.
#>

[CmdletBinding()]
param(
    [int]$EmailRetentionYears = 7,
    [int]$CollaborationRetentionYears = 7,
    [int]$TeamsChatRetentionYears = 3,

    [ValidateSet("Retain","RetainThenDelete")]
    [string]$EmailAction = "Retain",

    [ValidateSet("Retain","RetainThenDelete")]
    [string]$CollaborationAction = "Retain",

    [ValidateSet("Retain","RetainThenDelete")]
    [string]$TeamsChatAction = "RetainThenDelete"
)

$ErrorActionPreference = "Stop"

$ippsAvailable = Get-Command New-RetentionCompliancePolicy -ErrorAction SilentlyContinue
if (-not $ippsAvailable) { throw "Run Connect-IPPSSession first." }

function ConvertTo-RetentionAction {
    param([string]$Action)
    if ($Action -eq "Retain") { return "Keep" }
    return "KeepAndDelete"
}

function Deploy-Policy {
    param(
        [string]$Name,
        [hashtable]$LocationParams,
        [int]$Years,
        [string]$Action,
        [string]$Description
    )

    $existing = Get-RetentionCompliancePolicy -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Policy exists: $Name (skip; update via separate workflow)" -ForegroundColor Yellow
        return
    }

    Write-Host "  Creating: $Name" -ForegroundColor Cyan

    $policyParams = @{
        Name = $Name
        Comment = $Description
    }
    foreach ($k in $LocationParams.Keys) { $policyParams[$k] = $LocationParams[$k] }

    $policy = New-RetentionCompliancePolicy @policyParams

    # Create the rule
    $durationDays = $Years * 365
    $ruleParams = @{
        Name = "$Name Rule"
        Policy = $Name
        RetentionDuration = $durationDays
        RetentionComplianceAction = ConvertTo-RetentionAction -Action $Action
        ExpirationDateOption = "CreationAgeInDays"
    }

    New-RetentionComplianceRule @ruleParams | Out-Null
    Write-Host "    Rule created: $Years years, $Action" -ForegroundColor Green
}

Write-Host "=== Deploy Baseline Retention Policies ===" -ForegroundColor Cyan
Write-Host ""

# Policy 1: Email
Deploy-Policy `
    -Name "SMB Retention - Business Communications" `
    -LocationParams @{ ExchangeLocation = "All" } `
    -Years $EmailRetentionYears `
    -Action $EmailAction `
    -Description "Retains Exchange mail for $EmailRetentionYears years from creation."

# Policy 2: SharePoint and OneDrive
Deploy-Policy `
    -Name "SMB Retention - Collaboration Content" `
    -LocationParams @{ SharePointLocation = "All"; OneDriveLocation = "All" } `
    -Years $CollaborationRetentionYears `
    -Action $CollaborationAction `
    -Description "Retains SharePoint and OneDrive content for $CollaborationRetentionYears years from last modification."

# Policy 3: Teams chat
Deploy-Policy `
    -Name "SMB Retention - Teams Chat" `
    -LocationParams @{ TeamsChatLocation = "All"; TeamsChannelLocation = "All" } `
    -Years $TeamsChatRetentionYears `
    -Action $TeamsChatAction `
    -Description "Retains Teams chat and channel messages for $TeamsChatRetentionYears years; $TeamsChatAction."

Write-Host ""
Write-Host "Baseline retention policies deployed." -ForegroundColor Green
