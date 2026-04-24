<#
.SYNOPSIS
    Deploys applications and consent detection rules.

.DESCRIPTION
    Runbook 16 - Alert Rules for High-Signal Events, Step 5.

    Three detections:
      AP-001: OAuth consent grant to non-verified application
      AP-002: Service principal credential added (also an M365 Hardening Playbook indicator)
      AP-003: Application permission scope added or elevated

.PARAMETER Platform
    DefenderXDR, Sentinel, or AlertPolicy.

.PARAMETER NotificationEmail
    Alert destination.

.EXAMPLE
    ./16-Deploy-AppConsentAlerts.ps1 -Platform DefenderXDR -NotificationEmail "security-alerts@contoso.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("DefenderXDR", "Sentinel", "AlertPolicy")]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail
)

$ErrorActionPreference = "Stop"

Write-Host "=== Deploy Application and Consent Alert Rules ===" -ForegroundColor Cyan
Write-Host ""

# Note on AP-002: the operation string below must match Microsoft's literal string byte-for-byte
# including the en-dash, which is the one exception to the voice rule elsewhere in this baseline.
$rules = @(
    @{
        Id = "AP-001"
        Name = "OAuth consent grant to non-verified application"
        Severity = "Medium"
        Description = "A user consented to an application from a non-verified publisher. Review the application identity and permissions requested."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType == "Consent to application."
| where RawEventData.IsMSAApp != "true"
| where RawEventData.PublisherVerificationInfo == "" or isnull(RawEventData.PublisherVerificationInfo)
| project Timestamp, AccountUpn, ObjectName, ApplicationId, RawEventData
"@
        AlertPolicyOperation = @("Consent to application.")
    }
    @{
        Id = "AP-002"
        Name = "Service principal credential added"
        Severity = "High"
        Description = "A service principal had new credentials added. Review: this may be an adversary establishing persistence on an already-privileged application."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType has_any ("Add service principal credentials.", "Update application - Certificates and secrets management")
| project Timestamp, AccountUpn, ActionType, ObjectName, RawEventData
"@
        AlertPolicyOperation = @("Add service principal credentials.")
    }
    @{
        Id = "AP-003"
        Name = "Application permission scope added or elevated"
        Severity = "High"
        Description = "An application received new delegated or application permissions. Review whether the scope is appropriate for the application's business purpose."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType in ("Add delegated permission grant.", "Add app role assignment grant to user.", "Add app role assignment to service principal.")
| project Timestamp, AccountUpn, ActionType, ObjectName, RawEventData
"@
        AlertPolicyOperation = @("Add delegated permission grant.", "Add app role assignment to service principal.")
    }
)

$deployed = 0

foreach ($rule in $rules) {
    if ($Platform -eq "DefenderXDR") {
        try {
            $body = @{
                displayName = "$($rule.Id): $($rule.Name)"
                isEnabled = $true
                queryCondition = @{ queryText = $rule.DefenderKql }
                schedule = @{ period = "0:15:00" }
                detectionAction = @{
                    alertTemplate = @{
                        title = "$($rule.Id): $($rule.Name)"
                        description = $rule.Description
                        severity = $rule.Severity.ToLower()
                        category = "Persistence"
                        recommendedActions = "Review the application identity, publisher, and requested permissions."
                    }
                    responseActions = @()
                }
            }

            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/beta/security/rules/detectionRules" `
                -Body ($body | ConvertTo-Json -Depth 10) `
                -ContentType "application/json"

            Write-Host "  Deployed: $($rule.Id)" -ForegroundColor Green
            $deployed++
        } catch {
            Write-Host "  Failed:   $($rule.Id) - $_" -ForegroundColor Red
        }
    } elseif ($Platform -eq "AlertPolicy") {
        try {
            $existing = Get-ProtectionAlert -Identity "$($rule.Id): $($rule.Name)" -ErrorAction SilentlyContinue
            if ($existing) { Write-Host "  Exists:  $($rule.Id)" -ForegroundColor Yellow; continue }

            New-ProtectionAlert `
                -Name "$($rule.Id): $($rule.Name)" `
                -Category "AccessGovernance" `
                -Severity $rule.Severity `
                -ThreatType "Activity" `
                -Operation $rule.AlertPolicyOperation `
                -NotifyUser @($NotificationEmail) `
                -NotifyUserOnFilterMatch $true `
                -Description $rule.Description | Out-Null

            Write-Host "  Deployed: $($rule.Id)" -ForegroundColor Green
            $deployed++
        } catch {
            Write-Host "  Failed:   $($rule.Id) - $_" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "App/consent rules deployed: $deployed of $($rules.Count)" -ForegroundColor Green
