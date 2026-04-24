<#
.SYNOPSIS
    Deploys break glass emergency access accounts for a Microsoft 365 Business Premium tenant.

.DESCRIPTION
    Runbook 01 - Tenant Initial Configuration and Break Glass Accounts.
    Applies to: All variants (Plain BP, Defender Suite, E5 Security, EMS E5).

    Creates two cloud-only Global Administrator accounts on the tenant's initial *.onmicrosoft.com
    domain, generates 32-character random passphrases, creates the CA-Exclude-BreakGlass security
    group and adds both accounts, and enables Unified Audit Log ingestion.

    The generated passphrases are written to the file specified by -OutputPath. The operator is
    responsible for securing and then destroying that file. The script does not store credentials
    anywhere else.

.PARAMETER Prefix
    The naming prefix for break glass accounts. Default: "breakglass".
    Produces accounts breakglass01 and breakglass02.

.PARAMETER ExcludeGroupName
    The display name of the security group to create. Default: "CA-Exclude-BreakGlass".

.PARAMETER OutputPath
    Path to write the generated passphrases. The operator must secure and then delete this file.

.PARAMETER Force
    Skip the confirmation prompt before creating accounts.

.EXAMPLE
    ./01-Deploy-BreakGlass.ps1 -OutputPath "./break-glass-$(Get-Date -Format 'yyyyMMdd').txt"

.NOTES
    Required Graph scopes:
        Directory.ReadWrite.All
        RoleManagement.ReadWrite.Directory
        Group.ReadWrite.All
        User.ReadWrite.All

    Required Exchange Online access:
        Organization Management role (for Set-AdminAuditLogConfig)
#>

[CmdletBinding()]
param(
    [string]$Prefix = "breakglass",
    [string]$ExcludeGroupName = "CA-Exclude-BreakGlass",
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function New-RandomPassphrase {
    param([int]$Length = 32)
    # ASCII printable range excluding quotes and backslash to avoid shell/JSON escape issues
    $charset = [char[]](33..126) | Where-Object { $_ -notmatch '["\\`]' }
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $chars = for ($i = 0; $i -lt $Length; $i++) { $charset[$bytes[$i] % $charset.Count] }
    return -join $chars
}

Write-Host "=== Break Glass Account Deployment ===" -ForegroundColor Cyan
Write-Host "Runbook 01 - M365 Business Premium Baseline" -ForegroundColor Cyan
Write-Host ""

# Verify Graph connection and required scopes
$context = Get-MgContext
if (-not $context) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph with required scopes before executing this script."
}

$requiredScopes = @(
    "Directory.ReadWrite.All",
    "RoleManagement.ReadWrite.Directory",
    "Group.ReadWrite.All",
    "User.ReadWrite.All"
)

$missingScopes = $requiredScopes | Where-Object { $_ -notin $context.Scopes }
if ($missingScopes) {
    throw "Missing required Graph scopes: $($missingScopes -join ', '). Reconnect with Connect-MgGraph -Scopes @($($requiredScopes | ForEach-Object { "`"$_`"" }) -join ', ')"
}

Write-Host "Connected to tenant: $($context.TenantId)" -ForegroundColor Green

# Identify initial domain
$initialDomain = (Get-MgDomain | Where-Object { $_.IsInitial }).Id
if (-not $initialDomain) {
    throw "Could not identify initial onmicrosoft.com domain for this tenant."
}
Write-Host "Initial domain: $initialDomain" -ForegroundColor Green

# Confirm Business Premium licensing
$hasSPB = (Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "SPB" }).PrepaidUnits.Enabled -gt 0
if (-not $hasSPB) {
    Write-Warning "Business Premium (SPB) not active in this tenant. Continuing, but verify licensing before proceeding in production."
}

# Confirm with operator unless -Force
if (-not $Force) {
    Write-Host ""
    Write-Host "This script will:" -ForegroundColor Yellow
    Write-Host "  1. Create accounts $Prefix`01@$initialDomain and $Prefix`02@$initialDomain"
    Write-Host "  2. Assign Global Administrator to both as permanent active"
    Write-Host "  3. Create security group '$ExcludeGroupName'"
    Write-Host "  4. Enable Unified Audit Log ingestion"
    Write-Host "  5. Write generated passphrases to: $OutputPath"
    Write-Host ""
    $confirm = Read-Host "Proceed? (type 'yes' to continue)"
    if ($confirm -ne "yes") {
        Write-Host "Aborted by operator."
        exit 1
    }
}

$results = @{
    Accounts      = @()
    Group         = $null
    UALEnabled    = $false
    OutputPath    = $OutputPath
    TenantId      = $context.TenantId
    DeployedAt    = (Get-Date).ToString("o")
}

