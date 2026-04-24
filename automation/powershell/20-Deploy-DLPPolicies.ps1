<#
.SYNOPSIS
    Deploys the five baseline DLP policies in test mode.

.DESCRIPTION
    Runbook 20 - Purview DLP Baseline, Step 3.

    Creates five DLP policies covering US financial data, US PII, protected health
    information (optional), confidential business information, and outbound large-
    volume transfer. All policies start in "Test with notifications" mode, producing
    policy tips and admin notifications without blocking.

.PARAMETER NotificationEmail
    Destination for admin notifications on policy matches.

.PARAMETER IncludeHealthcarePolicy
    Deploy the PHI policy. Default: false. Enable for HIPAA-subject tenants.

.PARAMETER Mode
    Initial deployment mode. Default: TestWithNotifications.

.EXAMPLE
    ./20-Deploy-DLPPolicies.ps1 -NotificationEmail "security-alerts@contoso.com" -Mode TestWithNotifications

.NOTES
    Required: Connect-IPPSSession.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail,

    [switch]$IncludeHealthcarePolicy,

    [ValidateSet("TestWithNotifications", "TestWithoutNotifications", "Enable", "Disable")]
    [string]$Mode = "TestWithNotifications"
)

$ErrorActionPreference = "Stop"

$ippsAvailable = Get-Command New-DlpCompliancePolicy -ErrorAction SilentlyContinue
if (-not $ippsAvailable) { throw "Run Connect-IPPSSession first." }

Write-Host "=== Deploy DLP Baseline Policies ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode"
Write-Host "Notifications: $NotificationEmail"
Write-Host "Include PHI policy: $([bool]$IncludeHealthcarePolicy)"
Write-Host ""

function Deploy-Policy {
    param(
        [string]$PolicyName,
        [int]$Priority,
        [string]$Description,
        [hashtable]$RuleConfig
    )

    # Create or update policy
    $existing = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "  Policy exists: $PolicyName (updating mode)" -ForegroundColor Yellow
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode $Mode | Out-Null
    } else {
        Write-Host "  Creating: $PolicyName" -ForegroundColor Cyan
        $policyParams = @{
            Name = $PolicyName
            Comment = $Description
            ExchangeLocation = "All"
            SharePointLocation = "All"
            OneDriveLocation = "All"
            TeamsLocation = "All"
            Priority = $Priority
            Mode = $Mode
        }
        New-DlpCompliancePolicy @policyParams | Out-Null
    }

    # Create rule
    $ruleName = "$PolicyName Rule"
    $existingRule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue

    if ($existingRule) {
        Set-DlpComplianceRule -Identity $ruleName @RuleConfig | Out-Null
    } else {
        $ruleParams = $RuleConfig.Clone()
        $ruleParams.Name = $ruleName
        $ruleParams.Policy = $PolicyName
        New-DlpComplianceRule @ruleParams | Out-Null
    }
    Write-Host "    Rule configured" -ForegroundColor Green
}

# Policy 1: Outbound Large-Volume Transfer (priority 0, highest)
Deploy-Policy `
    -PolicyName "SMB DLP - Outbound Large-Volume Transfer" `
    -Priority 0 `
    -Description "High-fidelity exfiltration indicator. Blocks bulk outbound movement of sensitive data." `
    -RuleConfig @{
        ContentContainsSensitiveInformation = @(
            @{ Name = "Credit Card Number"; minCount = 10 }
            @{ Name = "U.S. Social Security Number (SSN)"; minCount = 5 }
        )
        BlockAccess = $true
        NotifyUser = @("SiteAdmin","LastModifier","Owner")
        GenerateIncidentReport = @($NotificationEmail)
        IncidentReportContent = @("Title","DocumentAuthor","DocumentLastModifier","Service","MatchedItem","RulesMatched","Detections","Severity")
        ReportSeverityLevel = "High"
    }

# Policy 2: Protected Health Information (if enabled)
if ($IncludeHealthcarePolicy) {
    Deploy-Policy `
        -PolicyName "SMB DLP - Protected Health Information" `
        -Priority 1 `
        -Description "Blocks sharing of PHI externally; alerts on internal sharing." `
        -RuleConfig @{
            ContentContainsSensitiveInformation = @(
                @{ Name = "U.S. / U.K. Passport Number"; minCount = 1 }
                @{ Name = "International Classification of Diseases (ICD-10-CM)"; minCount = 1 }
                @{ Name = "International Classification of Diseases (ICD-9-CM)"; minCount = 1 }
            )
            AccessScope = "NotInOrganization"
            BlockAccess = $true
            NotifyUser = @("SiteAdmin","LastModifier","Owner")
            GenerateIncidentReport = @($NotificationEmail)
            ReportSeverityLevel = "High"
        }
}

# Policy 3: US Financial Data
Deploy-Policy `
    -PolicyName "SMB DLP - US Financial Data" `
    -Priority 2 `
    -Description "Detects credit cards, bank accounts, and routing numbers in content." `
    -RuleConfig @{
        ContentContainsSensitiveInformation = @(
            @{ Name = "Credit Card Number"; minCount = 1 }
            @{ Name = "U.S. Bank Account Number"; minCount = 1 }
            @{ Name = "ABA Routing Number"; minCount = 1 }
        )
        NotifyUser = @("SiteAdmin","LastModifier","Owner")
        NotifyPolicyTipDisplayOption = "Tip"
        GenerateIncidentReport = @($NotificationEmail)
        ReportSeverityLevel = "Medium"
    }

# Policy 4: US PII
Deploy-Policy `
    -PolicyName "SMB DLP - US PII" `
    -Priority 3 `
    -Description "Detects SSN, passport, and driver license numbers." `
    -RuleConfig @{
        ContentContainsSensitiveInformation = @(
            @{ Name = "U.S. Social Security Number (SSN)"; minCount = 1 }
            @{ Name = "U.S. / U.K. Passport Number"; minCount = 1 }
            @{ Name = "U.S. Driver's License Number"; minCount = 3 }
        )
        NotifyUser = @("SiteAdmin","LastModifier","Owner")
        NotifyPolicyTipDisplayOption = "Tip"
        GenerateIncidentReport = @($NotificationEmail)
        ReportSeverityLevel = "Medium"
    }

# Policy 5: Confidential Business Information (label-integrated in Step 8)
Deploy-Policy `
    -PolicyName "SMB DLP - Confidential Business Information" `
    -Priority 4 `
    -Description "Placeholder for label-based enforcement after Runbook 21 integration." `
    -RuleConfig @{
        ContentContainsSensitiveInformation = @()
        NotifyUser = @("SiteAdmin","LastModifier","Owner")
        NotifyPolicyTipDisplayOption = "Tip"
        GenerateIncidentReport = @($NotificationEmail)
        ReportSeverityLevel = "Low"
    }

Write-Host ""
Write-Host "Baseline DLP policies deployed in $Mode mode." -ForegroundColor Green
Write-Host "Monitor for 30 days before transitioning to enforcement." -ForegroundColor Cyan
Write-Host ""
Write-Host "Monitor: ./20-Monitor-DLPMatches.ps1 -LookbackDays 30" -ForegroundColor Cyan
Write-Host "Transition: ./20-Transition-DLPEnforcement.ps1" -ForegroundColor Cyan
