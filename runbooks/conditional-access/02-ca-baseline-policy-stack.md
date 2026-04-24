# 02 - Conditional Access Baseline Policy Stack

**Category:** Conditional Access
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:** [01 - Tenant Initial Configuration and Break Glass Accounts](../identity-and-access/01-tenant-initial-and-break-glass.md) completed
**Time to deploy:** 60 minutes active work, plus 14 days of report-only observation before enforcement
**Deployment risk:** Medium. Policies deploy in report-only first, which is safe. Enforcement produces user-visible changes; communication is required.

## Purpose

This runbook deploys the Conditional Access policy stack that defines the tenant's core identity enforcement: MFA for all users, block legacy authentication, MFA for admins, MFA for device registration, and block sign-ins from unexpected countries. The stack replaces Security Defaults as the enforcement mechanism and provides the foundation that every subsequent runbook builds on.

The tenant before this runbook: running Security Defaults or with ad-hoc Conditional Access policies in varying states. The tenant after: a consistent, documented, and auditable set of Conditional Access policies producing deterministic enforcement behavior. Security Defaults is disabled.

The stack is deployed in two phases. Phase 1 deploys seven baseline policies in report-only mode and leaves Security Defaults enabled; this is safe and additive. Phase 2, after 14 days of observation, disables Security Defaults and switches the policies from report-only to on. The two-phase approach is why this runbook is Medium risk rather than High risk: report-only observation catches problems before enforcement.

## Prerequisites

* Break glass accounts exist and have been tested (runbook 01 complete)
* `CA-Exclude-BreakGlass` group exists and contains both break glass accounts
* Deploying technician has Global Administrator or Conditional Access Administrator
* Tenant has Entra ID P1 licensing (confirmed by Business Premium, E3, or E5 SKU)
* For tenants moving from existing ad-hoc Conditional Access: review and export existing policies before running this runbook; the baseline stack is designed to replace, not supplement, ad-hoc configurations

## Target configuration

Seven Conditional Access policies deployed and enabled. The universal stack applies to all variants:

| Policy | Purpose | Grant |
|---|---|---|
| CA001 - Require MFA for all users | Baseline MFA enforcement | Require MFA |
| CA002 - Block legacy authentication | Prevent protocols that bypass MFA | Block |
| CA003 - Require MFA for admins | Stronger MFA for directory roles | Require authentication strength (phishing-resistant preferred) |
| CA004 - Require MFA for Azure management | Protect admin portal access | Require MFA |
| CA005 - Require MFA for device registration | Prevent attacker-registered devices | Require MFA |
| CA006 - Block sign-ins from unexpected countries | Geographic filter | Block |
| CA007 - Require compliant or hybrid joined device for M365 | Device compliance enforcement | Require compliant device OR hybrid join |

For add-on variants, three additional policies (detailed in the Additional Controls section):

| Policy | Purpose | Applies to |
|---|---|---|
| CA010 - Sign-in risk policy | Identity Protection enforcement | Defender Suite, E5 Security, EMS E5 |
| CA011 - User risk policy | Identity Protection enforcement | Defender Suite, E5 Security, EMS E5 |
| CA012 - Admin portal authentication context | Step-up MFA for admin actions | Defender Suite, E5 Security, EMS E5 |

All policies exclude the `CA-Exclude-BreakGlass` group.

CA006 requires the organization to specify which countries are allowed; the default in the automation artifact covers only the United States and requires customization before deployment in tenants operating elsewhere or internationally. This is the primary modular element of the stack.

CA007 requires Intune device compliance policies to be in place for the Intune-enrolled devices in the tenant. If device compliance policies are not yet deployed (covered in the device compliance runbooks), CA007 should be deployed later in the sequence rather than as part of this runbook.

## Deployment procedure

### Step 1: Review and export any existing Conditional Access policies

If the tenant has existing Conditional Access policies, preserve them for reference before deploying the baseline stack:

```powershell
./02a-Export-ExistingCA.ps1 -OutputPath "./ca-backup-$(Get-Date -Format 'yyyyMMdd').json"
```

The script exports all existing Conditional Access policies to JSON for archival. Existing policies are not deleted or modified by this runbook; the baseline stack is deployed alongside them. After the baseline is enforced and verified working, existing ad-hoc policies should be reviewed and either retired (if superseded by the baseline) or adjusted (if complementary to the baseline). That review is a judgment call and is not automated.

Verification: the JSON file exists and contains the expected policy count. Preserve this file with the operations documentation.