# Create or verify accounts
$passphrases = @{}
1..2 | ForEach-Object {
    $accountNum  = $_.ToString("00")
    $upn         = "$Prefix$accountNum@$initialDomain"
    $displayName = "Break Glass $accountNum"

    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warning "Account $upn already exists. Skipping creation. Existing accounts are not rotated by this script; use 01d-Rotate-BreakGlass.ps1 if rotation is required."
        $results.Accounts += [PSCustomObject]@{
            UserPrincipalName = $upn
            Id                = $existing.Id
            Action            = "Existed"
            Passphrase        = $null
        }
        return
    }

    $passphrase = New-RandomPassphrase -Length 32
    $passphrases[$upn] = $passphrase

    $passwordProfile = @{
        Password                      = $passphrase
        ForceChangePasswordNextSignIn = $false
    }

    $newUser = New-MgUser `
        -UserPrincipalName $upn `
        -DisplayName $displayName `
        -MailNickname "$Prefix$accountNum" `
        -AccountEnabled:$true `
        -PasswordProfile $passwordProfile `
        -UsageLocation "US"

    # Assign Global Administrator (permanent active)
    $gaRoleTemplateId = "62e90394-69f5-4237-9190-012177145e10"  # Global Administrator role template
    $gaRole = Get-MgDirectoryRole -Filter "roleTemplateId eq '$gaRoleTemplateId'" -ErrorAction SilentlyContinue
    if (-not $gaRole) {
        # Activate the role if not yet active in this tenant
        $gaRole = New-MgDirectoryRole -RoleTemplateId $gaRoleTemplateId
    }

    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $gaRole.Id `
        -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)" }

    Write-Host "Created account: $upn" -ForegroundColor Green

    $results.Accounts += [PSCustomObject]@{
        UserPrincipalName = $upn
        Id                = $newUser.Id
        Action            = "Created"
        Passphrase        = "See output file"
    }
}

# Create or verify exclusion group
$existingGroup = Get-MgGroup -Filter "displayName eq '$ExcludeGroupName'" -ErrorAction SilentlyContinue
if ($existingGroup) {
    Write-Warning "Group '$ExcludeGroupName' already exists. Using existing group; verifying membership."
    $group = $existingGroup
} else {
    $group = New-MgGroup `
        -DisplayName $ExcludeGroupName `
        -MailEnabled:$false `
        -MailNickname ($ExcludeGroupName.ToLower() -replace '[^a-z0-9]', '') `
        -SecurityEnabled:$true `
        -Description "Security group for break glass account exclusion from Conditional Access policies. Membership: two break glass accounts only. Owner: [document here]. Do not add other members."
    Write-Host "Created group: $ExcludeGroupName" -ForegroundColor Green
}

# Add break glass accounts to group if not already members
foreach ($account in $results.Accounts) {
    $currentMembers = Get-MgGroupMember -GroupId $group.Id -All
    if ($account.Id -notin $currentMembers.Id) {
        New-MgGroupMember -GroupId $group.Id `
            -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($account.Id)" }
        Write-Host "Added $($account.UserPrincipalName) to $ExcludeGroupName" -ForegroundColor Green
    }
}

$results.Group = [PSCustomObject]@{
    DisplayName = $ExcludeGroupName
    Id          = $group.Id
    MemberCount = (Get-MgGroupMember -GroupId $group.Id -All).Count
}

# Enable UAL
Write-Host "Enabling Unified Audit Log ingestion..." -ForegroundColor Cyan
try {
    Connect-ExchangeOnline -ShowBanner:$false
    $ualConfig = Get-AdminAuditLogConfig
    if (-not $ualConfig.UnifiedAuditLogIngestionEnabled) {
        Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
        Write-Host "UAL ingestion enabled. Events begin flowing within 60 minutes." -ForegroundColor Green
    } else {
        Write-Host "UAL ingestion already enabled." -ForegroundColor Green
    }
    $results.UALEnabled = $true
} catch {
    Write-Warning "Could not enable UAL automatically. Run Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled `$true manually. Error: $_"
}

# Write output file
Write-Host ""
Write-Host "Writing deployment record to: $OutputPath" -ForegroundColor Cyan

$outputContent = @"
=== BREAK GLASS DEPLOYMENT RECORD ===
Tenant ID:    $($context.TenantId)
Deployed at:  $($results.DeployedAt)
Deployed by:  $($context.Account)
Initial domain: $initialDomain

=== ACCOUNTS ===

"@

foreach ($account in $results.Accounts) {
    $passphrase = if ($passphrases.ContainsKey($account.UserPrincipalName)) { $passphrases[$account.UserPrincipalName] } else { "(existing account; passphrase not set by this script)" }
    $outputContent += @"
UPN:        $($account.UserPrincipalName)
ID:         $($account.Id)
Action:     $($account.Action)
Passphrase: $passphrase

"@
}

$outputContent += @"

=== EXCLUSION GROUP ===
Name:         $($results.Group.DisplayName)
ID:           $($results.Group.Id)
Member count: $($results.Group.MemberCount)

=== UNIFIED AUDIT LOG ===
Enabled: $($results.UALEnabled)

=== IMPORTANT NEXT STEPS ===
1. Print or transcribe the passphrases to paper.
2. Seal each passphrase in a tamper-evident envelope.
3. Place envelopes in designated secure storage (safe, bank box, split-knowledge).
4. Delete this file from disk (shred/secure-delete).
5. Clear PowerShell session history: Clear-History (current session) and delete PSReadLine history if applicable.
6. Document the storage location in the operations runbook with date and technician.
7. Test both accounts (see Runbook 01, Step 4) before closing this deployment work item.
"@

$outputContent | Out-File -FilePath $OutputPath -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "=== DEPLOYMENT COMPLETE ===" -ForegroundColor Green
Write-Host "Output file: $OutputPath"
Write-Host ""
Write-Host "IMMEDIATE ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "  1. Secure the passphrases physically (see output file for full checklist)"
Write-Host "  2. Delete $OutputPath after securing"
Write-Host "  3. Clear PowerShell session history"
Write-Host "  4. Test both accounts per Runbook 01 Step 4"
Write-Host ""

# Return structured results for fleet automation
$results | ConvertTo-Json -Depth 4
