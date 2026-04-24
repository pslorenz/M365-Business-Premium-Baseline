# 06 - Authentication Context for Admin Portals (P2)

**Category:** Conditional Access
**Applies to:** Defender Suite, E5 Security, EMS E5 (Entra ID P2 required)
**Not applicable to:** Plain Business Premium (authentication context is a P2 feature)
**Prerequisites:**
* [02 - Conditional Access Baseline Policy Stack](./02-ca-baseline-policy-stack.md) completed and enforced
* [03 - Admin Account Separation and Tier Model](../identity-and-access/03-admin-account-separation.md) completed
* [04 - PIM Configuration](../identity-and-access/04-pim-configuration.md) completed
* Phishing-resistant MFA method registered for at least one administrator (FIDO2 security key, Windows Hello for Business, or certificate-based authentication)
**Time to deploy:** 45 minutes active work plus 7-day observation
**Deployment risk:** Medium. Step-up authentication may produce friction if administrators do not have phishing-resistant MFA methods registered.

## Purpose

Authentication context is an Entra ID P2 feature that lets Conditional Access policies require step-up authentication for specific operations rather than for the entire sign-in session. Without authentication context, a Conditional Access policy enforcing phishing-resistant MFA either applies to all admin sign-ins (high friction, disrupts routine tasks) or applies to none (low friction, weak posture for the specific high-value operations that warrant stronger authentication).

With authentication context, administrators sign in with their normal MFA, work through routine admin tasks, and are prompted for phishing-resistant authentication only when they attempt a specific high-sensitivity action that the authentication context is bound to. Microsoft admin portals, PIM activation, and specific sensitive Graph API operations can all be gated by authentication context.

The tenant before this runbook: Runbook 02 deployed CA012 (admin portal authentication context) in report-only mode as part of the baseline P2 policy set. The authentication context resource itself was created by the deployment script but is not yet bound to any operation. Administrators complete standard MFA on admin sign-ins but have no step-up requirement for sensitive actions.

The tenant after: the `c1` authentication context is bound to the Microsoft Entra admin center, the Microsoft 365 admin center, and PIM role activation. CA012 is enforced. An administrator signing in to perform routine tier-1 tasks completes standard MFA. An administrator attempting to modify Conditional Access policies, activate a tier-0 role through PIM, or perform other bound actions is prompted for phishing-resistant authentication at that specific action.

The combination of CA012 (the policy) and authentication context binding (the scope) is what produces selective step-up authentication. Neither half works alone; the policy without binding catches nothing because no action triggers it, and the binding without the policy catches nothing because no policy evaluates the context claim.

## Prerequisites

* Tenant has Entra ID P2 (Defender Suite, E5 Security, EMS E5, or Entra ID P2 standalone)
* CA012 exists in the tenant (deployed by Runbook 02 in report-only mode)
* At least one administrator has registered a phishing-resistant MFA method (FIDO2 security key or Windows Hello for Business); additional administrators will register during rollout
* Break glass accounts have their standard MFA-exempt pattern; authentication context does not apply to break glass because they are excluded from CA012

## Target configuration

At completion:

* Authentication context `c1` exists with display name "Admin portal step-up" and the description from the CA012 deployment
* CA012 is enabled (not report-only) and enforcing the authentication context requirement
* The authentication context is bound to:
    * Microsoft Entra admin center
    * Microsoft 365 admin center
    * PIM role activation for tier-0 roles (Global Administrator, Privileged Role Administrator, Privileged Authentication Administrator)
* Administrators in tier-0 or tier-1 groups have registered at least one phishing-resistant MFA method
* An authentication strength named "Phishing-resistant MFA" exists and is referenced by CA012's grant control

## Deployment procedure

### Step 1: Confirm the authentication context and authentication strength exist

The Runbook 02 deployment script created these as part of CA012. Verify:

```powershell
./06-Verify-Prerequisites.ps1
```

Expected output:

```
Authentication context c1:
  Exists: Yes
  Display name: Admin portal step-up
  Available: True

Authentication strength "Phishing-resistant MFA":
  Exists: Yes
  Allowed combinations: windowsHelloForBusiness, fido2, x509CertificateMultiFactor

CA012 policy:
  Exists: Yes
  State: enabledForReportingButNotEnforced (will be enforced in this runbook)
  References authentication context c1: Yes
```

If any prerequisite is missing, run the relevant portions of Runbook 02 before proceeding.

### Step 2: Verify administrator MFA registration

Check that administrators have phishing-resistant methods:

```powershell
./06-Check-AdminMFA.ps1
```

