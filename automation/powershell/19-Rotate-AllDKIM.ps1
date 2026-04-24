<#
.SYNOPSIS
    Rotates DKIM keys for every sending domain as part of the annual review.

.DESCRIPTION
    Runbook 19 - Annual Review Checklist, Section 3.
    Applies to: All variants.

    Iterates authoritative domains in the tenant and rotates DKIM keys for each.
    Safe to run annually regardless of key age; rotation is transparent to mail
    flow because Exchange Online maintains both the active and alternate selector
    during the grace period.

    Skips domains where DKIM is not enabled or where DKIM was rotated within the
    past SkipDays (default 180) to avoid unnecessary rotation.

.PARAMETER KeyLength
    2048 (recommended) or 1024. Default: 2048.

.PARAMETER SkipDays
    Skip domains rotated within this many days. Default: 180.
    Set to 0 to force rotation for every domain.

.PARAMETER DryRun
    Report what would rotate without actually rotating.

.EXAMPLE
    ./19-Rotate-AllDKIM.ps1 -DryRun

.EXAMPLE
    ./19-Rotate-AllDKIM.ps1 -KeyLength 2048

.NOTES
    Required Exchange Online role: Global Administrator or Security Administrator.
    DKIM rotation is a sensitive operation; the script prompts for confirmation
    unless -Force is specified.
#>

[CmdletBinding()]
param(
    [ValidateSet(1024, 2048)]
    [int]$KeyLength = 2048,

    [int]$SkipDays = 180,

    [switch]$DryRun,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

try {
    $null = Get-OrganizationConfig -ErrorAction Stop
} catch {
    throw "Not connected to Exchange Online."
}

Write-Host "=== Bulk DKIM Rotation ===" -ForegroundColor Cyan
Write-Host "Key length: $KeyLength-bit"
Write-Host "Skip domains rotated within: $SkipDays days"
Write-Host "Dry run: $([bool]$DryRun)"
Write-Host ""

$domains = Get-AcceptedDomain | Where-Object { $_.DomainType -eq "Authoritative" }
Write-Host "Authoritative domains: $($domains.Count)" -ForegroundColor Cyan
Write-Host ""

$rotatePlan = @()
$skipPlan = @()

foreach ($d in $domains) {
    $dName = $d.DomainName
    $dkimConfig = Get-DkimSigningConfig -Identity $dName -ErrorAction SilentlyContinue

    if (-not $dkimConfig) {
        $skipPlan += [PSCustomObject]@{
            Domain = $dName
            Reason = "No DKIM config - use 13-Enable-DKIM.ps1 first"
        }
        continue
    }

    if (-not $dkimConfig.Enabled) {
        $skipPlan += [PSCustomObject]@{
            Domain = $dName
            Reason = "DKIM disabled"
        }
        continue
    }

    # Check last rotation date
    $lastRotation = $null
    if ($dkimConfig.PSObject.Properties.Name -contains "LastChecked") {
        $lastRotation = $dkimConfig.LastChecked
    }

    if ($lastRotation -and $lastRotation -gt (Get-Date).AddDays(-$SkipDays)) {
        $skipPlan += [PSCustomObject]@{
            Domain = $dName
            Reason = "Rotated within $SkipDays days (last: $lastRotation)"
        }
        continue
    }

    $rotatePlan += [PSCustomObject]@{
        Domain = $dName
        CurrentKeySize = if ($dkimConfig.PSObject.Properties.Name -contains "Selector1KeySize") { $dkimConfig.Selector1KeySize } else { "unknown" }
        LastRotation = if ($lastRotation) { $lastRotation } else { "never" }
    }
}

# Display plan
Write-Host "Rotation plan:" -ForegroundColor Cyan
if ($rotatePlan.Count -gt 0) {
    $rotatePlan | Format-Table -AutoSize
} else {
    Write-Host "  (no domains require rotation)" -ForegroundColor Yellow
}

if ($skipPlan.Count -gt 0) {
    Write-Host ""
    Write-Host "Skip plan:" -ForegroundColor Yellow
    $skipPlan | Format-Table -AutoSize
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete. No changes made." -ForegroundColor Cyan
    exit 0
}

if ($rotatePlan.Count -eq 0) {
    Write-Host ""
    Write-Host "No rotations to perform." -ForegroundColor Green
    exit 0
}

# Confirmation
if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Rotate DKIM for $($rotatePlan.Count) domain(s)? (type 'rotate')"
    if ($confirm -ne "rotate") { Write-Host "Aborted."; exit 1 }
}

# Execute
Write-Host ""
Write-Host "Executing rotation..." -ForegroundColor Cyan

$success = 0
$failed = 0

foreach ($item in $rotatePlan) {
    try {
        Rotate-DkimSigningConfig -Identity $item.Domain -KeySize $KeyLength
        Write-Host "  Rotated: $($item.Domain)" -ForegroundColor Green
        $success++
    } catch {
        Write-Host "  Failed:  $($item.Domain) - $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Rotation summary:" -ForegroundColor Cyan
Write-Host "  Success: $success"
Write-Host "  Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

Write-Host ""
Write-Host "What happens next:" -ForegroundColor Cyan
Write-Host "  - Exchange switches outbound signing to the alternate selector"
Write-Host "  - New messages sign with the new $KeyLength-bit key"
Write-Host "  - The old selector remains valid for a grace period (Exchange-managed)"
Write-Host "  - In-flight messages continue to verify against the old key during grace"
Write-Host ""
Write-Host "Record rotation in the annual package: domain list, date, new key length." -ForegroundColor Yellow
