<#
.SYNOPSIS
    Deploys mail flow and compromise detection rules.

.DESCRIPTION
    Runbook 16 - Alert Rules for High-Signal Events, Step 4.

    Five detections:
      MC-001: Mailbox forwarding or redirect rule created
      MC-002: Inbox rule with external domain targets
      MC-003: Bulk message deletion by a single user
      MC-004: Safe Links block followed by user click-through
      MC-005: High volume of messages sent in short window

.PARAMETER Platform
    DefenderXDR, Sentinel, or AlertPolicy.

.PARAMETER NotificationEmail
    Alert destination.

.EXAMPLE
    ./16-Deploy-MailCompromiseAlerts.ps1 -Platform DefenderXDR -NotificationEmail "security-alerts@contoso.com"
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

Write-Host "=== Deploy Mail Compromise Alert Rules ===" -ForegroundColor Cyan
Write-Host ""

$rules = @(
    @{
        Id = "MC-001"
        Name = "Mailbox forwarding or redirect rule created"
        Severity = "High"
        Description = "A mailbox rule was created that forwards or redirects mail. High-fidelity BEC indicator; investigate immediately."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType in ("New-InboxRule", "Set-InboxRule", "New-TransportRule")
| extend params = tostring(RawEventData.Parameters)
| where params has_any ("ForwardTo", "RedirectTo", "ForwardAsAttachmentTo")
| project Timestamp, AccountUpn, ActionType, ObjectName, params
"@
        AlertPolicyOperation = @("New-InboxRule", "Set-InboxRule")
    }
    @{
        Id = "MC-002"
        Name = "Inbox rule with external domain targets"
        Severity = "High"
        Description = "An inbox rule was created with a forwarding target in an external domain. Common BEC pattern."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType in ("New-InboxRule", "Set-InboxRule")
| extend params = tostring(RawEventData.Parameters)
| where params has_any ("ForwardTo", "RedirectTo")
| where params matches regex "@(?!contoso\.com|contoso\.onmicrosoft\.com)[a-z0-9.-]+\\.[a-z]{2,}"
| project Timestamp, AccountUpn, ActionType, ObjectName, params
"@
        AlertPolicyOperation = @("New-InboxRule", "Set-InboxRule")
    }
    @{
        Id = "MC-003"
        Name = "Bulk message deletion by a single user"
        Severity = "Medium"
        Description = "A single user deleted or hard-deleted a large volume of messages in a short window. Possible cleanup after BEC; investigate."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(1h)
| where ActionType in ("SoftDelete", "HardDelete", "MoveToDeletedItems")
| summarize DeleteCount=count() by AccountUpn, bin(Timestamp, 15m)
| where DeleteCount > 100
| project Timestamp, AccountUpn, DeleteCount
"@
        AlertPolicyOperation = @("HardDelete", "SoftDelete")
    }
    @{
        Id = "MC-004"
        Name = "Safe Links block followed by user click-through"
        Severity = "Medium"
        Description = "A user clicked through a Safe Links block page to reach a URL flagged as malicious. Indicates social engineering or self-compromise risk."
        DefenderKql = @"
UrlClickEvents
| where Timestamp > ago(15m)
| where ActionType == "ClickAllowed"
| where UrlChain has_any ("Phish", "Malware", "Suspicious")
| project Timestamp, AccountUpn, Url, ActionType, UrlChain
"@
        AlertPolicyOperation = @()  # Requires Defender XDR
    }
    @{
        Id = "MC-005"
        Name = "High volume of messages sent by single user"
        Severity = "Medium"
        Description = "A single user sent an anomalously high volume of messages in a short window. Possible account compromise being used for outbound spam or phishing."
        DefenderKql = @"
EmailEvents
| where Timestamp > ago(1h)
| where EmailDirection == "Outbound"
| summarize MessageCount=count(), UniqueRecipients=dcount(RecipientEmailAddress) by SenderFromAddress, bin(Timestamp, 15m)
| where MessageCount > 100 or UniqueRecipients > 50
| project Timestamp, SenderFromAddress, MessageCount, UniqueRecipients
"@
        AlertPolicyOperation = @()  # Alert policy equivalent exists as built-in
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
                        category = "Exfiltration"
                        recommendedActions = "Confirm the rule or activity is legitimate; if not, disable the account and investigate."
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
        if ($rule.AlertPolicyOperation.Count -eq 0) {
            Write-Host "  Skipped:  $($rule.Id) - requires Defender XDR" -ForegroundColor Yellow
            continue
        }

        try {
            $existing = Get-ProtectionAlert -Identity "$($rule.Id): $($rule.Name)" -ErrorAction SilentlyContinue
            if ($existing) { Write-Host "  Exists:  $($rule.Id)" -ForegroundColor Yellow; continue }

            New-ProtectionAlert `
                -Name "$($rule.Id): $($rule.Name)" `
                -Category "ThreatManagement" `
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
Write-Host "Mail compromise rules deployed: $deployed of $($rules.Count)" -ForegroundColor Green
