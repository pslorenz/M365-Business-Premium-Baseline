# 03 - Admin Account Separation and Tier Model

**Category:** Identity and Access
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [01 - Tenant Initial Configuration and Break Glass Accounts](./01-tenant-initial-and-break-glass.md) completed
* [02 - Conditional Access Baseline Policy Stack](../conditional-access/02-ca-baseline-policy-stack.md) completed and enforced
**Time to deploy:** 60 to 90 minutes active work per admin being migrated, plus scheduling across administrators
**Deployment risk:** Medium. Changes admin workflow; communication and pilot are essential.

## Purpose

This runbook establishes the administrative account separation model that the rest of the baseline's privileged-access controls depend on. Every administrator in the tenant gets two accounts: a daily-driver account for mail, collaboration, and routine work, and a dedicated admin account for privileged operations. The two accounts are never used from the same browser session; privileged roles are assigned only to the admin account; the daily-driver account never holds directory roles.

The tenant before this runbook: administrators hold directory roles on their daily-driver accounts. The same account used to read mail and join Teams meetings also holds Global Administrator, Exchange Administrator, or similar privileged roles. Compromise of the daily-driver account through commodity phishing results in direct privilege escalation to tenant administration.

The tenant after: administrative roles held only by dedicated admin accounts that have narrowly-scoped licensing, no mailbox, no Teams membership, and sign-in patterns restricted by Conditional Access to admin portals. Daily-driver accounts hold no directory roles. A successful phish of a daily-driver account produces access to mail and collaboration but not to tenant administration.

The tier model is deliberately simple for SMB scale. Three tiers are sufficient: tier 0 (Global Administrator, Privileged Role Administrator, Privileged Authentication Administrator), tier 1 (other directory roles like Exchange Administrator, SharePoint Administrator, User Administrator, Security Administrator), and tier 2 (help desk and operator roles with narrow scope). Larger organizations use more elaborate models; the three-tier split covers the operational distinctions that actually matter for an SMB Business Premium tenant.

## Prerequisites

* Break glass accounts are in place and tested (Runbook 01)
* Conditional Access baseline is enforced, including CA003 (Require MFA for admins) and CA004 (Require MFA for Azure management) (Runbook 02)
* List of current administrators with their role assignments, produced by audit before this runbook
* Business Premium or E3/E5 licenses available to assign to new admin accounts (one per administrator being migrated)
* Documented approval from each administrator for the migration (the migration changes their daily workflow; do not surprise them)

## Target configuration

At completion of this runbook:

* Every active administrator has exactly two accounts: a daily-driver account and a dedicated admin account
* Admin accounts are named consistently (pattern: `admin-firstname.lastname@domain.com`), cloud-only where possible, assigned Entra ID P1 licensing only, no mailbox, no Teams membership
* Daily-driver accounts hold no Entra directory roles, no Exchange administrative roles, no SharePoint Site Collection Administrator grants beyond what they need for their own work
* Three tier groups exist in the directory: `RoleAssignable-Tier0`, `RoleAssignable-Tier1`, `RoleAssignable-Tier2` (these are role-assignable groups; more on this in the deployment procedure)
* Admin accounts are members of the appropriate tier group based on the highest role they require
* A documented record of who holds what role at what tier exists in the operations runbook
* An admin workstation or privileged access workstation (PAW) pattern is documented for tier-0 operations, even if only as a recommendation rather than enforced requirement

## Deployment procedure

### Step 1: Audit current administrative role assignments

```powershell
./03-Audit-AdminAssignments.ps1 -OutputPath "./admin-audit-$(Get-Date -Format 'yyyyMMdd').csv"
```

The audit script enumerates every Entra directory role with assignments and writes a CSV containing:
* Role display name and template ID
* Assignment type (permanent active, PIM-eligible, PIM-active)
* Assignee (user or group)
* Assignee's UPN and display name
* Whether the assignee is cloud-only or synced
* Whether the assignee is a break glass account
* Assignee's tier classification per the model

Review the output with each administrator. Document:
* Which assignments are required for the admin's current responsibilities
* Which assignments can be removed (stale grants from past projects, over-privileged grants for specific tasks)
* Which tier each required assignment falls into

This audit is also the source for the [M365 Hardening Playbook: Permanent Global Administrator assignments finding](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/permanent-global-admin-assignments.md). Tenants that have completed that finding can reuse the audit output.

