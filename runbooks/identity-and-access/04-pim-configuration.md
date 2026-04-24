# 04 - PIM Configuration (P2 Variants)

**Category:** Identity and Access
**Applies to:** Defender Suite, E5 Security, EMS E5 (any variant with Entra ID P2)
**Not applicable to:** Plain Business Premium (PIM is a P2 feature)
**Prerequisites:**
* [01 - Tenant Initial Configuration and Break Glass Accounts](./01-tenant-initial-and-break-glass.md) completed
* [02 - Conditional Access Baseline Policy Stack](../conditional-access/02-ca-baseline-policy-stack.md) completed and enforced
* [03 - Admin Account Separation and Tier Model](./03-admin-account-separation.md) completed with admin accounts licensed for Entra ID P2
**Time to deploy:** 90 minutes active work, plus ongoing administrator training during the first week
**Deployment risk:** Medium. PIM activation changes the daily admin workflow; administrators must adapt.

## Purpose

Privileged Identity Management (PIM) converts persistent administrative role assignments into just-in-time elevation, where administrators hold roles in eligible state by default and activate them for a time-limited window when needed. An attacker who compromises an admin account finds it inactive for administrative operations most of the time; activation requires MFA, optionally approval, and produces audit signal that is caught by the alerting configured in later runbooks.

The tenant before this runbook: admin accounts (from Runbook 03) hold directory roles as permanent active assignments. Compromise of an admin account at any time produces immediate privileged access. Administrator activity in privileged roles is indistinguishable in routine logs from non-privileged activity by the admin account.

The tenant after: tier-0 roles (Global Administrator, Privileged Role Administrator, Privileged Authentication Administrator) are PIM-eligible with approval workflow and tight activation window. Tier-1 roles are PIM-eligible without approval but with activation audit. Tier-2 roles are PIM-eligible with shorter activation windows. Compromise of an admin account produces access only if the attacker can complete the PIM activation, which requires MFA and, for tier 0, approval from another administrator.

PIM is the single highest-value control available to SMBs through the P2 add-on. Tenants on plain Business Premium have no PIM equivalent; compensating controls (tighter Conditional Access on admin accounts, manual periodic role review, monitoring for admin sign-ins from anomalous contexts) are weaker substitutes. The Defender Suite add-on at roughly $10-12 per user per month is the path for SMBs to acquire PIM; the value-per-dollar is not matched by any other add-on for this class of control.

## Prerequisites

* Tenant has Entra ID P2 via Defender Suite, E5 Security, EMS E5, or Entra ID P2 standalone
* Admin accounts from Runbook 03 are licensed with Entra ID P2 (or the P2 is implicit through the tenant-wide variant licensing)
* Tier groups (`RoleAssignable-Tier0`, `RoleAssignable-Tier1`, `RoleAssignable-Tier2`) exist from Runbook 03
* Break glass accounts are permanent active Global Administrator; they are not managed through PIM
* Administrators are available for a 30-minute walkthrough during the first week of activation workflow

## Target configuration

At completion:

* **Break glass accounts remain permanent active Global Administrator.** PIM does not apply to break glass; they sit outside the PIM workflow by design. This is intentional and correct.
* **Tier-0 roles** (Global Administrator, Privileged Role Administrator, Privileged Authentication Administrator): eligible assignments only, maximum activation duration 4 hours, activation requires MFA, activation requires approval from another tier-0 administrator, justification required, ticket number optional
* **Tier-1 roles** (Exchange Administrator, SharePoint Administrator, User Administrator, Security Administrator, and all other directory admin roles): eligible assignments only, maximum activation duration 8 hours, activation requires MFA, no approval required, justification required
* **Tier-2 roles** (Helpdesk Administrator, Authentication Administrator, and narrow operator roles): eligible assignments only, maximum activation duration 4 hours, activation requires MFA, no approval required, justification required
* **Access reviews** are scheduled quarterly for tier-0 roles, semi-annually for tier-1 and tier-2 roles
* **PIM notifications** are configured to send to a monitored distribution list for all tier-0 activations and for tier-1/tier-2 activations outside business hours

## Deployment procedure

### Step 1: Configure PIM role settings for tier-0 roles

PIM role settings control what happens when a role is activated. The settings differ by tier; tier-0 is the strictest configuration.

```powershell
./04-Configure-PIMRoleSetting.ps1 `
    -Role "GlobalAdministrator" `
    -Tier 0
```

The script configures the following settings via Graph (specifically the `unifiedRoleManagementPolicy` resource):