The script enumerates users in `RoleAssignable-Tier0` and `RoleAssignable-Tier1` and reports each admin's registered authentication methods. Expected output flags:

* Administrators with no phishing-resistant method registered
* Administrators with only one phishing-resistant method (recommendation: register at least two)
* Administrators whose methods are password-based or SMS (not phishing-resistant)

For each administrator without a phishing-resistant method, coordinate registration before enabling the step-up requirement. Options:

* **FIDO2 security key.** Most operationally reliable. Distribute keys (YubiKey, Feitian, or similar) to administrators, have them register through https://mysecurityinfo.microsoft.com.
* **Windows Hello for Business.** Works for administrators using Windows 11 devices with TPM 2.0. Registration is typically automatic during Windows sign-in setup.
* **Certificate-based authentication.** More involved setup; appropriate for organizations with existing PKI.
* **Microsoft Authenticator with passkey.** Supported in current Authenticator versions; registration is straightforward.

Do not proceed with enforcement until every administrator with tier-0 or tier-1 eligibility has at least one phishing-resistant method registered. An administrator without a phishing-resistant method will be unable to complete the step-up challenge and will be blocked from the bound operations.

### Step 3: Bind the authentication context to Entra admin center

The binding makes the authentication context apply to specific actions within the admin portal. Without binding, the context is defined but unused; CA012 evaluates nothing.

Authentication context binding happens within the Entra admin center itself:

1. Navigate to **Entra admin center > Identity governance > Conditional Access > Authentication contexts**
2. Select the `Admin portal step-up` context
3. Note the context ID (`c1`) for reference
4. Navigate to **Entra admin center > Identity governance > Privileged Identity Management > Microsoft Entra roles > Settings**

For each tier-0 role, configure PIM activation to require the authentication context:

```powershell
./06-Bind-AuthContextToPIM.ps1 -Role "Global Administrator"
./06-Bind-AuthContextToPIM.ps1 -Role "Privileged Role Administrator"
./06-Bind-AuthContextToPIM.ps1 -Role "Privileged Authentication Administrator"
```

The script modifies the PIM role setting to require authentication context `c1` on activation. An administrator activating one of these roles through PIM is prompted for phishing-resistant MFA at the activation step, in addition to the justification and (for tier 0) approval that were configured in Runbook 04.

### Step 4: Observe in report-only for 7 days

CA012 is currently in report-only mode. Observe sign-in evaluation to confirm:

```powershell
./06-Monitor-AuthContext.ps1 -LookbackDays 7
```

The script reports:
* Admin sign-ins that would have been challenged by CA012 enforcement
* Administrators who would have hit the policy successfully (have phishing-resistant methods)
* Administrators who would have been blocked (no phishing-resistant method)

Review the output. Any administrator in the second category must register a phishing-resistant method before Step 5.

### Step 5: Enforce CA012

```powershell
./06-Enforce-CA012.ps1
```

The script switches CA012 from report-only to enabled. Effective immediately, administrators attempting bound actions are prompted for phishing-resistant authentication.

### Step 6: Test the end-to-end flow

Test with one administrator:

1. Administrator signs in to Entra admin center with admin account and standard MFA
2. Administrator navigates to **Conditional Access > Policies**
3. Expected: no additional prompt (viewing policies does not trigger authentication context)
4. Administrator clicks a policy to edit
5. Expected: authentication context challenge; administrator must complete phishing-resistant MFA (FIDO2 tap, Windows Hello, etc.)
6. After successful step-up, administrator can edit the policy for the duration of the session
7. Administrator navigates to PIM, activates a tier-0 role
8. Expected: authentication context challenge again if the session has aged or is a fresh sign-in; otherwise the elevated context carries across to PIM activation

Document the test results. If the step-up challenge does not appear for bound actions, the binding is not correctly applied; re-run Steps 3 and 4.

### Step 7: Communicate to administrators

Brief message to administrators who will encounter the new prompt:

