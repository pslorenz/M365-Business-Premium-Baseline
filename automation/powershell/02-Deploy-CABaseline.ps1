<#
.SYNOPSIS
    Deploys the Conditional Access baseline policy stack for Microsoft 365 Business Premium.

.DESCRIPTION
    Runbook 02 - Conditional Access Baseline Policy Stack.
    Applies to: All variants (variant-aware; deploys P2 policies only when licensed).

    Deploys seven universal policies plus three P2-specific policies (for tenants with
    Entra ID P2 via Defender Suite, E5 Security, or EMS E5). Policies are imported from
    JSON files in ../ca-policies/. All policies deploy in report-only mode by default;
    use 02d-Enforce-CABaseline.ps1 to switch them to on after the observation period.

    Universal policies (all variants):
      CA001 - Require MFA for all users
      CA002 - Block legacy authentication
      CA003 - Require MFA for admins
      CA004 - Require MFA for Azure management
      CA005 - Require MFA for device registration
      CA006 - Block sign-ins from unexpected countries
      CA007 - Require compliant or hybrid joined device for M365

    P2-dependent policies (Defender Suite, E5 Security, EMS E5):
      CA010 - Sign-in risk policy
      CA011 - User risk policy
      CA012 - Admin portal authentication context

.PARAMETER Mode
    Initial state of deployed policies.
    Valid values: ReportOnly (default), Disabled
    "Enabled" is NOT offered as an initial mode; use 02d-Enforce-CABaseline.ps1 after observation.

.PARAMETER BreakGlassExcludeGroup
    Display name of the break glass exclusion group. Default: "CA-Exclude-BreakGlass".

.PARAMETER Variant
    Variant handling.
    Valid values: Auto (detect from licensing), Universal (universal policies only),
    Full (deploy P2 policies regardless of licensing, useful for lab testing)

.PARAMETER PolicyPath
    Path to the directory containing the CA policy JSON files. Default: ../ca-policies

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    ./02-Deploy-CABaseline.ps1 -Mode ReportOnly -Variant Auto

.NOTES
    Required Graph scopes:
        Policy.ReadWrite.ConditionalAccess
        Policy.Read.All
        Application.Read.All
        Group.Read.All
        Directory.Read.All
        Organization.Read.All
#>

[CmdletBinding()]
param(
    [ValidateSet("ReportOnly", "Disabled")]
    [string]$Mode = "ReportOnly",

    [string]$BreakGlassExcludeGroup = "CA-Exclude-BreakGlass",

    [ValidateSet("Auto", "Universal", "Full")]
    [string]$Variant = "Auto",

    [string]$PolicyPath = "../ca-policies",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph with required scopes."
}

Write-Host "=== Conditional Access Baseline Deployment ===" -ForegroundColor Cyan
Write-Host "Tenant: $($context.TenantId)" -ForegroundColor Cyan
Write-Host ""

# Detect variant
$tenantSkus = (Get-MgSubscribedSku | Where-Object { $_.PrepaidUnits.Enabled -gt 0 }).SkuPartNumber
$hasP2 = @("Microsoft_Defender_Suite_for_SMB", "IDENTITY_THREAT_PROTECTION", "EMSPREMIUM", "AAD_PREMIUM_P2", "SPE_E5") |
    Where-Object { $_ -in $tenantSkus }

$deployP2Policies = switch ($Variant) {
    "Full"      { $true }
    "Universal" { $false }
    "Auto"      { [bool]$hasP2 }
}

$detectedVariant = if ($hasP2) {
    if ("Microsoft_Defender_Suite_for_SMB" -in $tenantSkus) { "Defender Suite" }
    elseif ("IDENTITY_THREAT_PROTECTION" -in $tenantSkus) { "E5 Security" }
    elseif ("EMSPREMIUM" -in $tenantSkus) { "EMS E5" }
    elseif ("AAD_PREMIUM_P2" -in $tenantSkus) { "Entra P2 standalone" }
    else { "P2 (via M365 E5)" }
} else {
    "Plain Business Premium"
}

Write-Host "Detected variant: $detectedVariant" -ForegroundColor Green
Write-Host "Will deploy P2 policies: $deployP2Policies" -ForegroundColor Green
Write-Host "Deployment mode: $Mode" -ForegroundColor Green
Write-Host ""

# Locate break glass exclusion group
$excludeGroup = Get-MgGroup -Filter "displayName eq '$BreakGlassExcludeGroup'" -ErrorAction SilentlyContinue
if (-not $excludeGroup) {
    throw "Break glass exclusion group '$BreakGlassExcludeGroup' not found. Run Runbook 01 first."
}
$excludeGroupId = $excludeGroup.Id
Write-Host "Exclusion group: $BreakGlassExcludeGroup ($excludeGroupId)" -ForegroundColor Green