| Setting | Tier 0 Value |
|---|---|
| Maximum activation duration | 4 hours |
| MFA required on activation | Yes |
| Justification required | Yes |
| Ticket information required | No (optional) |
| Approval required | Yes |
| Approvers | Members of `RoleAssignable-Tier0` group (excluding the requesting user) |
| Notifications | Send to `pim-alerts@contoso.com` on activation, assignment changes, and approval workflow |

Repeat for Privileged Role Administrator and Privileged Authentication Administrator:

```powershell
./04-Configure-PIMRoleSetting.ps1 -Role "PrivilegedRoleAdministrator" -Tier 0
./04-Configure-PIMRoleSetting.ps1 -Role "PrivilegedAuthenticationAdministrator" -Tier 0
```

Verification: in the portal, **Entra admin center > Identity governance > Privileged Identity Management > Microsoft Entra roles > Roles > [role] > Role settings**, confirm the settings match the tier-0 target.

### Step 2: Configure PIM role settings for tier-1 roles

Tier-1 roles use a less restrictive activation workflow (no approval) but still require MFA and justification:

```powershell
$tier1Roles = @(
    "ExchangeAdministrator",
    "SharePointAdministrator",
    "UserAdministrator",
    "SecurityAdministrator",
    "IntuneAdministrator",
    "ConditionalAccessAdministrator",
    "ApplicationAdministrator",
    "CloudApplicationAdministrator",
    "BillingAdministrator",
    "HelpdeskAdministrator"
)

foreach ($role in $tier1Roles) {
    ./04-Configure-PIMRoleSetting.ps1 -Role $role -Tier 1
}
```

Tier-1 role settings:

| Setting | Tier 1 Value |
|---|---|
| Maximum activation duration | 8 hours |
| MFA required on activation | Yes |
| Justification required | Yes |
| Ticket information required | No |
| Approval required | No |
| Notifications | Send to pim-alerts distribution for after-hours activations |

