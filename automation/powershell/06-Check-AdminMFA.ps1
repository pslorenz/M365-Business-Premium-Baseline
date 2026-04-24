<#
.SYNOPSIS
    Reports phishing-resistant MFA registration for administrators in tier-0 and tier-1 groups.

.DESCRIPTION
    Runbook 06 - Authentication Context for Admin Portals.
    Applies to: Defender Suite, E5 Security, EMS E5 (P2 required).

    Enumerates members of RoleAssignable-Tier0 and RoleAssignable-Tier1 groups,
    reports each member's registered authentication methods, and flags administrators
    who lack a phishing-resistant method (FIDO2, Windows Hello for Business, or
    certificate-based authentication).

.EXAMPLE
    ./06-Check-AdminMFA.ps1

.NOTES
    Required Graph scopes:
        UserAuthenticationMethod.Read.All
        Group.Read.All
        User.Read.All
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

Write-Host "=== Admin MFA Registration Check ===" -ForegroundColor Cyan
Write-Host ""

$tierGroups = @("RoleAssignable-Tier0", "RoleAssignable-Tier1")
$allAdmins = @()

foreach ($groupName in $tierGroups) {
    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Warning "Group $groupName not found. Run Runbook 03 first."
        continue
    }
    $members = Get-MgGroupMember -GroupId $group.Id -All
    foreach ($m in $members) {
        if ($m.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.user") {
            $user = Get-MgUser -UserId $m.Id -Property "id,userPrincipalName,displayName,accountEnabled" -ErrorAction SilentlyContinue
            if ($user -and $user.AccountEnabled) {
                $allAdmins += [PSCustomObject]@{
                    UPN = $user.UserPrincipalName
                    DisplayName = $user.DisplayName
                    Tier = $groupName
                    UserId = $user.Id
                }
            }
        }
    }
}

if ($allAdmins.Count -eq 0) {
    Write-Host "No administrators found in tier groups." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($allAdmins.Count) administrators in tier groups."
Write-Host ""

$results = @()

foreach ($admin in $allAdmins) {
    try {
        $methods = Get-MgUserAuthenticationMethod -UserId $admin.UserId -All

        $hasFido2 = $methods | Where-Object {
            $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.fido2AuthenticationMethod"
        }
        $hasHello = $methods | Where-Object {
            $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod"
        }
        $hasCert = $methods | Where-Object {
            $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.x509CertificateAuthenticationMethod"
        }
        $hasPasskey = $methods | Where-Object {
            $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" -and
            $_.AdditionalProperties.deviceTag -match "passkey"
        }

        $hasPhishResistant = ($hasFido2.Count + $hasHello.Count + $hasCert.Count + $hasPasskey.Count) -gt 0

        $methodSummary = @()
        if ($hasFido2) { $methodSummary += "FIDO2($($hasFido2.Count))" }
        if ($hasHello) { $methodSummary += "WHfB($($hasHello.Count))" }
        if ($hasCert)  { $methodSummary += "Cert($($hasCert.Count))" }
        if ($hasPasskey) { $methodSummary += "Passkey($($hasPasskey.Count))" }
        if ($methodSummary.Count -eq 0) { $methodSummary += "None phishing-resistant" }

        $results += [PSCustomObject]@{
            UPN = $admin.UPN
            Tier = $admin.Tier
            PhishResistant = $hasPhishResistant
            Methods = ($methodSummary -join "; ")
            Status = if ($hasPhishResistant) { "PASS" } else { "BLOCKED by CA012 when enforced" }
        }
    } catch {
        $results += [PSCustomObject]@{
            UPN = $admin.UPN
            Tier = $admin.Tier
            PhishResistant = $false
            Methods = "Error: $_"
            Status = "UNKNOWN"
        }
    }
}

$results | Format-Table -AutoSize -Wrap

Write-Host ""
$missing = $results | Where-Object { -not $_.PhishResistant }
if ($missing.Count -eq 0) {
    Write-Host "All administrators have phishing-resistant MFA registered." -ForegroundColor Green
    Write-Host "Safe to enforce CA012." -ForegroundColor Green
} else {
    Write-Host "$($missing.Count) administrator(s) lack phishing-resistant MFA." -ForegroundColor Yellow
    Write-Host "DO NOT enforce CA012 until these administrators register:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  - $($_.UPN)" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Registration URL: https://mysecurityinfo.microsoft.com" -ForegroundColor Cyan
}
