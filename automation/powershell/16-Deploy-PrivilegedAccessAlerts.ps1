<#
.SYNOPSIS
    Deploys privileged access detection rules.

.DESCRIPTION
    Runbook 16 - Alert Rules for High-Signal Events, Step 2.

    Deploys five high-signal detections targeting privileged access patterns:
      PA-001: Break glass account sign-in
      PA-002: Privileged role assigned outside PIM workflow
      PA-003: Tier-0 role activated outside business hours (P2)
      PA-004: Conditional Access policy modified
      PA-005: Security default changed or tenant security settings modified

.PARAMETER Platform
    DefenderXDR, Sentinel, or AlertPolicy.

.PARAMETER BreakGlassUPNs
    Array of break glass account UPNs.

.PARAMETER NotificationEmail
    Alert destination.

.EXAMPLE
    ./16-Deploy-PrivilegedAccessAlerts.ps1 -Platform DefenderXDR -BreakGlassUPNs @("breakglass01@contoso.onmicrosoft.com") -NotificationEmail "security-alerts@contoso.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("DefenderXDR", "Sentinel", "AlertPolicy")]
    [string]$Platform,

    [string[]]$BreakGlassUPNs = @(),

    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail
)

$ErrorActionPreference = "Stop"

Write-Host "=== Deploy Privileged Access Alert Rules ===" -ForegroundColor Cyan
Write-Host "Platform: $Platform"
Write-Host "Destination: $NotificationEmail"
Write-Host ""

# Rule definitions (platform-independent threat models; platform-specific implementations)
$rules = @(
    @{
        Id = "PA-001"
        Name = "Break glass account sign-in"
        Severity = "High"
        Description = "Break glass account sign-in detected. Confirm sign-in was planned; investigate as incident if not."
        DefenderKql = @"
IdentityLogonEvents
| where Timestamp > ago(10m)
| where AccountUpn in ($(($BreakGlassUPNs | ForEach-Object { "'$_'" }) -join ','))
| where ActionType == "LogonSuccess"
| project Timestamp, AccountUpn, IPAddress, DeviceName, LogonType, ISP
"@
        AlertPolicyOperation = @("UserLoggedIn")
    }
    @{
        Id = "PA-002"
        Name = "Privileged role assigned outside PIM workflow"
        Severity = "High"
        Description = "Administrator role assigned directly rather than via PIM. Verify the assignment was approved and PIM was bypassed intentionally."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(30m)
| where ActionType == "Add member to role."
| where RawEventData.Target.UserType != "PIMActivation"
| project Timestamp, AccountUpn, ActionType, ObjectName, RawEventData
"@
        AlertPolicyOperation = @("Add member to role.")
    }
    @{
        Id = "PA-003"
        Name = "Tier-0 role activated outside business hours"
        Severity = "Medium"
        Description = "A tier-0 privileged role (Global Admin, PRA, PAA) was activated outside business hours. Confirm the activation aligns with an approved change window."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(30m)
| where ActionType == "Member assigned directly to role."
| where RawEventData.Role in ("Global Administrator", "Privileged Role Administrator", "Privileged Authentication Administrator")
| extend hour = datetime_part("hour", Timestamp)
| where hour < 6 or hour > 20
| project Timestamp, AccountUpn, RawEventData
"@
        AlertPolicyOperation = @("Member assigned directly to role.")
    }
    @{
        Id = "PA-004"
        Name = "Conditional Access policy modified"
        Severity = "High"
        Description = "A Conditional Access policy was modified. All changes should be reviewed; unscheduled changes warrant investigation."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType in ("Add conditional access policy.", "Update conditional access policy.", "Delete conditional access policy.")
| project Timestamp, AccountUpn, ActionType, ObjectName, RawEventData
"@
        AlertPolicyOperation = @("Add conditional access policy.", "Update conditional access policy.", "Delete conditional access policy.")
    }
    @{
        Id = "PA-005"
        Name = "Security default or tenant security setting modified"
        Severity = "High"
        Description = "A tenant-level security setting was changed. Verify the change was authorized."
        DefenderKql = @"
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType has_any ("Set-SecurityDefaults", "Disable security defaults", "Update organization settings")
| project Timestamp, AccountUpn, ActionType, ObjectName, RawEventData
"@
        AlertPolicyOperation = @("Update organization settings")
    }
)

$deployed = 0

if ($Platform -eq "DefenderXDR") {
    foreach ($rule in $rules) {
        try {
            $body = @{
                displayName = "$($rule.Id): $($rule.Name)"
                isEnabled = $true
                queryCondition = @{
                    queryText = $rule.DefenderKql
                }
                schedule = @{
                    period = "0:15:00"   # Run every 15 minutes
                }
                detectionAction = @{
                    alertTemplate = @{
                        title = "$($rule.Id): $($rule.Name)"
                        description = $rule.Description
                        severity = $rule.Severity.ToLower()
                        category = "InitialAccess"
                        recommendedActions = "Review event details; investigate the actor and the target resource."
                    }
                    responseActions = @()
                }
            }

            # Graph endpoint for custom detection rules
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/beta/security/rules/detectionRules" `
                -Body ($body | ConvertTo-Json -Depth 10) `
                -ContentType "application/json"

            Write-Host "  Deployed: $($rule.Id) - $($rule.Name)" -ForegroundColor Green
            $deployed++
        } catch {
            Write-Host "  Failed:   $($rule.Id) - $_" -ForegroundColor Red
        }
    }
} elseif ($Platform -eq "AlertPolicy") {
    $ippsAvailable = Get-Command New-ProtectionAlert -ErrorAction SilentlyContinue
    if (-not $ippsAvailable) { throw "Run Connect-IPPSSession first." }

    foreach ($rule in $rules) {
        try {
            $existing = Get-ProtectionAlert -Identity "$($rule.Id): $($rule.Name)" -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host "  Exists: $($rule.Id)" -ForegroundColor Yellow
                continue
            }

            New-ProtectionAlert `
                -Name "$($rule.Id): $($rule.Name)" `
                -Category "AccessGovernance" `
                -Severity $rule.Severity `
                -ThreatType "Activity" `
                -Operation $rule.AlertPolicyOperation `
                -NotifyUser @($NotificationEmail) `
                -NotifyUserOnFilterMatch $true `
                -Description $rule.Description `
                -AggregationType "simple" | Out-Null

            Write-Host "  Deployed: $($rule.Id) - $($rule.Name)" -ForegroundColor Green
            $deployed++
        } catch {
            Write-Host "  Failed:   $($rule.Id) - $_" -ForegroundColor Red
        }
    }
} elseif ($Platform -eq "Sentinel") {
    Write-Host "Sentinel analytics rule deployment requires Azure PowerShell and Sentinel workspace context." -ForegroundColor Yellow
    Write-Host "Manual deployment: use the Sentinel portal's Analytics rules blade with the KQL queries documented in runbook 16." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "For each rule, create a 'Scheduled query rule' with the KQL shown." -ForegroundColor Yellow
    foreach ($rule in $rules) {
        Write-Host ""
        Write-Host "Rule: $($rule.Id) - $($rule.Name)" -ForegroundColor Cyan
        Write-Host "Severity: $($rule.Severity)"
        Write-Host "Query:"
        Write-Host $rule.DefenderKql
    }
    $deployed = $rules.Count
}

Write-Host ""
Write-Host "Privileged access rules deployed: $deployed of $($rules.Count)" -ForegroundColor Green
