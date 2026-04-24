<#
.SYNOPSIS
    Deploys sensitive content detection rules for Copilot prompts.

.DESCRIPTION
    Runbook 24 - DSPM for AI, Step 3.

    Creates rules that detect sensitive information types (credit cards, SSNs,
    passwords) in Copilot prompts. Initial mode is Audit; transition to Block
    after 30 days of observation via 24-Transition-AIEnforcement.ps1.

.PARAMETER NotificationEmail
    Destination for prompt-related alerts.

.PARAMETER Mode
    Default: Audit. Options: Audit, Block.

.EXAMPLE
    ./24-Deploy-PromptSensitiveContentRules.ps1 -NotificationEmail "ai-governance@contoso.com" -Mode Audit

.NOTES
    Required: Connect-IPPSSession.
    DSPM for AI must be enabled (via 24-Enable-DSPMAI.ps1) before running this script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail,

    [ValidateSet("Audit","Block")]
    [string]$Mode = "Audit"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Deploy Prompt Content Detection ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode"
Write-Host ""

# DSPM for AI prompt rules are extensions of DLP policies with AI-specific location
$aiRuleCmd = Get-Command New-DlpCompliancePolicy -ErrorAction SilentlyContinue
if (-not $aiRuleCmd) { throw "Run Connect-IPPSSession first." }

$policyName = "SMB DSPM AI - Prompt Sensitive Content"

$existing = Get-DlpCompliancePolicy -Identity $policyName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Policy exists; updating mode..." -ForegroundColor Yellow
    $policyMode = if ($Mode -eq "Audit") { "TestWithNotifications" } else { "Enable" }
    Set-DlpCompliancePolicy -Identity $policyName -Mode $policyMode | Out-Null
} else {
    Write-Host "Creating: $policyName" -ForegroundColor Cyan

    try {
        # Microsoft 365 Copilot location is a newer DLP location
        # If not available in the tenant, fall back to a note
        $policyMode = if ($Mode -eq "Audit") { "TestWithNotifications" } else { "Enable" }

        New-DlpCompliancePolicy `
            -Name $policyName `
            -Comment "Detects sensitive content in Microsoft 365 Copilot prompts. Part of Runbook 24 (DSPM for AI)." `
            -Microsoft365CopilotLocation "All" `
            -Mode $policyMode `
            -ErrorAction Stop | Out-Null

        # Rule matching credit cards, SSNs, passwords
        $ruleConfig = @{
            Name = "$policyName Rule"
            Policy = $policyName
            ContentContainsSensitiveInformation = @(
                @{ Name = "Credit Card Number"; minCount = 1 }
                @{ Name = "U.S. Social Security Number (SSN)"; minCount = 1 }
                @{ Name = "Password"; minCount = 1 }
            )
            NotifyUser = @("Owner")
            GenerateIncidentReport = @($NotificationEmail)
            ReportSeverityLevel = "Medium"
        }

        if ($Mode -eq "Block") {
            $ruleConfig["BlockAccess"] = $true
        }

        New-DlpComplianceRule @ruleConfig | Out-Null

        Write-Host "  Policy and rule created." -ForegroundColor Green
    } catch {
        Write-Host "  Microsoft 365 Copilot DLP location may not be available in your tenant." -ForegroundColor Yellow
        Write-Host "  Configure through Purview portal: DSPM for AI > Policies" -ForegroundColor Yellow
        Write-Host "  Error: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Prompt detection rules deployed." -ForegroundColor Green