### Step 2: Create the three tier groups as role-assignable

Role-assignable groups in Entra ID are groups that can hold directory role assignments. Once created, they cannot be converted back to standard groups, and their membership is restricted to prevent a non-privileged user from adding themselves to a role-assignable group. The three tier groups are created once and reused across all administrators.

```powershell
./03-Create-TierGroups.ps1
```

The script creates:
* `RoleAssignable-Tier0` - for accounts holding Global Administrator, Privileged Role Administrator, or Privileged Authentication Administrator
* `RoleAssignable-Tier1` - for accounts holding any other directory administrative role
* `RoleAssignable-Tier2` - for accounts holding narrowly-scoped operator roles (Helpdesk Administrator, Authentication Administrator, User Administrator where scoped)

Each group is created with `isAssignableToRole = true`, no mail, and a description documenting the purpose.

Verification: in the portal, **Entra admin center > Groups > All groups**, confirm the three groups exist and each has the "Role assignable" property set to Yes.

### Step 3: Provision admin accounts for each administrator

For each administrator identified in Step 1, create the corresponding admin account:

```powershell
./03-Provision-AdminAccount.ps1 `
    -DailyDriverUPN "jane.admin@contoso.com" `
    -AdminAccountUPN "admin-jane.admin@contoso.com" `
    -DisplayName "Admin - Jane Admin" `
    -LicenseSku "AAD_PREMIUM" `
    -OutputPath "./admin-provisioning-$(Get-Date -Format 'yyyyMMdd').txt"
```

The script:
1. Generates a random 32-character passphrase for the new admin account
2. Creates the cloud-only account with the specified UPN and display name
3. Assigns the specified license (Entra ID P1 alone is sufficient; full Business Premium is not required because the account does not need Exchange, Teams, or SharePoint licensing for administrative work)
4. Sets the mailbox setting to prevent Exchange licensing from creating a mailbox
5. Enables the account
6. Writes the passphrase to the output file (same handling as break glass: secure and delete)
7. Prompts the admin to complete MFA registration on first sign-in

Notes on the license selection:
* **Entra ID P1** is the minimum; it enables Conditional Access evaluation for the account and directory role assignment
* **Entra ID P2** (via Defender Suite, E5 Security, or EMS E5) is recommended for admin accounts because the admin account gets the full benefit of PIM eligibility workflows
* **Full Business Premium** is unnecessary for admin accounts because administrators use their daily-driver account for email and collaboration; assigning BP to admin accounts wastes licensing

Repeat for every administrator.

### Step 4: Assign directory roles to the admin accounts at the correct tier

For each admin account, assign the required directory roles. The preferred pattern is to add the admin account to the appropriate tier group and assign roles to the group rather than to the individual account. This is feasible for some roles but not all; some directory roles cannot be assigned to role-assignable groups.

Roles assignable to role-assignable groups (direct to group):
* Global Administrator (in tier 0 group)
* Privileged Role Administrator (tier 0)
* Privileged Authentication Administrator (tier 0)

Roles not assignable to role-assignable groups (must be assigned to the user directly):
* Most other directory roles (Exchange Administrator, SharePoint Administrator, Helpdesk Administrator, etc.)

For the group-assignable roles:
```powershell
./03-Assign-TierZeroRole.ps1 `
    -TierGroup "RoleAssignable-Tier0" `
    -Role "GlobalAdministrator" `
    -AssignmentType "Permanent"
```

Note: `AssignmentType "Permanent"` is correct for plain Business Premium tenants without PIM. For tenants with PIM (Defender Suite, E5 Security, EMS E5), assignments should be PIM-eligible (see [Runbook 04 - PIM Configuration](./04-pim-configuration.md)). Runbook 03 deploys permanent assignments as the baseline state; Runbook 04 converts them to eligible.

For user-direct assignments (tier 1 and tier 2 roles):
```powershell
./03-Assign-DirectoryRole.ps1 `
    -UserUPN "admin-jane.admin@contoso.com" `
    -Role "ExchangeAdministrator" `
    -AssignmentType "Permanent"
