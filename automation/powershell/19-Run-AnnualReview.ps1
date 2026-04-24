<#
.SYNOPSIS
    Executes automated portions of the annual baseline review.

.DESCRIPTION
    Runbook 19 - Annual Review Checklist.
    Applies to: All variants.

    Runs every Verify-Deployment script across the deployed baseline, gathers licensing
    state, produces coverage and gap reports. The output is the input package for the
    annual reviewer; human judgment portions (threat review, regulatory mapping,
    leadership presentation) are not automated.

.PARAMETER OutputDirectory
    Directory for the annual package. Default: timestamped directory.

.PARAMETER ScriptRoot
    Path to the automation/powershell directory.

.EXAMPLE
    ./19-Run-AnnualReview.ps1 -OutputDirectory "./annual-review-2026"

.NOTES
    Required connections: Microsoft Graph, Exchange Online, Security and Compliance PowerShell.
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory = "./annual-review-$(Get-Date -Format 'yyyy')",
    [string]$ScriptRoot = "."
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
if (-not (Test-Path (Join-Path $OutputDirectory "raw-data"))) {
    New-Item -ItemType Directory -Path (Join-Path $OutputDirectory "raw-data") -Force | Out-Null
}

Write-Host "=== Annual Review: Automated Data Collection ===" -ForegroundColor Cyan
Write-Host "Output directory: $OutputDirectory"
Write-Host ""

# Section 1: Baseline coverage - run every Verify script
Write-Host "Section 1: Baseline coverage verification..." -ForegroundColor Cyan

$verifyScripts = Get-ChildItem -Path $ScriptRoot -Filter "*-Verify-Deployment.ps1" | Sort-Object Name
$coverageLog = Join-Path $OutputDirectory "raw-data/verify-deployment-logs.txt"
Set-Content -Path $coverageLog -Value "# Baseline Coverage Verification`n"
Add-Content -Path $coverageLog -Value "Run at: $((Get-Date).ToString('o'))`n"

$passCount = 0
$failCount = 0

foreach ($script in $verifyScripts) {
    Write-Host "  Running: $($script.Name)" -ForegroundColor Gray
    Add-Content -Path $coverageLog -Value "`n## $($script.Name)`n"

    try {
        $output = & $script.FullName 2>&1 | Out-String
        Add-Content -Path $coverageLog -Value $output

        if ($LASTEXITCODE -eq 0) {
            $passCount++
        } else {
            $failCount++
        }
    } catch {
        Add-Content -Path $coverageLog -Value "ERROR: $_"
        $failCount++
    }
}

Write-Host ""
Write-Host "Verify scripts: $passCount pass, $failCount fail/partial" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })

# Section 2: Licensing inventory
Write-Host ""
Write-Host "Section 2: Licensing inventory..." -ForegroundColor Cyan

try {
    $skus = Get-MgSubscribedSku -ErrorAction Stop
    $licensingReport = Join-Path $OutputDirectory "02-licensing-review.md"

    $md = @"
# Licensing Review

Generated: $((Get-Date).ToString('o'))

## Current License Inventory

| SKU Part Number | SKU ID | Enabled Units | Consumed Units | Available |
|---|---|---|---|---|
"@

    foreach ($sku in $skus | Sort-Object SkuPartNumber) {
        $available = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
        $md += "`n| $($sku.SkuPartNumber) | $($sku.SkuId) | $($sku.PrepaidUnits.Enabled) | $($sku.ConsumedUnits) | $available |"
    }

    $md += @"


## Review Decisions

| Item | Decision |
|---|---|
| Over-licensing identified? | |
| Add-on upgrade recommended? | |
| License adjustments for next fiscal year | |

"@

    Set-Content -Path $licensingReport -Value $md
    Write-Host "  Licensing report written." -ForegroundColor Green
} catch {
    Write-Warning "Licensing query failed: $_"
}

# Section 3: Email authentication (reuses quarterly export)
Write-Host ""
Write-Host "Section 3: Email authentication..." -ForegroundColor Cyan
$emailReport = Join-Path $OutputDirectory "03-email-auth-posture.md"
$emailScript = Join-Path $ScriptRoot "18-Export-EmailProtectionReport.ps1"
if (Test-Path $emailScript) {
    try {
        & $emailScript -OutputPath $emailReport | Out-Null
        Write-Host "  Email authentication report written." -ForegroundColor Green
    } catch {
        Write-Warning "Email report failed: $_"
    }
}

# Section summaries
$baselineCoverage = Join-Path $OutputDirectory "01-baseline-coverage-matrix.md"
Set-Content -Path $baselineCoverage -Value @"
# Baseline Coverage Matrix

Generated: $((Get-Date).ToString('o'))

## Summary

Verify scripts executed: $($verifyScripts.Count)
Pass: $passCount
Fail / partial: $failCount

See raw-data/verify-deployment-logs.txt for full output.

## Runbook Verification Status

| Runbook | Verify Script | Result |
|---|---|---|
"@

foreach ($s in $verifyScripts) {
    $runbookPrefix = if ($s.Name -match "^(\d{2})") { $matches[1] } else { "?" }
    Add-Content -Path $baselineCoverage -Value "| $runbookPrefix | $($s.Name) | (see raw-data) |"
}

# Summary document
$summaryPath = Join-Path $OutputDirectory "00-executive-summary.md"
Set-Content -Path $summaryPath -Value @"
# M365 Baseline Annual Review - Executive Summary

Review year: $(Get-Date -Format 'yyyy')
Review date: $((Get-Date).ToString('o'))
Reviewer: [fill in]
Leadership sponsor: [fill in]

## Package Contents

1. 00-executive-summary.md - this file
2. 01-baseline-coverage-matrix.md - Section 1 deliverable
3. 02-licensing-review.md - Section 2 deliverable
4. 03-email-auth-posture.md - Section 3 deliverable
5. 04-threat-effectiveness.md - Section 4 deliverable (manual)
6. 05-capability-gap-report.md - Section 5 deliverable (manual)
7. 06-ir-bc-readiness.md - Section 6 deliverable (manual, includes drill)
8. 07-regulatory-mapping.md - Section 7 deliverable (manual)
9. 08-leadership-decisions.md - Section 8 deliverable (manual)
10. raw-data/ - full verify and audit outputs

## Review Status

- Section 1 (Baseline coverage): $(if ($failCount -eq 0) { "PASS" } else { "Partial - see matrix" })
- Section 2 (Licensing): Data collected; reviewer decision required
- Section 3 (Email authentication): Data collected; reviewer decision required
- Sections 4-8: Manual completion required

## Leadership Presentation

Present the executive summary and package contents to the leadership sponsor.
Capture leadership decisions in 08-leadership-decisions.md.

## Baseline Version

- Current deployed version: [fill in]
- Updated version for next year: [fill in after review]
"@

Write-Host ""
Write-Host "Annual review data collection complete." -ForegroundColor Green
Write-Host "Package directory: $OutputDirectory" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: complete manual sections (4-8) per Runbook 19." -ForegroundColor Yellow
