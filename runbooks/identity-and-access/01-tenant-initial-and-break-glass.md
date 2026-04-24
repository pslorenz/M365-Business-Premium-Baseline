# 01 - Tenant Initial Configuration and Break Glass Accounts

**Category:** Identity and Access
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:** Tenant exists, deploying technician has Global Administrator (or holds GDAP Global Administrator if MSP-deployed)
**Time to deploy:** 90 minutes active work, plus storage and testing steps
**Deployment risk:** Low. Additive changes only; no existing configuration is removed by this runbook.

## Purpose

Every Business Premium tenant needs two cloud-only emergency access accounts before any other security work begins. This runbook creates those accounts, tests them, configures the alerting that makes their use detectable, and verifies the initial tenant hygiene settings that form the foundation for every subsequent runbook. A tenant that has completed this runbook has the recovery capability required to safely proceed with the identity and Conditional Access runbooks, where misconfiguration can lock out administrative access.

The tenant before this runbook: a fresh or near-fresh Business Premium tenant, possibly running Security Defaults, possibly with the original admin account as the only Global Administrator. The tenant after: two tested break glass accounts in place with documented credentials, tenant hygiene settings verified, and the foundational audit and alerting configured to detect break glass use.

## Prerequisites

* Business Premium licensing is active in the tenant (confirm with `Get-MgSubscribedSku` or the Microsoft 365 admin center billing page)
* Deploying technician has Global Administrator access (permanent active, since PIM has not been configured yet)
* Physical storage option for break glass credentials is available (fireproof safe, secure cabinet, or documented split-knowledge storage)
* PowerShell 7 or later, with Microsoft.Graph and ExchangeOnlineManagement modules installed

## Target configuration

The tenant at completion has:

* Exactly two break glass accounts on the tenant's initial `*.onmicrosoft.com` domain, each with Global Administrator permanent active, long random passphrases, and credentials stored offline (cough cough FIDO 2 keys cough cough)
* A security group named `CA-Exclude-BreakGlass` containing both accounts, referenced for exclusion from future Conditional Access policies
* Unified Audit Log ingestion enabled
* Documented passphrase storage location and annual test schedule
* Verification that the initial admin account (the one used to create the tenant) is identified and will be addressed by subsequent admin-separation work
* Tenant-level settings verified: user tenant creation restricted, user application registration restricted, guest access restrictions set to most restrictive, guest invitation restricted to admin-only

The exact passphrase for each break glass account is organization-specific and is not included in the target configuration; the procedure generates passphrases randomly and the technician records them securely per internal policy.

## Deployment procedure

### Step 1: Verify tenant licensing and determine the initial onmicrosoft domain

```powershell
Connect-MgGraph -Scopes "Organization.Read.All", "Domain.Read.All"

# Confirm Business Premium is active
$hasSPB = (Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "SPB" }).PrepaidUnits.Enabled -gt 0
if (-not $hasSPB) {
    throw "Business Premium (SPB) not active in this tenant. Verify licensing before proceeding."
}

# Identify the initial onmicrosoft domain
$initialDomain = (Get-MgDomain | Where-Object { $_.IsInitial }).Id
Write-Host "Initial domain: $initialDomain"
```

Verification: the script outputs the `*.onmicrosoft.com` domain. This is the domain the break glass accounts will use.

### Step 2: Run the deployment script

```powershell
cd /path/to/m365-bp-baseline/automation/powershell

./01-Deploy-BreakGlass.ps1 `
    -Prefix "breakglass" `
    -ExcludeGroupName "CA-Exclude-BreakGlass" `
    -OutputPath "./break-glass-deployment-$(Get-Date -Format 'yyyyMMdd').txt"
