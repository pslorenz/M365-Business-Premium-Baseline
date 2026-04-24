<#
.SYNOPSIS
    Configures tenant-level SharePoint external sharing settings.

.DESCRIPTION
    Runbook 22 - External Sharing Controls, Step 4.

    Deploys the tenant-wide SharePoint sharing baseline: authenticated external guests
    only (no anonymous links), 30-day anonymous expiry fallback, view-only default
    for anonymous links, guest reauthentication, and domain restrictions if configured.

.PARAMETER SharingCapability
    Tenant-level sharing tier. Default: ExternalUserSharingOnly (authenticated guests).
    Options:
      Disabled                         - No external sharing
      ExistingExternalUserSharingOnly  - Only guests already in directory
      ExternalUserSharingOnly          - New and existing guests (authenticated)
      ExternalUserAndGuestSharing      - Permits anonymous "Anyone" links

.PARAMETER DefaultLinkType
    Default: Direct (Specific people).
    Options: None, Direct (Specific people), Internal (Organization), AnonymousAccess.

.PARAMETER AnonymousLinkExpirationDays
    Default: 30. Maximum days before anonymous links expire.

.PARAMETER AnonymousLinkPermission
    Default: View. Options: None, View, Edit.

.PARAMETER RequireGuestReauth
    Default: true. Require guest email reauthentication.

.PARAMETER ReauthDays
    Default: 30.

.PARAMETER ExternalUserExpireInDays
    Default: 60. Remove guest accounts after this many days of inactivity.

.PARAMETER AllowedDomains
    Optional list of allowed external sharing domains. If set, domain restriction
    mode becomes AllowList.

.PARAMETER BlockedDomains
    Optional list of blocked domains. Mutually exclusive with AllowedDomains.

.EXAMPLE
    ./22-Deploy-TenantSharingSettings.ps1 -SharingCapability ExternalUserSharingOnly -DefaultLinkType Direct -AnonymousLinkExpirationDays 30 -AllowedDomains @("trusted-partner.com")

.NOTES
    Required: Connect-SPOService.
#>

[CmdletBinding()]
param(
    [ValidateSet("Disabled","ExistingExternalUserSharingOnly","ExternalUserSharingOnly","ExternalUserAndGuestSharing")]
    [string]$SharingCapability = "ExternalUserSharingOnly",

    [ValidateSet("None","Direct","Internal","AnonymousAccess")]
    [string]$DefaultLinkType = "Direct",

    [int]$AnonymousLinkExpirationDays = 30,

    [ValidateSet("None","View","Edit")]
    [string]$AnonymousLinkPermission = "View",

    [bool]$RequireGuestReauth = $true,

    [int]$ReauthDays = 30,

    [int]$ExternalUserExpireInDays = 60,

    [string[]]$AllowedDomains = @(),

    [string[]]$BlockedDomains = @()
)

$ErrorActionPreference = "Stop"

$spoAvailable = Get-Command Set-SPOTenant -ErrorAction SilentlyContinue
if (-not $spoAvailable) { throw "Connect-SPOService first." }

if ($AllowedDomains.Count -gt 0 -and $BlockedDomains.Count -gt 0) {
    throw "AllowedDomains and BlockedDomains are mutually exclusive."
}

Write-Host "=== Deploy Tenant Sharing Settings ===" -ForegroundColor Cyan
Write-Host "Sharing capability: $SharingCapability"
Write-Host "Default link type:  $DefaultLinkType"
Write-Host "Anonymous expiry:   $AnonymousLinkExpirationDays days"
Write-Host ""

try {
    $params = @{
        SharingCapability                          = $SharingCapability
        DefaultSharingLinkType                     = $DefaultLinkType
        RequireAnonymousLinksExpireInDays          = $AnonymousLinkExpirationDays
        FileAnonymousLinkType                      = $AnonymousLinkPermission
        FolderAnonymousLinkType                    = $AnonymousLinkPermission
        ExternalUserExpireInDays                   = $ExternalUserExpireInDays
        EmailAttestationRequired                   = $RequireGuestReauth
        EmailAttestationReAuthDays                 = $ReauthDays
        PreventExternalUsersFromResharing          = $true
        RequireAcceptingAccountMatchInvitedAccount = $true
        ShowPeoplePickerSuggestionsForGuestUsers   = $false
    }

    if ($AllowedDomains.Count -gt 0) {
        $params["SharingDomainRestrictionMode"] = "AllowList"
        $params["SharingAllowedDomainList"] = ($AllowedDomains -join " ")
    } elseif ($BlockedDomains.Count -gt 0) {
        $params["SharingDomainRestrictionMode"] = "BlockList"
        $params["SharingBlockedDomainList"] = ($BlockedDomains -join " ")
    }

    Set-SPOTenant @params -ErrorAction Stop

    Write-Host "Tenant sharing settings applied." -ForegroundColor Green

    if ($AllowedDomains.Count -gt 0) {
        Write-Host "  Allowed domains: $($AllowedDomains -join ', ')" -ForegroundColor Cyan
    }
    if ($BlockedDomains.Count -gt 0) {
        Write-Host "  Blocked domains: $($BlockedDomains -join ', ')" -ForegroundColor Cyan
    }
} catch {
    Write-Host "Failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Settings take effect within 15 to 60 minutes." -ForegroundColor Cyan
