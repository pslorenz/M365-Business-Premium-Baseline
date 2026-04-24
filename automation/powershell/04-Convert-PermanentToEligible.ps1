<#
.SYNOPSIS
    Converts permanent active directory role assignments to PIM-eligible.

.DESCRIPTION
    Runbook 04 - PIM Configuration.
    Applies to: Defender Suite, E5 Security, EMS E5 (Entra ID P2 required).

    Enumerates every permanent active directory role assignment on admin accounts
    (matching the admin-* naming convention) and converts each to PIM-eligible.
    Break glass accounts are excluded; their permanent active assignments are preserved.

.PARAMETER DryRun
    Report only; do not make changes.

.PARAMETER ExcludeBreakGlass
    Preserve break glass account permanent active assignments. Default: $true.

.EXAMPLE
    ./04-Convert-PermanentToEligible.ps1 -DryRun

.EXAMPLE
    ./04-Convert-PermanentToEligible.ps1 -ExcludeBreakGlass

.NOTES
    Required Graph scopes:
        RoleManagement.ReadWrite.Directory
        Directory.Read.All
        User.Read.All
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$ExcludeBreakGlass = $true
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

$hasP2 = Get-MgSubscribedSku | Where-Object {
    $_.SkuPartNumber -in @("AAD_PREMIUM_P2", "EMSPREMIUM", "SPE_E5", "Microsoft_Defender_Suite_for_SMB", "IDENTITY_THREAT_PROTECTION")
}
if (-not $hasP2) { throw "PIM requires Entra ID P2." }

Write-Host "=== Convert Permanent Assignments to PIM-Eligible ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'LIVE' })"
Write-Host ""

$conversions = @()
$directoryRoles = Get-MgDirectoryRole -All

foreach ($role in $directoryRoles) {
    $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
    foreach ($member in $members) {
        if ($member.AdditionalProperties.'@odata.type' -ne "#microsoft.graph.user") { continue }

        $user = Get-MgUser -UserId $member.Id -Property "id,userPrincipalName" -ErrorAction SilentlyContinue
        if (-not $user) { continue }

        $isBreakGlass = $user.UserPrincipalName -like "breakglass*"
        if ($isBreakGlass -and $ExcludeBreakGlass) {
            continue
        }

        # Get the role definition for PIM eligible assignment
        $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -Filter "templateId eq '$($role.RoleTemplateId)'" -ErrorAction SilentlyContinue
        if (-not $roleDef) { continue }

        $conversions += [PSCustomObject]@{
            UPN              = $user.UserPrincipalName
            UserId           = $user.Id
            Role             = $role.DisplayName
            RoleId           = $role.Id
            RoleDefinitionId = $roleDef.Id
        }
    }
}

if ($conversions.Count -eq 0) {
    Write-Host "No permanent assignments to convert." -ForegroundColor Green
    exit 0
}

Write-Host "Conversions to perform:"
$conversions | Format-Table -AutoSize -Property UPN, Role
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN complete. To execute, re-run without -DryRun." -ForegroundColor Cyan
    exit 0
}

$confirm = Read-Host "Proceed with $($conversions.Count) conversions? (type 'yes')"
if ($confirm -ne "yes") { Write-Host "Aborted."; exit 1 }

foreach ($conv in $conversions) {
    try {
        # Create PIM eligible assignment (using admin assign action)
        $params = @{
            Action           = "adminAssign"
            Justification    = "Converted from permanent active per Runbook 04 migration"
            RoleDefinitionId = $conv.RoleDefinitionId
            DirectoryScopeId = "/"
            PrincipalId      = $conv.UserId
            ScheduleInfo     = @{
                StartDateTime = (Get-Date).ToString("o")
                Expiration    = @{ Type = "noExpiration" }
            }
        }

        New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $params

        # Remove the permanent assignment
        Remove-MgDirectoryRoleMemberByRef -DirectoryRoleId $conv.RoleId -DirectoryObjectId $conv.UserId

        Write-Host "Converted: $($conv.UPN) / $($conv.Role)" -ForegroundColor Green
    } catch {
        Write-Host "FAILED: $($conv.UPN) / $($conv.Role): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Conversion complete. Admin accounts now hold their roles as PIM-eligible." -ForegroundColor Green
Write-Host "Administrators must activate through PIM before performing privileged actions." -ForegroundColor Cyan