```

The script:

1. Generates two 32-character random passphrases, longer is better
2. Creates two cloud-only accounts on the initial onmicrosoft domain, `breakglass01@yourtenant.onmicrosoft.com` and `breakglass02@yourtenant.onmicrosoft.com`, I suggest renaming these in the script
3. Assigns Global Administrator to both as permanent active
4. Creates the `CA-Exclude-BreakGlass` security group and adds both accounts as members
5. Enables Unified Audit Log ingestion if not already enabled
6. Writes the generated passphrases to the output file
7. Displays the output file path and reminds the operator to secure it

The output file contains the passphrases and is the only record. Treat it as tier-zero material from the moment the script finishes.

### Step 3: Secure the credentials physically

Do this immediately after Step 2, before closing the PowerShell session.

1. Print the output file, or transcribe the passphrases to paper
2. Seal each passphrase (one per envelope) in a tamper-evident envelope, signed across the seal
3. Place the envelopes in the designated secure storage (fireproof safe, bank safe deposit box, documented split-knowledge storage)
4. Delete the output file from the technician workstation (shred on Linux/macOS, secure delete on Windows)
5. Clear the PowerShell session history to remove any exposure of the passphrases
6. Document the storage location in the operations runbook (which storage, which date, which envelopes)

Verification: the operations runbook has an entry for the break glass deployment with date, technician, and storage location. The output file no longer exists on disk. The PowerShell session history is clean.

### Step 4: Test both break glass accounts annualy

From a fresh browser session (private window, ideally a machine that has not previously authenticated to the tenant):

1. Retrieve the first passphrase from the secure storage (break the seal on envelope 1)
2. Navigate to `https://entra.microsoft.com`
3. Sign in with `breakglass01@yourtenant.onmicrosoft.com` and the passphrase
4. Confirm the sign-in succeeds. Because Security Defaults may still be active at this stage, the sign-in may prompt for MFA registration. Skip or defer MFA registration; break glass accounts should not have MFA registered because MFA dependencies are exactly what break glass is supposed to sidestep.
5. Navigate to **Identity > Users > All users** and confirm the account appears as Global Administrator
6. Sign out
7. Repeat steps 1-6 for `breakglass02`
8. Rotate the passphrases in fresh envelopes or don't, sign across the seals, return to secure storage
9. Document the test in the operations runbook with date and outcome

Verification: both accounts successfully signed in and exercised Global Administrator. Both envelopes returned to secure storage. Test documented.

### Step 5: Enable Unified Audit Log if not already enabled

The deployment script should have enabled UAL in Step 2. Verify:

```powershell
Connect-ExchangeOnline
$ualConfig = Get-AdminAuditLogConfig
Write-Host "UnifiedAuditLogIngestionEnabled: $($ualConfig.UnifiedAuditLogIngestionEnabled)"
if (-not $ualConfig.UnifiedAuditLogIngestionEnabled) {
    Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
    Write-Host "UAL ingestion enabled. Wait 60 minutes for events to begin flowing."
}
```

Verification: UAL is reported as enabled. If it was just enabled, note that audit events take up to 60 minutes to begin appearing; downstream verification steps that rely on audit events should wait accordingly.

### Step 6: Verify tenant hygiene settings

```powershell
./01b-Verify-TenantHygiene.ps1
```

The verification script checks and reports on:

* User tenant creation (should be restricted)
* User application registration (should be restricted; will be re-verified after the Application Developer role is delegated in a later runbook)
* Guest access restrictions (should be most restrictive: `2af84b1e-32c8-42b7-82bc-daa82404023b`)
* Guest invitation restrictions (should be `adminsAndGuestInviters`)

The script does not modify settings automatically; it reports the current state. For a fresh tenant, these may already be at Microsoft's current defaults (which are reasonable for most) or may be at legacy permissive defaults. If any setting is not at the target state, run the corresponding remediation:

```powershell
# Restrict user tenant creation
./01c-Remediate-TenantHygiene.ps1 -Settings "TenantCreation"

# Restrict guest access
./01c-Remediate-TenantHygiene.ps1 -Settings "GuestAccess"

# Restrict guest invitation
./01c-Remediate-TenantHygiene.ps1 -Settings "GuestInvitation"

# Or all at once
./01c-Remediate-TenantHygiene.ps1 -Settings "All"
```

Verification: re-run `01b-Verify-TenantHygiene.ps1`. All settings report as at target state.

### Step 7: Configure the basic break glass sign-in alert

For tenants with Sentinel, Defender XDR, or Log Analytics, the alerting configuration is addressed in the audit and alerting runbook. For the phase 1 deployment, configure a minimum-viable alert using Entra's built-in alerting:

Navigate to **Entra admin center > Identity > Protection > Monitoring & operations > Alerts** (or in older tenants, the notifications under the Azure AD monitoring section) and configure email notifications for:

* Any sign-in from `breakglass01@yourtenant.onmicrosoft.com`
* Any sign-in from `breakglass02@yourtenant.onmicrosoft.com`

Destination email should be a monitored distribution list or a Microsoft Teams channel with notifications configured, not a single person's inbox.