```

Use the audit output from Step 1 to drive these assignments. Each admin account receives only the roles the corresponding administrator actually needs.

### Step 5: Remove directory roles from daily-driver accounts

This step is the one that produces immediate administrative-workflow change for each administrator. The daily-driver account loses its privileged role grants; the administrator must sign in with their admin account to perform privileged operations from now on.

Sequence per administrator:
1. Confirm the admin account is provisioned, licensed, and role-assigned (Steps 3 and 4 complete for this administrator)
2. Confirm the admin has signed in successfully with the admin account at least once and registered MFA
3. Confirm the admin has validated that their admin account can perform the operations they need
4. Remove each directory role from the daily-driver account

```powershell
./03-Remove-DailyDriverRoles.ps1 -UserUPN "jane.admin@contoso.com" -DryRun
```

The script runs in dry-run mode by default, listing the roles that would be removed without making changes. Review the output, confirm with the administrator, then re-run without `-DryRun`:

```powershell
./03-Remove-DailyDriverRoles.ps1 -UserUPN "jane.admin@contoso.com"
```

Repeat for every administrator whose admin account has been provisioned.

### Step 6: Document the tier model and assignments

Update the operations runbook to record:
* Which administrators have admin accounts, when provisioned, which tier
* Which daily-driver accounts no longer hold directory roles, with the date the removal occurred
* The tier classification of each directory role in use by the tenant
* The expected location for the admin credentials (typically each admin's personal password manager, not in shared storage)
* The cadence for reviewing admin role assignments (quarterly, per Runbook 04 if PIM is in scope; annually otherwise)

### Step 7: Communicate the workflow change

Administrators now have two accounts and need to understand when to use each. The operational rules:

* Daily-driver account: mail, Teams, SharePoint, OneDrive, normal user operations
* Admin account: all privileged operations (Entra admin center, Exchange admin, Intune admin, Defender portal, Purview portal, any PowerShell that requires admin scopes)
* Never sign in to both accounts from the same browser session; use a separate browser profile or private window for admin account sign-ins
* Admin account sign-in is acceptable from the administrator's regular workstation for plain Business Premium tenants; for tenants with higher-assurance requirements, consider a dedicated privileged access workstation (PAW) or an isolated Windows account

The communication can be a short document and a 15-minute walkthrough. Most administrators adopt the pattern within a week once they have used it a few times.

## Automation artifacts

* `automation/powershell/03-Audit-AdminAssignments.ps1` - Enumerates current directory role assignments
* `automation/powershell/03-Create-TierGroups.ps1` - Creates the three role-assignable tier groups
* `automation/powershell/03-Provision-AdminAccount.ps1` - Creates and licenses an admin account
* `automation/powershell/03-Assign-TierZeroRole.ps1` - Assigns a tier-0 role to a tier group
* `automation/powershell/03-Assign-DirectoryRole.ps1` - Assigns a non-group-assignable role to an admin user directly
* `automation/powershell/03-Remove-DailyDriverRoles.ps1` - Removes directory role assignments from a daily-driver account
* `automation/powershell/03-Verify-Deployment.ps1` - Confirms the runbook's target configuration

## Verification

### Configuration verification

```powershell
./03-Verify-Deployment.ps1
```

Expected output:

```
Tier groups:
  RoleAssignable-Tier0: present, role-assignable, member count: [N]
  RoleAssignable-Tier1: present, role-assignable, member count: [N]
  RoleAssignable-Tier2: present, role-assignable, member count: [N]

Administrator accounts:
  Each current administrator has exactly one admin account
  Admin accounts are cloud-only or synced per design
  Admin accounts have P1 or P2 licensing
  Admin accounts do not have mailboxes

Daily-driver accounts:
  No daily-driver account holds a directory role (excluding break glass)

Tier-zero role assignments:
  Global Administrator: assigned to RoleAssignable-Tier0 group and to break glass accounts only
  Privileged Role Administrator: assigned to tier-0 group members only
  Privileged Authentication Administrator: assigned to tier-0 group members only

Tier-1 role assignments:
  Each assignment is to an admin account, not a daily-driver account

Tier-2 role assignments:
  Each assignment is to an admin account, not a daily-driver account