Note: Application Administrator and Cloud Application Administrator appear in this tier-1 list but are treated as tier-0 by the [M365 Hardening Playbook finding](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/app-admin-cloud-app-admin-tier-zero.md) because of their credential-add capability against privileged service principals. Organizations with mature service principal hygiene (per the [Service principals finding](https://github.com/pslorenz/m365-hardening-playbook/blob/main/applications-and-consent/service-principals-tier-zero-permissions.md)) may accept tier-1 for these roles; organizations without that hygiene should treat these as tier-0 (requires approval). The script supports either interpretation:

```powershell
# Treat Application Administrator as tier 0 (stricter, recommended for most tenants)
./04-Configure-PIMRoleSetting.ps1 -Role "ApplicationAdministrator" -Tier 0
./04-Configure-PIMRoleSetting.ps1 -Role "CloudApplicationAdministrator" -Tier 0
```

### Step 3: Configure PIM role settings for tier-2 roles

Tier-2 covers narrow operator roles:

```powershell
./04-Configure-PIMRoleSetting.ps1 -Role "ServiceSupportAdministrator" -Tier 2
./04-Configure-PIMRoleSetting.ps1 -Role "MessageCenterReader" -Tier 2
./04-Configure-PIMRoleSetting.ps1 -Role "ReportsReader" -Tier 2
```

Tier-2 role settings:

| Setting | Tier 2 Value |
|---|---|
| Maximum activation duration | 4 hours |
| MFA required on activation | Yes |
| Justification required | Yes |
| Ticket information required | No |
| Approval required | No |

### Step 4: Convert existing permanent assignments to eligible

For each admin account and each directory role currently assigned as permanent active, convert to PIM-eligible. The break glass accounts are NOT converted; they stay permanent active.

```powershell
./04-Convert-PermanentToEligible.ps1 `
    -DryRun `
    -ExcludeBreakGlass
```

Dry run output shows what would change:

```
Admin accounts to convert (excluding break glass):
  admin-jane.admin@contoso.com:
    - Global Administrator (permanent active) -> PIM-eligible
    - Exchange Administrator (permanent active) -> PIM-eligible
  admin-bob.admin@contoso.com:
    - Intune Administrator (permanent active) -> PIM-eligible

Total conversions: 3 assignments across 2 accounts
```

Review the dry-run output with each affected administrator. Confirm they understand that on the next administrative action, they will need to activate the role through PIM before the action succeeds.

After confirmation, run without dry-run:

```powershell
./04-Convert-PermanentToEligible.ps1 -ExcludeBreakGlass
```

The script processes each conversion, logging the action and any errors. For group-assignable roles (tier-0 roles assigned to tier groups from Runbook 03), the conversion applies to the group assignment; individual members of the group inherit eligibility.

### Step 5: Configure PIM activation notifications

PIM sends notifications on activation requests, activations, role assignments, and other events. Configure the destination:

```powershell
./04-Configure-PIMNotifications.ps1 `
    -TierZeroAlertEmail "tier-zero-alerts@contoso.com" `
    -AllTierAlertEmail "pim-alerts@contoso.com"
```

The script configures notifications per role, routing:
* Tier-0 activation approval requests, approvals, denials, and activations to the tier-zero alert distribution
* Tier-1 and tier-2 activations outside business hours to the general PIM alert distribution
* All role assignment changes to both distributions

The destination addresses should be monitored distribution lists or Teams channel connectors with active recipients, not personal inboxes.

### Step 6: Configure access reviews

Access reviews automate the periodic validation of who still needs which role. Configure:

```powershell
./04-Configure-AccessReviews.ps1
```

The script creates three access review schedules:

* **Tier-0 access review.** Quarterly, covers all eligible and active Global Administrator, Privileged Role Administrator, and Privileged Authentication Administrator assignments. Reviewers: tier-0 group members. Auto-apply results after 7-day review window. Self-review prohibited (tier-0 admin cannot review their own assignment).
* **Tier-1 access review.** Semi-annually, covers all tier-1 role eligible and active assignments. Reviewers: tier-0 group members. Auto-apply results after 14-day review window.
* **Tier-2 access review.** Semi-annually, covers all tier-2 role eligible and active assignments. Reviewers: tier-1 or tier-0 administrators. Auto-apply results after 14-day review window.

Access reviews require Entra ID Governance licensing on top of P2 in some scenarios. Verify licensing before deploying; for tenants without Governance, manual quarterly reviews via the operations runbook are the compensating pattern.

### Step 7: Test the activation workflow

For each administrator, test PIM activation end-to-end:

1. Administrator signs in as their admin account
2. Navigates to **Entra admin center > Identity governance > Privileged Identity Management > My roles**
3. Selects an eligible role, clicks Activate
4. Completes MFA challenge
5. Enters justification
6. For tier-0: waits for approval from another tier-0 administrator, observes approval notification, activation completes
7. For tier-1/tier-2: activation completes immediately after justification
8. Performs a privileged action (create a test user, modify a test policy) to confirm the role is active
9. Role automatically deactivates at the end of the activation window

The walkthrough is typically 15 to 30 minutes per administrator. Scheduling with each administrator during the first week of deployment is the best way to ensure the workflow is understood.

### Step 8: Update operations runbook

Document the PIM configuration:
* Which roles are in each tier
* Activation duration and approval requirements per tier
* Who are the approvers for tier-0 activations
* Where PIM notifications land and who monitors them
* The access review schedule and who receives the review responsibilities
* The process for requesting a new eligible assignment (typically: existing tier-1 or tier-0 administrator creates the eligibility, documented in a ticket)

## Automation artifacts

* `automation/powershell/04-Configure-PIMRoleSetting.ps1` - Configures PIM role settings for a specified role and tier
* `automation/powershell/04-Convert-PermanentToEligible.ps1` - Converts permanent active assignments to PIM-eligible
* `automation/powershell/04-Configure-PIMNotifications.ps1` - Routes PIM notifications to monitored destinations
* `automation/powershell/04-Configure-AccessReviews.ps1` - Schedules recurring access reviews per tier
* `automation/powershell/04-Verify-Deployment.ps1` - Confirms the PIM configuration

## Verification

### Configuration verification

```powershell
./04-Verify-Deployment.ps1
```

Expected output:

```
Tenant variant: [Defender Suite | E5 Security | EMS E5 | Entra P2 standalone]

Break glass accounts:
  breakglass01@yourtenant.onmicrosoft.com: Global Administrator (permanent active) - correct
  breakglass02@yourtenant.onmicrosoft.com: Global Administrator (permanent active) - correct

Tier-0 role settings:
  Global Administrator: activation 4h, MFA required, approval required, justification required - PASS
  Privileged Role Administrator: [same] - PASS
  Privileged Authentication Administrator: [same] - PASS

Tier-1 role settings:
  Exchange Administrator: activation 8h, MFA required, no approval - PASS
  [other tier-1 roles]

Admin account assignments:
  admin-jane.admin@contoso.com: [role list, all eligible, no permanent active (excluding break glass pattern)]

Permanent active assignments (excluding break glass):
  [should be empty]

Access reviews:
  Tier-0 quarterly review: scheduled, next review starts [date]
  Tier-1 semi-annual review: scheduled, next review starts [date]
  Tier-2 semi-annual review: scheduled, next review starts [date]

Notifications:
  Tier-0 alerts routing to: tier-zero-alerts@contoso.com
  General PIM alerts routing to: pim-alerts@contoso.com
```

### Functional verification

1. **Break glass still works without PIM.** Sign in as a break glass account, confirm permanent active Global Administrator is immediately usable without PIM activation.
2. **Admin account requires PIM activation.** Sign in as an admin account, attempt a privileged action (for example, open the Entra portal's user management and attempt to create a user). Expected: action fails with insufficient permissions because the admin account is not currently activated.
3. **Activation workflow completes.** Activate the required role through PIM, complete MFA, enter justification, observe approval flow (for tier 0) or immediate activation (for tier 1/2), then confirm the privileged action now succeeds.
4. **Deactivation occurs at end of window.** Wait for the activation window to expire, attempt the privileged action again, confirm it fails because the role is no longer active.
5. **Notifications fire.** Confirm that the tier-0 alert distribution received notifications during the tier-0 activation test.

## Additional controls (add-on variants)

This runbook is variant-specific: it applies only to tenants with Entra ID P2. No further add-on sections apply.

## What to watch after deployment

* **Administrator friction during the first week.** New activation workflow adds 30 to 90 seconds per privileged session. Administrators who were accustomed to always-on access sometimes express frustration; the frustration fades within 2 to 4 weeks as the pattern becomes reflexive.
* **Missing approvers on tier-0 activations.** Tier-0 activations require approval from another tier-0 administrator. If the organization has only two tier-0 admins and one requests activation, the other must be available. For solo-admin scenarios or small teams, this is occasionally operationally awkward. Options: add a third tier-0 admin, route approval to a specific security-focused role (such as an MSP-provided security admin), or accept the pattern. Do not remove the approval requirement; the requirement is what makes tier-0 activation meaningfully different from tier-1.
* **Emergency approval through break glass.** In genuine emergencies where approval cannot be obtained in reasonable time, the break glass accounts provide the path. Using break glass for a PIM-approval workaround is correct per the break glass design, but every such use is a documented incident that warrants review; the alert configured for break glass sign-in (Runbook 01) fires.
* **PIM activation rates by administrator.** Observed via the PIM audit log. Administrators who activate tier-0 roles many times per day may be doing routine work that should be handled by tier-1 or tier-2 roles. Review and re-tier as appropriate.
* **Stale eligible assignments.** Access reviews catch this. Administrators who no longer need a role but still hold eligibility will have their eligibility removed at the next review unless the reviewer explicitly retains it. Tenants without Access Reviews licensed need manual quarterly review.

## Rollback

Rollback from PIM to permanent active assignments is operationally straightforward but strategically a regression. The correct response to PIM-related operational issues is usually to adjust the PIM configuration rather than revert:

* Activation window too short: extend the maximum activation duration for the specific tier
* Too many approvers needed: reduce the approval requirement from all tier-0 to any tier-0 (already the configured state) or reassess whether the specific role requires tier-0
* Activation workflow too cumbersome: review whether the administrator's activity pattern can be handled by a lower tier

To convert a specific eligible assignment back to permanent active (rare, requires explicit justification):

```powershell
./04-Revert-ToPermanent.ps1 -UserUPN "admin-jane.admin@contoso.com" -Role "SpecificRole" -Justification "Documented exception reason"
```

## References

* Microsoft Learn: [What is Microsoft Entra Privileged Identity Management?](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-configure)
* Microsoft Learn: [Configure Microsoft Entra role settings in Privileged Identity Management](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)
* Microsoft Learn: [Create an access review of Microsoft Entra roles in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-create-roles-and-resource-roles-review)
* M365 Hardening Playbook: [Permanent Global Administrator assignments (PIM not in use)](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/permanent-global-admin-assignments.md)
* M365 Hardening Playbook: [Application Administrator and Cloud Application Administrator treated as lower tier than Global Administrator](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/app-admin-cloud-app-admin-tier-zero.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Section 1.1 (Privileged access management)
* NIST CSF 2.0: PR.AA-01, PR.AA-05, DE.CM-03