# Locate policy JSON files
$scriptDir = Split-Path -Parent $PSCommandPath
$resolvedPolicyPath = Resolve-Path (Join-Path $scriptDir $PolicyPath) -ErrorAction SilentlyContinue
if (-not $resolvedPolicyPath) {
    throw "Policy path '$PolicyPath' not found relative to script location."
}

$universalFiles = @(
    "02-ca001-mfa-all-users.json",
    "02-ca002-block-legacy-auth.json",
    "02-ca003-mfa-admins.json",
    "02-ca004-mfa-azure-management.json",
    "02-ca005-mfa-device-registration.json",
    "02-ca006-country-block.json",
    "02-ca007-compliant-device.json"
)

$p2Files = @(
    "02-ca010-signin-risk.json",
    "02-ca011-user-risk.json",
    "02-ca012-admin-auth-context.json"
)

$filesToDeploy = $universalFiles
if ($deployP2Policies) { $filesToDeploy += $p2Files }

# Confirm
if (-not $Force) {
    Write-Host ""
    Write-Host "About to deploy $($filesToDeploy.Count) Conditional Access policies in $Mode mode." -ForegroundColor Yellow
    Write-Host "All policies will exclude the $BreakGlassExcludeGroup group." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Proceed? (type 'yes' to continue)"
    if ($confirm -ne "yes") {
        Write-Host "Aborted."
        exit 1
    }
}

# Deploy each policy
$stateValue = switch ($Mode) {
    "ReportOnly" { "enabledForReportingButNotEnforced" }
    "Disabled"   { "disabled" }
}

$results = @()

foreach ($file in $filesToDeploy) {
    $fullPath = Join-Path $resolvedPolicyPath $file
    if (-not (Test-Path $fullPath)) {
        Write-Warning "Policy file not found: $file. Skipping."
        $results += [PSCustomObject]@{ Policy = $file; Status = "SKIPPED"; Reason = "File not found" }
        continue
    }

    $policyJson = Get-Content $fullPath -Raw | ConvertFrom-Json -AsHashtable

    # Strip metadata keys (convention: leading underscore) before submitting to Graph.
    # Keys like _comment, _requires, _namedLocation, _authenticationContext, _authenticationStrength
    # are deployment-time metadata; Graph rejects unknown properties.
    $metadataKeys = @($policyJson.Keys | Where-Object { $_ -match '^_' })
    foreach ($key in $metadataKeys) {
        $null = $policyJson.Remove($key)
    }

    # Substitute the break glass group placeholder with the actual group ID
    if ($policyJson.conditions.users.excludeGroups) {
        $policyJson.conditions.users.excludeGroups = @($excludeGroupId)
    } else {
        $policyJson.conditions.users["excludeGroups"] = @($excludeGroupId)
    }

    # Override state per parameter
    $policyJson.state = $stateValue

    # Check if policy with this display name already exists
    $existing = Get-MgIdentityConditionalAccessPolicy -All |
        Where-Object { $_.DisplayName -eq $policyJson.displayName }

    try {
        if ($existing) {
            Write-Warning "Policy '$($policyJson.displayName)' already exists. Skipping (use 02d to enforce or 02e to disable)."
            $results += [PSCustomObject]@{
                Policy = $policyJson.displayName
                Status = "EXISTS"
                Id     = $existing.Id
                State  = $existing.State
            }
        } else {
            $body = $policyJson | ConvertTo-Json -Depth 10
            $created = Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
                -Body $body `
                -ContentType "application/json"

            Write-Host "Deployed: $($policyJson.displayName)" -ForegroundColor Green
            $results += [PSCustomObject]@{
                Policy = $policyJson.displayName
                Status = "DEPLOYED"
                Id     = $created.id
                State  = $stateValue
            }
        }
    } catch {
        Write-Host "FAILED to deploy $($policyJson.displayName): $_" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Policy = $policyJson.displayName
            Status = "FAILED"
            Reason = $_.ToString()
        }
    }
}

Write-Host ""
Write-Host "=== Deployment Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Monitor for 14 days: ./02b-Monitor-CABaseline.ps1" -ForegroundColor Cyan
Write-Host "  2. Resolve findings (legacy auth sources, country exceptions, etc.)"
Write-Host "  3. Disable Security Defaults: ./02c-Disable-SecurityDefaults.ps1"
Write-Host "  4. Enforce baseline: ./02d-Enforce-CABaseline.ps1"
Write-Host ""

$results | ConvertTo-Json -Depth 3