```

Any finding that contradicts this output indicates incomplete migration; resolve before considering the runbook complete.

### Functional verification

Per administrator, confirm:

1. **Admin account works for privileged operations.** Sign in as the admin account, navigate to **Entra admin center**, confirm the administrative portal is accessible and role-appropriate actions succeed.
2. **Daily-driver account no longer has privileged access.** Sign in as the daily-driver account, attempt to access **Entra admin center**. Expected: the portal loads but administrative actions (viewing all users, modifying policies, etc.) are unavailable or produce access-denied errors for actions that would have been permitted before.
3. **CA003 correctly applies to admin accounts.** Sign in as the admin account from a fresh session, confirm MFA is prompted (CA003 requires MFA for directory role holders, and the admin account holds directory roles).
4. **CA001 applies to daily-driver accounts but CA003 no longer applies.** Sign in as the daily-driver account, confirm MFA is prompted (CA001 requires MFA for all users) but that no additional admin-specific enforcement occurs.

## Additional controls (add-on variants)

### Additional controls with Defender Suite, E5 Security, or EMS E5 (Entra ID P2)

P2 variants can license admin accounts with Entra ID P2 rather than P1 to unlock PIM eligibility. The admin account provisioning script supports this:

```powershell
./03-Provision-AdminAccount.ps1 `
    -DailyDriverUPN "jane.admin@contoso.com" `
    -AdminAccountUPN "admin-jane.admin@contoso.com" `
    -DisplayName "Admin - Jane Admin" `
    -LicenseSku "AAD_PREMIUM_P2" `
    -OutputPath "./admin-provisioning-$(Get-Date -Format 'yyyyMMdd').txt"
```

For tenants with the add-on, the admin accounts should receive P2 licensing. The additional license cost over P1 is usually absorbed within the Defender Suite, E5 Security, or EMS E5 licensing the tenant has already acquired; P2 for admin accounts typically does not require additional licensing purchases.

After provisioning with P2, proceed directly to [Runbook 04 - PIM Configuration](./04-pim-configuration.md) to convert permanent active assignments to PIM-eligible.

### Additional controls with Defender Suite or E5 Security (Defender for Endpoint Plan 2)

No additions in this runbook; Defender for Endpoint Plan 2 controls are deployed in the device compliance runbooks.

## What to watch after deployment

* **Admin account password management.** Each admin account has its own passphrase that the administrator must manage. The recommendation is to use a password manager (1Password, Bitwarden, etc.) for the admin account credential. Document the expectation and provide guidance.
* **Help desk tickets for "I can't access the admin portal."** Expected in the first week as administrators adjust. Common pattern: administrator is signed in as daily-driver account in one browser window, opens a new tab, assumes they are the admin account, gets access denied. The fix is to use a separate browser profile or private window for admin work.
* **MFA registration for admin accounts.** Each admin account needs its own MFA methods registered. The administrator can use the same authenticator app with separate entries; registration is a one-time setup.
* **Session hygiene.** Administrators sometimes forget to sign out of the admin account and leave the session open, which is functionally equivalent to leaving the admin account signed in on an unlocked workstation. The CA policy stack does not automatically prevent this; behavior change does. Document the expectation; reinforce through the operations runbook reviews.

## Rollback

Rollback by re-adding directory roles to daily-driver accounts is straightforward but defeats the purpose of the runbook. The typical cause of rollback consideration is administrator frustration with the two-account pattern during the first week of adoption. Work through the frustration rather than rolling back; within 2 to 4 weeks the pattern is reflexive.

If a specific administrator's workflow genuinely cannot accommodate the two-account pattern (rare; typically indicates an underlying workflow issue that warrants separate solution), document the exception with a review date and a compensating control (for example, the administrator's daily-driver account is placed in a tighter CA policy targeting them specifically).

## References

* Microsoft Learn: [Best practices for Microsoft Entra roles](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices)
* Microsoft Learn: [Create a role-assignable group in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-create-eligible)
* Microsoft Learn: [Securing privileged access: Enterprise access model](https://learn.microsoft.com/en-us/security/privileged-access-workstations/privileged-access-access-model)
* Microsoft Learn: [Privileged Access Workstations](https://learn.microsoft.com/en-us/security/privileged-access-workstations/overview)
* M365 Hardening Playbook: [Permanent Global Administrator assignments (PIM not in use)](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/permanent-global-admin-assignments.md)
* M365 Hardening Playbook: [Application Administrator and Cloud Application Administrator treated as lower tier than Global Administrator](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/app-admin-cloud-app-admin-tier-zero.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Section 1.1 (Administrator role separation)
* NIST CSF 2.0: PR.AA-01, PR.AA-05