* What changed: specific high-value admin actions now require a phishing-resistant MFA step-up
* When it triggers: opening or modifying Conditional Access policies, activating tier-0 roles through PIM, accessing specific admin portals
* What to expect: a browser prompt asking for FIDO2 key tap, Windows Hello PIN/biometric, or certificate-based authentication (depending on the administrator's registered methods)
* What to do if the prompt fails: confirm the phishing-resistant method is registered at https://mysecurityinfo.microsoft.com; if registration is missing or broken, contact IT

Most administrators complete the step-up successfully on first encounter. The friction is 2 to 5 seconds per event, which is acceptable for the security benefit.

### Step 8: Update operations runbook

Document the authentication context configuration:

* Context `c1` exists with the "Admin portal step-up" display name
* CA012 is enforced and requires phishing-resistant MFA for bound operations
* Which operations trigger the step-up (Entra admin portal actions, PIM tier-0 activation, etc.)
* Which administrators have phishing-resistant methods registered and which methods
* Annual review to confirm that new administrators complete phishing-resistant registration during onboarding

## Automation artifacts

* `automation/powershell/06-Verify-Prerequisites.ps1` - Confirms the CA012 baseline deployed by Runbook 02 is in place
* `automation/powershell/06-Check-AdminMFA.ps1` - Reports phishing-resistant method registration for tier-0 and tier-1 administrators
* `automation/powershell/06-Bind-AuthContextToPIM.ps1` - Binds authentication context to PIM role activation
* `automation/powershell/06-Monitor-AuthContext.ps1` - Reports authentication context evaluation in report-only mode
* `automation/powershell/06-Enforce-CA012.ps1` - Switches CA012 from report-only to enabled
* `automation/powershell/06-Verify-Deployment.ps1` - Confirms the runbook's target state

## Verification

### Configuration verification

```powershell
./06-Verify-Deployment.ps1
```

Expected output:

```
Authentication context c1:
  Display name: Admin portal step-up
  Available: True
  Bindings:
    PIM Global Administrator activation: Bound
    PIM Privileged Role Administrator activation: Bound
    PIM Privileged Authentication Administrator activation: Bound

CA012 policy:
  State: enabled
  Grant: authentication strength "Phishing-resistant MFA"

Tier-0 administrator phishing-resistant MFA registration:
  admin-jane.admin@contoso.com: FIDO2 registered (PASS)
  admin-bob.admin@contoso.com: WindowsHelloForBusiness registered (PASS)
  [others]

Tier-1 administrator phishing-resistant MFA registration:
  [similar]
```

### Functional verification

1. **Bound action triggers step-up.** As an admin account, attempt to modify a Conditional Access policy. Expected: phishing-resistant MFA challenge before the modification proceeds.
2. **Unbound action does not trigger step-up.** As an admin account, view a list of users. Expected: no additional challenge beyond the initial sign-in MFA.
3. **Phishing-resistant method completes the challenge.** When the challenge appears, completing FIDO2, Windows Hello, or certificate authentication succeeds and the action proceeds.
4. **Break glass accounts bypass the requirement.** Sign in as a break glass account, attempt a bound action. Expected: action proceeds without the step-up challenge (break glass is excluded from CA012).

## What to watch after deployment

* **Administrators without phishing-resistant methods.** Anyone in a tier group who has not registered a method will be blocked from bound operations. Check-Admin-MFA.ps1 should run weekly and alert on any gaps.
* **New administrators onboarded.** Authentication context enforcement applies immediately to new admin accounts added to tier groups. Onboarding must include phishing-resistant registration.
* **Step-up prompts during emergency response.** If an incident requires rapid administrative action and the responder does not have a phishing-resistant method available (lost FIDO2 key, damaged device), the break glass accounts are the path. Document this in the incident response runbook.
* **Browser compatibility.** Phishing-resistant methods require specific browser support. Chromium-based browsers (Chrome, Edge, Brave) support FIDO2 and Windows Hello. Safari on macOS has partial support. Firefox has some gaps. Document recommended browsers for administrators.

## Rollback

Disable CA012:

```powershell
./06-Disable-CA012.ps1 -Reason "Documented reason for rollback"
```

The script disables CA012 but preserves the authentication context binding. An administrator reconnecting a FIDO2 key or completing Windows Hello registration can re-enable CA012 without reconfiguring the context bindings.

Full rollback (disable CA012 and unbind the authentication context from PIM) is rarely the right answer. The typical rollback scenario is a specific administrator having trouble with their phishing-resistant method during a critical window; disabling CA012 temporarily lets them work through the incident, then reactivation after the method is fixed.

## References

* Microsoft Learn: [Authentication context in Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-cloud-apps#authentication-context)
* Microsoft Learn: [Conditional Access authentication strengths](https://learn.microsoft.com/en-us/entra/identity/authentication/concept-authentication-strengths)
* Microsoft Learn: [Enable passkeys (FIDO2) for your organization](https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-enable-passkey-fido2)
* Microsoft Learn: [Configure PIM to require authentication context](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)
* M365 Hardening Playbook: [Permanent Global Administrator assignments (PIM not in use)](https://github.com/pslorenz/m365-hardening-playbook/blob/main/privileged-access/permanent-global-admin-assignments.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Phishing-resistant authentication recommendations
* NIST CSF 2.0: PR.AA-01, PR.AA-02, PR.AA-03
