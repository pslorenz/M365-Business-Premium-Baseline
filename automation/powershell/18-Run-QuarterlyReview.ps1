<#
.SYNOPSIS
    Executes automated portions of the quarterly baseline review.

.DESCRIPTION
    Runbook 18 - Quarterly Review Checklist.
    Applies to: All variants.

    Produces a consolidated input package for the quarterly review. The package
    includes tier audit output, CA exception detail, device posture data, email
    authentication state, and alert rule metrics. The human reviewer uses this
    input to make the tier reclassification, access review, and tuning decisions
    defined in the runbook.

.PARAMETER OutputDirectory
    Directory for report files. One file per section. Default: timestamped directory.

.EXAMPLE
    ./18-Run-QuarterlyReview.ps1 -OutputDirectory "./quarterly-2026-Q2"

.NOTES
    Required connections: Microsoft Graph, Exchange Online, Security and Compliance.
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory = "./quarterly-$(Get-Date -Format 'yyyy-Q')",
    [string]$ScriptRoot = "."
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "=== Quarterly Review: Automated Data Collection ===" -ForegroundColor Cyan
Write-Host "Output directory: $OutputDirectory"
Write-Host ""

function Invoke-SectionScript {
    param(
        [string]$ScriptName,
        [string]$OutputFile,
        [hashtable]$Params = @{}
    )

    Write-Host "  Running: $ScriptName" -ForegroundColor Gray

    $scriptPath = Join-Path $ScriptRoot $ScriptName
    $outputPath = Join-Path $OutputDirectory $OutputFile

    if (-not (Test-Path $scriptPath)) {
        Set-Content -Path $outputPath -Value "Script not found: $scriptPath"
        return
    }

    try {
        & $scriptPath @Params 2>&1 | Out-File -FilePath $outputPath -Encoding UTF8
    } catch {
        Set-Content -Path $outputPath -Value "Error running $ScriptName : $_"
    }
}

# Section 1: Tier model audit
Write-Host ""
Write-Host "Section 1: Tier model audit" -ForegroundColor Cyan
Invoke-SectionScript -ScriptName "03-Audit-AdminAssignments.ps1" `
    -OutputFile "01-tier-audit.csv" `
    -Params @{ OutputPath = (Join-Path $OutputDirectory "01-tier-audit.csv") }

# Section 2: Access reviews
Write-Host ""
Write-Host "Section 2: Access reviews" -ForegroundColor Cyan
Invoke-SectionScript -ScriptName "04-Verify-Deployment.ps1" -OutputFile "02-pim-state.txt"

# Section 3: CA and identity
Write-Host ""
Write-Host "Section 3: CA and identity review" -ForegroundColor Cyan
Invoke-SectionScript -ScriptName "02e-Verify-CABaseline.ps1" -OutputFile "03-ca-baseline.txt"
Invoke-SectionScript -ScriptName "05-Review-AllowedCountries.ps1" -OutputFile "03-allowed-countries.txt"
Invoke-SectionScript -ScriptName "05-Verify-Deployment.ps1" -OutputFile "03-travel-exceptions.txt"

# Section 4: Device compliance
Write-Host ""
Write-Host "Section 4: Device compliance" -ForegroundColor Cyan
Invoke-SectionScript -ScriptName "08-Verify-Deployment.ps1" -OutputFile "04-windows-compliance.txt"
Invoke-SectionScript -ScriptName "09-Verify-Deployment.ps1" -OutputFile "04-mobile-compliance.txt"
Invoke-SectionScript -ScriptName "10-Verify-Deployment.ps1" -OutputFile "04-vbs-tpm.txt"
Invoke-SectionScript -ScriptName "08-Verify-BitLockerEscrow.ps1" -OutputFile "04-bitlocker-escrow.txt"
Invoke-SectionScript -ScriptName "09-Verify-MobileInfrastructure.ps1" -OutputFile "04-mobile-infra.txt"

# Section 5: Email protection
Write-Host ""
Write-Host "Section 5: Email protection" -ForegroundColor Cyan
Invoke-SectionScript -ScriptName "11-Verify-Deployment.ps1" -OutputFile "05-antiphish-antimalware.txt"
Invoke-SectionScript -ScriptName "12-Verify-Deployment.ps1" -OutputFile "05-safelinks-safeattachments.txt"
Invoke-SectionScript -ScriptName "13-Verify-Deployment.ps1" -OutputFile "05-email-auth.txt"

# Section 6: Alerting and audit
Write-Host ""
Write-Host "Section 6: Alerting and audit" -ForegroundColor Cyan
Invoke-SectionScript -ScriptName "14-Verify-Deployment.ps1" -OutputFile "06-ual-retention.txt"
Invoke-SectionScript -ScriptName "16-Verify-Deployment.ps1" -OutputFile "06-alert-rules.txt"
Invoke-SectionScript -ScriptName "16-Review-AlertActivity.ps1" `
    -OutputFile "06-alert-activity-90d.txt" `
    -Params @{ LookbackDays = 90 }

# Produce a top-level summary
$summary = @"
M365 Baseline Quarterly Review - Automated Data Collection
==========================================================
Generated: $((Get-Date).ToString('o'))
Output directory: $OutputDirectory

Sections:
  01 - Tier audit (Section 1 of Runbook 18)
  02 - PIM state (Section 2)
  03 - CA and identity review (Section 3)
  04 - Device compliance (Section 4)
  05 - Email protection (Section 5)
  06 - Alerting and audit (Section 6)

The automated data collection produces the inputs for reviewer decisions.
Complete the human-judgment portions per Runbook 18 and document outcomes
in the quarterly posture package.

Deliverables per Runbook 18:
  1. Tier audit report (Section 1)
  2. Access review decision log (Section 2)
  3. CA exception report (Section 3)
  4. Device posture report (Section 4)
  5. Alert catalog report (Section 6)

Store all deliverables in the operations archive with the naming convention:
  YYYY-QN-<section>.pdf (or .md)
"@

Set-Content -Path (Join-Path $OutputDirectory "00-summary.txt") -Value $summary

Write-Host ""
Write-Host "Automated data collection complete." -ForegroundColor Green
Write-Host "Input files in: $OutputDirectory" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: complete the quarterly review per Runbook 18, produce the five deliverables." -ForegroundColor Yellow