### Step 2: Customize the country list in CA006

The default CA006 policy allows sign-ins only from the United States. For tenants operating elsewhere or internationally:

```powershell
# Edit the allowed countries list in the CA006 configuration
cd automation/ca-policies
# Open 02-ca006-country-block.json
# Modify the "countriesAndRegions" array in the named location definition
# Save
```

Country codes are two-letter ISO codes (`US`, `CA`, `GB`, `MX`, etc.). Include every country where the organization has users, offices, or sanctioned travel. Err toward inclusion; it is easier to tighten later than to unblock a traveling executive during enforcement.

Verification: the JSON file contains the correct country list for the organization.

### Step 3: Deploy the baseline stack in report-only mode

```powershell
./02-Deploy-CABaseline.ps1 `
    -Mode "ReportOnly" `
    -BreakGlassExcludeGroup "CA-Exclude-BreakGlass" `
    -Variant "Auto"
```

The script:

1. Reads the tenant's licensing via `Get-MgSubscribedSku` and determines which variant applies
2. Creates the named location referenced by CA006 using the country list from Step 2
3. Imports the seven universal policies from the JSON files in `automation/ca-policies/`
4. If the variant is Defender Suite, E5 Security, or EMS E5, imports the three additional P2 policies
5. Sets all deployed policies to "enabledForReportingButNotEnforced" (report-only)
6. Outputs a summary of deployed policies and their state

Verification: the script reports the policies deployed. Confirm in the portal that the policies exist under **Entra admin center > Protection > Conditional Access > Policies** and that each shows **Report-only** state.

### Step 4: Wait and observe

The observation period is 14 days at minimum. During observation, monitor the policies' evaluation against real sign-ins:

```powershell
./02b-Monitor-CABaseline.ps1 -LookbackDays 14
```

The monitoring script queries the sign-in logs for the last 14 days and produces a per-policy summary:

* Total sign-ins evaluated
* `reportOnlyFailure` count (sign-ins that would have been blocked or challenged if the policy were enforced)
* Distinct users affected
* Applications involved
* Source locations

Review the output weekly. Pay attention to:

* **CA002 (block legacy auth) reportOnlyFailures:** every failure is a legacy authentication attempt that needs resolution. Most are service accounts or multifunction printers that require migration to modern authentication; some are attack attempts that will be correctly blocked after enforcement. Identify the legitimate cases and remediate them (see the [playbook finding on legacy authentication](https://github.com/pslorenz/m365-hardening-playbook/blob/main/identity-foundation/legacy-authentication-allowed.md)) before enforcement.
* **CA006 (country block) reportOnlyFailures:** every failure is a sign-in from a country not on the allow list. Legitimate traveling users need either the country added to the list or an exception through the temporary-exclusion workflow (covered in a later runbook).
* **CA007 (compliant device) reportOnlyFailures:** every failure is a device not currently compliant or not enrolled. Complete the device compliance runbooks before enforcing CA007.
* **CA005 (device registration MFA) reportOnlyFailures:** rare; typically indicates a user registering a device without having completed MFA registration. The remediation is usually to ensure MFA registration is completed at the user's first sign-in.

Extend the observation period if the tenant has monthly processes (payroll exports, end-of-month batch jobs, quarterly vendor integrations) that might produce legacy auth or service account patterns that do not appear in a 14-day window.

### Step 5: Resolve pre-enforcement findings

For each finding identified in Step 4, resolve before proceeding to enforcement:

* Migrate service accounts to application-registration authentication with certificate credentials
* Migrate multifunction printers to SMTP relay connectors
* Add legitimate countries to the CA006 allow list
* Complete device enrollment for users who should retain access
* Complete MFA registration for users who have not yet registered

Some findings may not be fully resolvable in the observation window (replacing a printer takes more than two weeks in most environments). For these, document the exception, determine whether to proceed with enforcement and accept the residual breakage, or extend the observation window. The decision is organization-specific.

### Step 6: Disable Security Defaults

This is the highest-risk single step in the runbook. Security Defaults is the baseline identity enforcement while the Conditional Access policies are in report-only. Disabling Security Defaults without the Conditional Access stack enforcing leaves the tenant unprotected. This step must occur immediately before Step 7; do not disable Security Defaults and then leave the tenant overnight without enforcing the Conditional Access stack.

```powershell
./02c-Disable-SecurityDefaults.ps1
```

The script prompts for confirmation, then disables Security Defaults. It does not proceed automatically; the operator must confirm.

Verification: in the portal, **Entra admin center > Identity > Overview > Properties > Manage security defaults** shows disabled.

### Step 7: Switch the baseline stack from report-only to on

Immediately after Step 6:

```powershell
./02d-Enforce-CABaseline.ps1
```

The script switches each policy from `enabledForReportingButNotEnforced` to `enabled`. The change takes effect immediately; the next sign-in by each user evaluates against the enforced policies.

Verification: the portal shows each CA policy as On. A test sign-in by a non-break-glass account completes with MFA prompted as expected.

### Step 8: Verify the enforcement and test break glass access

Complete the verification detailed in the Verification section. Confirm, specifically, that break glass accounts continue to sign in without any Conditional Access policy applying to them. If any break glass exclusion did not take effect, correct it immediately (before the break glass account is needed in an emergency).

### Step 9: Communicate to users

If not already done as part of change management, send the user-facing notification about the MFA enforcement. Include:

* What changed (MFA is now required on more sign-ins; previously permitted bypasses like trusted networks no longer apply)
* What users should expect (occasional additional MFA prompts, particularly at the start of the workday)
* How to complete first-time MFA registration if not already done (with a link to the Microsoft user-facing documentation)
* Who to contact for help (the help desk, specifically naming the channel)

Communication prevents the initial wave of help desk tickets that inevitably accompanies MFA enforcement rollouts.

## Automation artifacts

* `automation/powershell/02-Deploy-CABaseline.ps1` - Deploys the baseline CA stack in report-only mode
* `automation/powershell/02a-Export-ExistingCA.ps1` - Exports existing CA policies for archival
* `automation/powershell/02b-Monitor-CABaseline.ps1` - Reports on CA policy evaluation during observation
* `automation/powershell/02c-Disable-SecurityDefaults.ps1` - Disables Security Defaults (with confirmation)
* `automation/powershell/02d-Enforce-CABaseline.ps1` - Switches CA policies from report-only to on
* `automation/ca-policies/02-ca001-mfa-all-users.json` through `02-ca012-admin-auth-context.json` - Policy definitions

## Verification

### Configuration verification

```powershell
./02-Verify-Deployment.ps1
```

Expected output includes:

```
Baseline CA Policies (Universal):
  CA001 - Require MFA for all users: Enabled, Excludes CA-Exclude-BreakGlass
  CA002 - Block legacy authentication: Enabled, Excludes CA-Exclude-BreakGlass
  CA003 - Require MFA for admins: Enabled, Excludes CA-Exclude-BreakGlass
  CA004 - Require MFA for Azure management: Enabled, Excludes CA-Exclude-BreakGlass
  CA005 - Require MFA for device registration: Enabled, Excludes CA-Exclude-BreakGlass
  CA006 - Block sign-ins from unexpected countries: Enabled, Excludes CA-Exclude-BreakGlass
  CA007 - Require compliant or hybrid joined device: [Enabled if Intune compliance deployed, otherwise Report-only]

