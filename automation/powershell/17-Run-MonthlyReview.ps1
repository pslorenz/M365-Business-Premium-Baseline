<#
.SYNOPSIS
    Executes the automated portions of the monthly baseline review.

.DESCRIPTION
    Runbook 17 - Monthly Review Checklist.
    Applies to: All variants.

    Invokes relevant Verify and Monitor scripts across the deployed baseline and
    produces a consolidated input report for the human reviewer. Does not make
    changes; read-only data collection for review decisions.

.PARAMETER OutputPath
    Destination for the consolidated report. Default: timestamped filename.

.PARAMETER ScriptRoot
    Path to the automation/powershell directory. Default: current directory.

.EXAMPLE
    ./17-Run-MonthlyReview.ps1 -OutputPath "./monthly-review-2026-04.txt"

.NOTES
    Required connections:
      Connect-MgGraph with Directory, Policy, DeviceManagement scopes
      Connect-ExchangeOnline
      Connect-IPPSSession (for Security and Compliance)
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "./monthly-review-$(Get-Date -Format 'yyyy-MM').txt",
    [string]$ScriptRoot = "."
)

$ErrorActionPreference = "Continue"  # Individual script failures should not halt the review

function Write-Section {
    param([string]$Title)
    $separator = "=" * 70
    Add-Content -Path $OutputPath -Value ""
    Add-Content -Path $OutputPath -Value $separator
    Add-Content -Path $OutputPath -Value $Title
    Add-Content -Path $OutputPath -Value $separator
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
}

function Invoke-CheckScript {
    param(
        [string]$ScriptName,
        [string]$Description,
        [hashtable]$Params = @{}
    )

    Add-Content -Path $OutputPath -Value ""
    Add-Content -Path $OutputPath -Value "[$Description]"
    Write-Host "  Running: $Description" -ForegroundColor Gray

    $scriptPath = Join-Path $ScriptRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Add-Content -Path $OutputPath -Value "  SKIPPED: script not found ($scriptPath)"
        return
    }

    try {
        $output = & $scriptPath @Params 2>&1 | Out-String
        Add-Content -Path $OutputPath -Value $output
    } catch {
        Add-Content -Path $OutputPath -Value "  ERROR: $_"
    }
}

# Initialize report
Set-Content -Path $OutputPath -Value @"
M365 Baseline Monthly Review
Generated: $((Get-Date).ToString('o'))
Reviewer: [fill in]

"@

Write-Host "=== Monthly Review: Automated Data Collection ===" -ForegroundColor Cyan
Write-Host "Output: $OutputPath"
Write-Host ""

# Section 1: Identity and access
Write-Section "Section 1: Identity and Access"
Invoke-CheckScript -ScriptName "03-Audit-AdminAssignments.ps1" -Description "1.1 Admin assignment audit" -Params @{ OutputPath = "./temp-admin-audit.csv" }
Invoke-CheckScript -ScriptName "06-Check-AdminMFA.ps1" -Description "1.2 Admin phishing-resistant MFA check"

# Section 2: Conditional Access
Write-Section "Section 2: Conditional Access"
Invoke-CheckScript -ScriptName "02e-Verify-CABaseline.ps1" -Description "2.1 CA baseline policy state"
Invoke-CheckScript -ScriptName "05-Review-TravelExceptions.ps1" -Description "2.2 Travel exception review"

# Section 3: Device compliance
Write-Section "Section 3: Device Compliance"
Invoke-CheckScript -ScriptName "08-Monitor-WindowsCompliance.ps1" -Description "3.1 Windows compliance rate" -Params @{ LookbackDays = 30 }
Invoke-CheckScript -ScriptName "09-Monitor-MobileCompliance.ps1" -Description "3.2 Mobile compliance rate" -Params @{ LookbackDays = 30 }

# Section 4: Email protection
Write-Section "Section 4: Email Protection"
Invoke-CheckScript -ScriptName "09-Verify-MobileInfrastructure.ps1" -Description "4.3 APNs and ABM expiration check"
Invoke-CheckScript -ScriptName "11-Monitor-EmailThreats.ps1" -Description "4.1 Email threat activity" -Params @{ LookbackDays = 30 }

# Section 5: Audit and alerting
Write-Section "Section 5: Audit and Alerting"
Invoke-CheckScript -ScriptName "14-Verify-UALEnabled.ps1" -Description "5.3 UAL ingestion health"
Invoke-CheckScript -ScriptName "14-Test-AuditSearch.ps1" -Description "5.3 Audit search functional"
Invoke-CheckScript -ScriptName "16-Review-AlertActivity.ps1" -Description "5.1 Alert firing activity" -Params @{ LookbackDays = 30 }

# Summary
Write-Section "Review Guidance"
Add-Content -Path $OutputPath -Value @"

The automated data collection above is the input for the human review decisions.
Each section of Runbook 17 has specific decision items that require judgment;
use the data above to inform those decisions.

After completing the review, update this document with:
  - Reviewer name
  - Review completion date
  - Action items and owners
  - Date of next review

Archive the completed review in the operations runbook.
"@

# Cleanup temp files
if (Test-Path "./temp-admin-audit.csv") { Remove-Item "./temp-admin-audit.csv" -Force }

Write-Host ""
Write-Host "Automated data collection complete." -ForegroundColor Green
Write-Host "Report: $OutputPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: complete the human-judgment portions of Runbook 17 using the data above." -ForegroundColor Yellow
