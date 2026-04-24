<#
.SYNOPSIS
    Rolls up every Verify-Deployment script into a single baseline summary.

.DESCRIPTION
    Convenience wrapper around the per-runbook Verify-Deployment scripts.
    Produces a one-line status per runbook and a final pass/fail summary.
    Useful before monthly/quarterly/annual reviews as a quick health check.

.PARAMETER ScriptRoot
    Path to automation/powershell directory. Default: current directory.

.EXAMPLE
    ./Verify-BaselineSummary.ps1

.NOTES
    Required connections vary by runbook: Microsoft Graph, Exchange Online,
    Security and Compliance PowerShell. Scripts that cannot connect fail gracefully
    and report their specific connection requirement.
#>

[CmdletBinding()]
param(
    [string]$ScriptRoot = "."
)

$ErrorActionPreference = "Continue"

Write-Host "=== Baseline Verification Summary ===" -ForegroundColor Cyan
Write-Host "Runs every Verify-Deployment script and reports roll-up status."
Write-Host ""

$verifyScripts = Get-ChildItem -Path $ScriptRoot -Filter "*-Verify-Deployment.ps1" | Sort-Object Name

$results = @()

foreach ($script in $verifyScripts) {
    # Extract runbook number from filename
    $runbook = if ($script.Name -match "^(\d{2}[a-z]?)") { $matches[1] } else { "?" }

    Write-Host "Runbook $runbook : running $($script.Name)..." -ForegroundColor Gray

    # Capture output and exit code
    try {
        $null = & $script.FullName 2>&1
        $exit = $LASTEXITCODE

        $status = switch ($exit) {
            0 { "PASS" }
            1 { "PARTIAL" }
            2 { "ERROR" }
            default { "UNKNOWN ($exit)" }
        }
    } catch {
        $status = "EXCEPTION"
    }

    $results += [PSCustomObject]@{
        Runbook = $runbook
        Script = $script.Name
        Status = $status
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$pass = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$partial = ($results | Where-Object { $_.Status -eq "PARTIAL" }).Count
$error = ($results | Where-Object { $_.Status -in @("ERROR", "EXCEPTION", "UNKNOWN") }).Count

Write-Host ""
Write-Host "Overall:"
Write-Host "  PASS:    $pass" -ForegroundColor Green
Write-Host "  PARTIAL: $partial" -ForegroundColor $(if ($partial -gt 0) { "Yellow" } else { "Gray" })
Write-Host "  ERROR:   $error" -ForegroundColor $(if ($error -gt 0) { "Red" } else { "Gray" })

if ($partial -eq 0 -and $error -eq 0) {
    Write-Host ""
    Write-Host "Baseline fully verified." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Baseline has issues. Run individual Verify scripts for detail." -ForegroundColor Yellow
    exit 1
}
