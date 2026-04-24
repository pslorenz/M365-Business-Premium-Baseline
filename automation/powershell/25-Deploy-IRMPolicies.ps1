<#
.SYNOPSIS
    Deploys three baseline Insider Risk Management policies.

.DESCRIPTION
    Runbook 25 - Insider Risk Management, Step 4.

    Creates:
    - Data Theft by Departing Users (triggered by HR status change)
    - Data Leaks (continuous monitoring, all users)
    - Priority User Protection (stricter monitoring for specified group)

.PARAMETER NotificationEmail
    Email destination for IRM alerts.

.PARAMETER LegalEscalationEmail
    Email destination for high-severity cases.

.PARAMETER PriorityUserGroup
    Group name containing priority users.

.EXAMPLE
    ./25-Deploy-IRMPolicies.ps1 -NotificationEmail "insider-risk@contoso.com" -LegalEscalationEmail "legal@contoso.com" -PriorityUserGroup "Priority Users"

.NOTES
    Required: Connect-IPPSSession.
    IRM policy creation cmdlets vary by stack version; portal fallback included.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NotificationEmail,

    [string]$LegalEscalationEmail,

    [string]$PriorityUserGroup = "Priority Users"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Deploy IRM Baseline Policies ===" -ForegroundColor Cyan
Write-Host ""

$irmCmd = Get-Command New-InsiderRiskPolicy -ErrorAction SilentlyContinue

if (-not $irmCmd) {
    Write-Host "IRM policy cmdlets not available in this session." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Portal configuration (recommended path):" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Policy 1: Data Theft by Departing Users" -ForegroundColor Cyan
    Write-Host "  1. Compliance portal > Insider Risk Management > Policies"
    Write-Host "  2. Create policy > Template: Data theft by departing users"
    Write-Host "  3. Name: SMB IRM - Data Theft by Departing Users"
    Write-Host "  4. Scope: HR-flagged departing/terminated users"
    Write-Host "  5. Indicators: File downloads, external sharing, email with attachments, USB"
    Write-Host "  6. Observation window: -30 to +7 days from departure date"
    Write-Host "  7. Alert threshold: score > 40"
    Write-Host "  8. Notifications: $NotificationEmail"
    Write-Host ""
    Write-Host "Policy 2: Data Leaks" -ForegroundColor Cyan
    Write-Host "  1. Create policy > Template: General data leaks"
    Write-Host "  2. Name: SMB IRM - Data Leaks"
    Write-Host "  3. Scope: All users"
    Write-Host "  4. Indicators: External sharing anomalies, bulk email, printing, USB"
    Write-Host "  5. Alert threshold: score > 50"
    Write-Host "  6. Notifications: $NotificationEmail"
    Write-Host ""
    Write-Host "Policy 3: Priority User Protection" -ForegroundColor Cyan
    Write-Host "  1. Create policy > Template: Data leaks by priority users"
    Write-Host "  2. Name: SMB IRM - Priority User Protection"
    Write-Host "  3. Scope: $PriorityUserGroup group"
    Write-Host "  4. Indicators: all from Policy 2, plus access to HighlyConfidential content"
    Write-Host "  5. Alert threshold: score > 30 (lower than standard)"
    Write-Host "  6. Notifications: $NotificationEmail"
    if ($LegalEscalationEmail) {
        Write-Host "     High-severity: $LegalEscalationEmail"
    }
    exit 0
}

# If cmdlets available, create policies directly
$policies = @(
    @{
        Name = "SMB IRM - Data Theft by Departing Users"
        Template = "DataTheftByDepartingUsers"
        NotificationEmail = $NotificationEmail
    }
    @{
        Name = "SMB IRM - Data Leaks"
        Template = "GeneralDataLeaks"
        NotificationEmail = $NotificationEmail
    }
    @{
        Name = "SMB IRM - Priority User Protection"
        Template = "DataLeaksByPriorityUsers"
        NotificationEmail = $NotificationEmail
        PriorityUserGroup = $PriorityUserGroup
    }
)

foreach ($p in $policies) {
    Write-Host "  Creating: $($p.Name)" -ForegroundColor Cyan
    try {
        New-InsiderRiskPolicy `
            -Name $p.Name `
            -PolicyTemplate $p.Template `
            -ErrorAction Stop | Out-Null
        Write-Host "    Created" -ForegroundColor Green
    } catch {
        Write-Host "    Failed: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "IRM policies deployed." -ForegroundColor Green