This is a minimum-viable alert for phase 1. The full alerting posture with analytic rules on break glass sign-in and other tier-zero events is deployed in the audit and alerting runbook.

Verification: sign in with a break glass account briefly (as the test in Step 4). Confirm the alert fires within its evaluation window.

## Automation artifacts

* `automation/powershell/01-Deploy-BreakGlass.ps1` - Creates break glass accounts, assigns Global Administrator, creates exclusion group, enables UAL
* `automation/powershell/01b-Verify-TenantHygiene.ps1` - Reports current state of tenant hygiene settings
* `automation/powershell/01c-Remediate-TenantHygiene.ps1` - Applies tenant hygiene remediation

See `automation/powershell/README.md` for the environment setup (PowerShell 7, required modules, authentication).

## Verification

### Configuration verification

Run the verification script:

```powershell
./01-Verify-Deployment.ps1
```

Expected output:

```
Break Glass Accounts:
  breakglass01@yourtenant.onmicrosoft.com - Enabled: True, CloudOnly: True, GA: True
  breakglass02@yourtenant.onmicrosoft.com - Enabled: True, CloudOnly: True, GA: True

Exclusion Group:
  CA-Exclude-BreakGlass - 2 members - Both break glass accounts present

Unified Audit Log:
  UnifiedAuditLogIngestionEnabled: True

Tenant Hygiene:
  User tenant creation: Restricted
  User application registration: Restricted
  Guest access: Restricted
  Guest invitation: Admins and inviters only
```

Any failure in the verification output indicates a deployment step that did not complete successfully; re-run the corresponding step.

### Functional verification

Functional verification is the test performed in Step 4 (sign in with both break glass accounts, confirm success, confirm Global Administrator role exercises). If that test passed, functional verification is complete.

Additionally, confirm that the break glass sign-in alert (Step 7) fired during the Step 4 test. If the alert did not fire, re-verify the alert configuration before proceeding.

## Additional controls (add-on variants)

This runbook's universal content applies to all variants. The following additions apply where noted.

### Additional controls with Defender Suite, E5 Security, or EMS E5 (Entra ID P2)

For tenants with P2, the break glass accounts should be explicitly excluded from PIM's eligible assignment path. Break glass accounts hold Global Administrator as permanent active; PIM-eligible assignment is the correct pattern for every other admin but wrong for break glass.

The PIM configuration runbook (planned) will address this explicitly. For the initial deployment in this runbook, no additional PIM-related configuration is required; the permanent active assignment created by the deployment script is correct.

No additions required from Defender for Office 365 Plan 2 or Defender for Endpoint Plan 2; this runbook is identity-only.

## What to watch after deployment

* **Any sign-in from either break glass account outside of documented tests.** This is the core signal the alert configured in Step 7 is watching for. Every such sign-in is either an incident response in progress or an attacker with the credentials.
* **Unauthorized changes to the `CA-Exclude-BreakGlass` group membership.** The group should contain exactly the two break glass accounts. Any additional members require investigation; any removal of the break glass accounts breaks the exclusion pattern that future Conditional Access runbooks depend on.
* **Removal of the Global Administrator role from either break glass account.** Automation that reviews privileged role assignments occasionally flags break glass accounts as "permanent active tier-zero assignments" and removes them. Ensure the accounts are documented exceptions in any such automation.

## Rollback

Rollback is not recommended. Deleting break glass accounts returns the tenant to a state with no recovery path; if every administrative account is subsequently locked out, Microsoft Support engagement is the only recovery, and that engagement is slow and not guaranteed.

If a break glass account needs to be rotated (for example, the credentials were exposed through a disclosed or suspected breach of the physical storage), the correct response is to create a replacement account first, test the replacement, then disable the compromised account:

```powershell
./01d-Rotate-BreakGlass.ps1 -CurrentUPN "breakglass01@yourtenant.onmicrosoft.com" -Reason "Credential exposure"
```

The rotation script creates a new break glass account with the same pattern, tests it, and disables the old account. The disabled account remains in the directory for audit history; do not delete it.

## References

* Microsoft Learn: [Manage emergency access admin accounts in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)
* Microsoft Learn: [Configure Security Defaults](https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults)
* M365 Hardening Playbook: [Emergency access (break glass) accounts missing or misconfigured](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/emergency-access-accounts.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Section 1 (Entra ID) - emergency access account recommendations
* NIST CSF 2.0: PR.AA-01, PR.AA-05, RC.RP-01