Security Defaults: Disabled

Tenant Variant: [Plain BP | Defender Suite | E5 Security | EMS E5]

Add-on Policies (if applicable):
  CA010 - Sign-in risk policy: Enabled
  CA011 - User risk policy: Enabled
  CA012 - Admin portal authentication context: Enabled
```

### Functional verification

Test the enforcement end-to-end:

1. **MFA for standard user.** Sign in as a test user account in a fresh browser window. Expected: MFA prompt, then successful sign-in.
2. **Legacy auth block.** From a machine outside the tenant's managed environment, attempt an IMAP sign-in with a valid user's credentials. Expected: authentication fails with `ResultType: 53003` (Access blocked by Conditional Access).
3. **Break glass access.** Sign in with one of the break glass accounts. Expected: successful sign-in with no MFA prompt, no Conditional Access evaluation.
4. **Country block.** If feasible, use a VPN exit in a blocked country to attempt a sign-in. Expected: blocked with a Conditional Access error. (If VPN testing is not feasible, rely on the Conditional Access What If tool with a simulated IP address.)
5. **Device registration.** Register a test device in the tenant. Expected: MFA is prompted during registration.

Any failure in the functional verification indicates a deployment or policy configuration issue that must be resolved before considering the runbook complete.

## Additional controls (add-on variants)

### Additional controls with Defender Suite, E5 Security, or EMS E5 (Entra ID P2)

The three additional policies deployed by the automation script for P2-licensed tenants:

**CA010 - Sign-in risk policy.** Requires MFA on any sign-in flagged as medium or high risk by Identity Protection. Target population: All users, excludes break glass. The policy catches AiTM token replay, credential stuffing from anonymous IPs, impossible-travel patterns, and other Identity Protection detections. Without this policy, risk is detected and reported but not acted on.

**CA011 - User risk policy.** Requires password change with MFA on any account flagged as high user risk. Target population: All users, excludes break glass. The policy handles accounts with leaked credentials or aggregated compromise signals. Requires self-service password reset to be deployed in the tenant for users to complete the required change.

**CA012 - Admin portal authentication context.** Requires authentication context (typically phishing-resistant MFA) for access to Microsoft admin portals. Target population: Users with any admin role, excludes break glass. The policy complements CA003 by requiring stronger authentication specifically for administrative actions, not just admin sign-ins. The authentication context definition is deployed as a separate resource; the CA policy references it.

For tenants without P2, these three policies are not deployed. The sign-in risk and user risk detections are still visible in the Identity Protection dashboard (the reports-only capability is P1-accessible), but no automated enforcement applies. The organization would need to manually review risk detections and remediate, which in practice does not happen at scale.

### Additional controls with Defender Suite or E5 Security (not this runbook)

Defender for Office 365 Plan 2 controls are deployed in the Defender for Office 365 runbook, not in this Conditional Access runbook. Similarly, Defender for Endpoint Plan 2 controls are deployed in the device compliance runbook.

## What to watch after deployment

* **Sign-in failure rate spike in the first 72 hours.** Expected. Users with long-running sessions authenticate fresh after the enforcement, and the mix of legitimate MFA prompts produces a visible bump in the sign-in logs. Returns to baseline within a week.
* **Help desk tickets about "I can't sign in."** Expected. The most common issues are users on old devices that do not support modern authentication, users who had been bypassing MFA through legacy protocols, and users who have not completed MFA registration. Triage each; a documented knowledge-base article covering the common patterns reduces ticket volume over time.
* **Continued legacy authentication attempts.** Expected for 7 to 14 days as clients that were caching legacy-auth session material retry and fail. After two weeks, persistent legacy auth attempts indicate clients that have not migrated; investigate individually.
* **False positive country blocks on traveling users.** Expected. The travel exception workflow (covered in a later runbook) handles legitimate travel; the observation in this step identifies users who need the exception.
* **Risk-based policy evaluations (for P2 variants).** Initial enforcement produces occasional risk-flagged sign-ins; most are legitimate users in new locations. Identity Protection's model learns the user's pattern and false-positive rates decrease over 30 to 60 days.

## Rollback

Rollback of the full baseline stack returns the tenant to Security Defaults, which is a regression. Specific-policy rollback is appropriate for narrow issues:

**Single policy producing unexpected breakage.** Disable that policy only:

```powershell
./02e-Disable-CAPolicy.ps1 -PolicyName "CA002 - Block legacy authentication" -Reason "Incident: [description]"
```

The script disables the specified policy and logs the reason. Re-enable after the underlying issue is resolved. This is the correct response to 95% of post-enforcement issues.

**Full stack rollback.** If the entire enforcement produces unmanageable issues (very rare if the observation period was thorough):

```powershell
./02f-Full-Rollback.ps1
```

The script disables all baseline Conditional Access policies and re-enables Security Defaults. Use break glass accounts if normal admin authentication is blocked. Document the rollback and reason; re-deployment must address the underlying issues identified during the failed deployment.

## References

* Microsoft Learn: [Plan a Conditional Access deployment](https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access)
* Microsoft Learn: [Conditional Access templates](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common)
* Microsoft Learn: [Authentication context](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-cloud-apps#authentication-context)
* M365 Hardening Playbook: [Security Defaults still enabled despite Entra ID P1 or P2 licensing](https://github.com/pslorenz/m365-hardening-playbook/blob/main/identity-foundation/security-defaults-left-enabled.md)
* M365 Hardening Playbook: [Legacy authentication still allowed](https://github.com/pslorenz/m365-hardening-playbook/blob/main/identity-foundation/legacy-authentication-allowed.md)
* M365 Hardening Playbook: [MFA policy excludes a trusted network named location](https://github.com/pslorenz/m365-hardening-playbook/blob/main/conditional-access/mfa-policy-excludes-trusted-network.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Section 1 (Entra ID) - Conditional Access
* NIST CSF 2.0: PR.AA-01, PR.AA-03, PR.AA-05
