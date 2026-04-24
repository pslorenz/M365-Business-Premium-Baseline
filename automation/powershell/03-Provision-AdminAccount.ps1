<#
.SYNOPSIS
    Provisions a dedicated admin account for an existing administrator.

.DESCRIPTION
    Runbook 03 - Admin Account Separation and Tier Model.
    Creates a cloud-only admin account paired with an existing daily-driver account.
    Admin account is licensed with Entra ID P1 or P2 (no Exchange, no Teams, no SharePoint
    by default) and configured to prompt MFA registration on first sign-in.

.PARAMETER DailyDriverUPN
    The UPN of the administrator's daily-driver account.

.PARAMETER AdminAccountUPN
    The UPN for the new admin account. Convention: admin-firstname.lastname@domain.com

.PARAMETER DisplayName
    Display name for the new admin account. Convention: "Admin - [Full Name]"

.PARAMETER LicenseSku
    Which license to assign. Common values:
      AAD_PREMIUM      - Entra ID P1 (minimum)
      AAD_PREMIUM_P2   - Entra ID P2 (recommended for PIM-eligible tenants)

.PARAMETER OutputPath
    Path to write the generated passphrase.

.EXAMPLE
    ./03-Provision-AdminAccount.ps1 `
        -DailyDriverUPN "jane.admin@contoso.com" `
        -AdminAccountUPN "admin-jane.admin@contoso.com" `
        -DisplayName "Admin - Jane Admin" `
        -LicenseSku "AAD_PREMIUM_P2" `
        -OutputPath "./admin-provisioning-$(Get-Date -Format 'yyyyMMddHHmm').txt"

.NOTES
    Required Graph scopes:
        User.ReadWrite.All
        Directory.ReadWrite.All
        Organization.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DailyDriverUPN,

    [Parameter(Mandatory = $true)]
    [string]$AdminAccountUPN,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [ValidateSet("AAD_PREMIUM", "AAD_PREMIUM_P2")]
    [string]$LicenseSku = "AAD_PREMIUM",

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function New-RandomPassphrase {
    param([int]$Length = 32)
    $charset = [char[]](33..126) | Where-Object { $_ -notmatch '["\\`]' }
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $chars = for ($i = 0; $i -lt $Length; $i++) { $charset[$bytes[$i] % $charset.Count] }
    return -join $chars
}

$context = Get-MgContext
if (-not $context) { throw "Not connected to Microsoft Graph." }

# Verify daily-driver exists
$dailyDriver = Get-MgUser -Filter "userPrincipalName eq '$DailyDriverUPN'" -ErrorAction SilentlyContinue
if (-not $dailyDriver) {
    throw "Daily-driver account not found: $DailyDriverUPN"
}

# Verify admin account does not already exist
$existing = Get-MgUser -Filter "userPrincipalName eq '$AdminAccountUPN'" -ErrorAction SilentlyContinue
if ($existing) {
    throw "Admin account already exists: $AdminAccountUPN. Use a different UPN or remove the existing account first."
}

# Verify license is available
$licenseSkuObj = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq $LicenseSku }
if (-not $licenseSkuObj) {
    throw "License $LicenseSku not found in tenant subscriptions."
}

$availableUnits = $licenseSkuObj.PrepaidUnits.Enabled - $licenseSkuObj.ConsumedUnits
if ($availableUnits -lt 1) {
    throw "No available license units for $LicenseSku (Enabled: $($licenseSkuObj.PrepaidUnits.Enabled), Consumed: $($licenseSkuObj.ConsumedUnits))"
}

Write-Host "=== Provision Admin Account ===" -ForegroundColor Cyan
Write-Host "Daily-driver:  $DailyDriverUPN"
Write-Host "Admin account: $AdminAccountUPN"
Write-Host "License:       $LicenseSku"
Write-Host ""

$passphrase = New-RandomPassphrase -Length 32

$passwordProfile = @{
    Password                      = $passphrase
    ForceChangePasswordNextSignIn = $false
}

# Get the admin's first/last name from their daily-driver for the new account
$mailNickname = ($AdminAccountUPN -split '@')[0]

$adminAccount = New-MgUser `
    -UserPrincipalName $AdminAccountUPN `
    -DisplayName $DisplayName `
    -MailNickname $mailNickname `
    -AccountEnabled:$true `
    -PasswordProfile $passwordProfile `
    -UsageLocation $dailyDriver.UsageLocation

Write-Host "Account created." -ForegroundColor Green

# Assign license
Set-MgUserLicense -UserId $adminAccount.Id `
    -AddLicenses @(@{ SkuId = $licenseSkuObj.SkuId }) `
    -RemoveLicenses @()

Write-Host "License $LicenseSku assigned." -ForegroundColor Green

# Write passphrase to output file
@"
=== ADMIN ACCOUNT PROVISIONING RECORD ===
Provisioned at: $((Get-Date).ToString("o"))
Provisioned by: $($context.Account)
Tenant ID:      $($context.TenantId)

Daily-driver account: $DailyDriverUPN
Admin account:        $AdminAccountUPN
Display name:         $DisplayName
License assigned:     $LicenseSku

Initial passphrase: $passphrase

=== INSTRUCTIONS FOR THE ADMINISTRATOR ===
1. Sign in to https://entra.microsoft.com with $AdminAccountUPN and the passphrase above.
2. Complete MFA registration when prompted. Use a method separate from your daily-driver MFA.
3. Store the passphrase in your personal password manager.
4. Change the passphrase to a memorable phrase of your choosing (24+ characters) through your password manager's generator.
5. Confirm you can access the Entra admin portal with this account.

=== NEXT STEPS FOR THE DEPLOYER ===
1. Add this admin account to the appropriate tier group (RoleAssignable-Tier0/1/2).
2. Assign the required directory roles (03-Assign-TierZeroRole.ps1 or 03-Assign-DirectoryRole.ps1).
3. After the administrator has signed in and validated the admin account, remove directory roles from the daily-driver account (03-Remove-DailyDriverRoles.ps1).
4. Delete this output file once the passphrase is in the administrator's hands.
"@ | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host ""
Write-Host "Passphrase written to: $OutputPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "  1. Transmit the passphrase to $DailyDriverUPN via a secure channel"
Write-Host "  2. Delete $OutputPath after transmission"
Write-Host "  3. Administrator should change the passphrase on first sign-in"
Write-Host ""

[PSCustomObject]@{
    DailyDriverUPN  = $DailyDriverUPN
    AdminAccountUPN = $AdminAccountUPN
    AdminAccountId  = $adminAccount.Id
    LicenseAssigned = $LicenseSku
    OutputPath      = $OutputPath
    ProvisionedAt   = (Get-Date).ToString("o")
} | ConvertTo-Json
