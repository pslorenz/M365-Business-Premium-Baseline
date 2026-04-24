<#
.SYNOPSIS
    Audits Entra directory role assignments and classifies them by tier.

.DESCRIPTION
    Runbook 03 - Admin Account Separation and Tier Model.
    Applies to: All variants.

    Enumerates every Entra directory role assignment in the tenant and produces a CSV with
    assignee details, assignment type, and tier classification. The output drives the
    subsequent admin account provisioning and migration work.

.PARAMETER OutputPath
    Path for the CSV output.

.EXAMPLE
    ./03-Audit-AdminAssignments.ps1 -OutputPath "./admin-audit-$(Get-Date -Format 'yyyyMMdd').csv"

.NOTES
    Required Graph scopes:
        RoleManagement.Read.Directory
        Directory.Read.All
        User.Read.All
        Group.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

$tier0RoleTemplates = @(
    "62e90394-69f5-4237-9190-012177145e10",  # Global Administrator
    "e8611ab8-c189-46e8-94e1-60213ab1f814",  # Privileged Role Administrator
    "7be44c8a-adaf-4e2a-84d6-ab2649e08a13"   # Privileged Authentication Administrator
)

$tier1RoleTemplates = @(
    "29232cdf-9323-42fd-ade2-1d097af3e4de",  # Exchange Administrator
    "f28a1f50-f6e7-4571-818b-6a12f2af6b6c",  # SharePoint Administrator
    "fe930be7-5e62-47db-91af-98c3a49a38b1",  # User Administrator
    "194ae4cb-b126-40b2-bd5b-6091b380977d",  # Security Administrator
    "3a2c62db-5318-420d-8d74-23affee5d9d5",  # Intune Administrator
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9",  # Conditional Access Administrator
    "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3",  # Application Administrator
    "158c047a-c907-4556-b7ef-446551a6b5f7",  # Cloud Application Administrator
    "b0f54661-2d74-4c50-afa3-1ec803f12efe",  # Billing Administrator
    "966707d0-3269-4727-9be2-8c3a10f19b9d",  # Helpdesk Administrator
    "e3973bdf-4987-49ae-837a-ba8e231c7286",  # Teams Administrator
    "fdd7a751-b60b-444a-984c-02652fe8fa1c"   # Groups Administrator
)

function Get-Tier {
    param([string]$RoleTemplateId)
    if ($RoleTemplateId -in $tier0RoleTemplates) { return 0 }
    if ($RoleTemplateId -in $tier1RoleTemplates) { return 1 }
    return 2
}

Write-Host "=== Admin Assignment Audit ===" -ForegroundColor Cyan
Write-Host "Tenant: $($context.TenantId)"
Write-Host ""

$results = @()
$roles = Get-MgDirectoryRole -All

foreach ($role in $roles) {
    $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
    foreach ($member in $members) {
        $memberType = $member.AdditionalProperties.'@odata.type'

        if ($memberType -eq "#microsoft.graph.user") {
            $user = Get-MgUser -UserId $member.Id `
                -Property "id,userPrincipalName,displayName,accountEnabled,onPremisesSyncEnabled,userType" `
                -ErrorAction SilentlyContinue

            $isBreakGlass = $user.UserPrincipalName -like "breakglass*"

            $results += [PSCustomObject]@{
                RoleDisplayName  = $role.DisplayName
                RoleTemplateId   = $role.RoleTemplateId
                Tier             = Get-Tier -RoleTemplateId $role.RoleTemplateId
                AssignmentType   = "Permanent (via directRole)"
                AssigneeType     = "User"
                AssigneeUPN      = $user.UserPrincipalName
                AssigneeName     = $user.DisplayName
                Enabled          = $user.AccountEnabled
                CloudOnly        = (-not [bool]$user.OnPremisesSyncEnabled)
                IsBreakGlass     = $isBreakGlass
                IsAdminPrefix    = $user.UserPrincipalName -like "admin-*"
                Notes            = if ($isBreakGlass) { "Break glass - expected permanent" }
                                    elseif (-not $user.UserPrincipalName -like "admin-*") { "DAILY DRIVER with role (migration target)" }
                                    else { "" }
            }
        } elseif ($memberType -eq "#microsoft.graph.group") {
            $group = Get-MgGroup -GroupId $member.Id -ErrorAction SilentlyContinue
            $results += [PSCustomObject]@{
                RoleDisplayName  = $role.DisplayName
                RoleTemplateId   = $role.RoleTemplateId
                Tier             = Get-Tier -RoleTemplateId $role.RoleTemplateId
                AssignmentType   = "Permanent (via group)"
                AssigneeType     = "Group"
                AssigneeUPN      = "(group)"
                AssigneeName     = $group.DisplayName
                Enabled          = $true
                CloudOnly        = $true
                IsBreakGlass     = $false
                IsAdminPrefix    = $false
                Notes            = "Group assignment - review members separately"
            }
        }
    }
}

# Also enumerate PIM eligible assignments if Entra P2 is available
try {
    $pimEligible = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -All -ErrorAction SilentlyContinue
    foreach ($eligible in $pimEligible) {
        $user = Get-MgUser -UserId $eligible.PrincipalId `
            -Property "id,userPrincipalName,displayName,accountEnabled" `
            -ErrorAction SilentlyContinue

        if ($user) {
            $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $eligible.RoleDefinitionId -ErrorAction SilentlyContinue
            $results += [PSCustomObject]@{
                RoleDisplayName  = $roleDefinition.DisplayName
                RoleTemplateId   = $roleDefinition.TemplateId
                Tier             = Get-Tier -RoleTemplateId $roleDefinition.TemplateId
                AssignmentType   = "PIM-eligible"
                AssigneeType     = "User"
                AssigneeUPN      = $user.UserPrincipalName
                AssigneeName     = $user.DisplayName
                Enabled          = $user.AccountEnabled
                CloudOnly        = $true
                IsBreakGlass     = $false
                IsAdminPrefix    = $user.UserPrincipalName -like "admin-*"
                Notes            = "PIM-eligible (activate through PIM)"
            }
        }
    }
} catch {
    Write-Warning "Could not enumerate PIM-eligible assignments (tenant may not have Entra ID P2): $_"
}

$results | Sort-Object Tier, RoleDisplayName, AssigneeUPN |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Audit complete. Results written to: $OutputPath" -ForegroundColor Green
Write-Host ""

# Summary by tier
$summary = $results | Group-Object Tier | ForEach-Object {
    [PSCustomObject]@{
        Tier = $_.Name
        AssignmentCount = $_.Count
        DistinctAssignees = ($_.Group | Where-Object { $_.AssigneeType -eq "User" } | Select-Object -ExpandProperty AssigneeUPN -Unique).Count
    }
}
$summary | Format-Table -AutoSize

# Highlight daily-driver accounts with roles
$dailyDrivers = $results | Where-Object {
    $_.AssigneeType -eq "User" -and
    -not $_.IsBreakGlass -and
    -not $_.IsAdminPrefix
}
if ($dailyDrivers.Count -gt 0) {
    Write-Host ""
    Write-Host "Daily-driver accounts holding directory roles (migration targets):" -ForegroundColor Yellow
    $dailyDrivers | Group-Object AssigneeUPN | Sort-Object Name | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) role(s)" -ForegroundColor Yellow
    }
}

$results | ConvertTo-Json -Depth 3 | Out-Null  # Return value not printed to avoid large console dump
