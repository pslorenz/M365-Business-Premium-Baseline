# 08 - Windows Device Compliance Policy

**Category:** Device Compliance
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [07 - Intune Enrollment Strategy](./07-intune-enrollment-strategy.md) completed with Windows auto-enrollment configured
**Time to deploy:** 90 minutes active work, plus 14 days of observation before enforcement via CA007
**Deployment risk:** Medium. Compliance policy deployment is additive (does not change device state), but CA007 enforcement blocks access for devices that fail compliance.

## Purpose

This runbook deploys the Windows device compliance policy that every subsequent access-control decision depends on. The policy defines what "compliant" means for a Windows device in this tenant: BitLocker encryption, Secure Boot, Code Integrity, minimum OS version, firewall enabled, antivirus active, compliant password, and (where supported) TPM 2.0 presence. Runbook 02's CA007 policy requires compliant devices for Microsoft 365 access; without an actual compliance policy defining what compliance means, CA007 either passes everything (if no policy assigned) or blocks everything (if a placeholder policy is in place).

The tenant before this runbook: Windows devices enroll in Intune (via Runbook 07) and appear in the device inventory with compliance state "unknown" or "compliant by default" (Microsoft's default before a specific policy applies). CA007 in report-only mode shows these devices as passing because there is no policy requirement to fail against.

The tenant after: an assigned Windows compliance policy evaluates every enrolled Windows device against concrete criteria. Devices that meet the criteria are compliant; devices that do not are non-compliant with specific named failures visible in Intune. CA007 can be enforced and produces meaningful access decisions based on actual device posture, not just enrollment status.

The policy settings here pair with the attack surface each control addresses. BitLocker encryption protects data at rest if a device is stolen. Secure Boot and Code Integrity (HVCI) prevent bootkit and rootkit compromise of the boot sequence. Minimum OS version keeps devices on supported Windows versions that receive security updates. Firewall and antivirus requirements ensure basic endpoint protection is active. Password compliance enforces that users actually authenticate to the device rather than bypassing the lock screen. TPM presence (where supported) is the hardware foundation for all of the above.

## Prerequisites

* Intune enrollment is configured (Runbook 07 complete)
* At least one Windows device is enrolled for initial validation
* Defender for Endpoint onboarding is either complete or understood as a follow-on dependency; this runbook works with Windows Defender (the built-in antivirus) and does not require Defender for Endpoint
* BitLocker recovery key storage is configured in Entra ID (default for new tenants; verify for older tenants)
* Organizational position on password complexity is documented (minimum length, complexity requirements, history)

## Target configuration

At completion:

* **Primary Windows compliance policy** deployed with the settings below
* **Policy assigned** to all Windows devices (or the appropriate group encompassing the Windows fleet)
* **Device compliance actions** configured: notify user at 3 days non-compliant, mark non-compliant at 7 days non-compliant, notify admin at 14 days non-compliant
* **Grace period** of 24 hours for newly-enrolled devices to reach compliant state before being reported non-compliant

Policy settings:

| Category | Setting | Value |
|---|---|---|
| Device Health | Require BitLocker | Require |
| Device Health | Require Secure Boot | Require |
| Device Health | Require code integrity | Require |
| Device Properties | Minimum OS version | 10.0.19045 (Windows 10 22H2) or 10.0.22631 (Windows 11 23H2) |
| Device Properties | Maximum OS version | Not configured |
| System Security | Require password | Require |
| System Security | Minimum password length | 12 characters |
| System Security | Simple passwords | Block |
| System Security | Password expiration | 365 days (or Not configured) |
| System Security | Number of previous passwords | 5 |
| System Security | Require password to unlock device from idle | Require |
| System Security | Maximum minutes of inactivity | 15 |
| System Security | Require encryption of data storage | Require |
| System Security | Firewall enabled | Require |
| System Security | Antivirus | Require |
| System Security | Antispyware | Require |
| System Security | Real-time protection | Require |
| System Security | Signature must be up-to-date | Require |
| Defender | Microsoft Defender Antimalware | Require |
| Defender | Defender version | Not configured (Intune tracks automatically) |
| Defender | Signatures up-to-date | Require |
| Defender | Real-time protection | Require |

The minimum OS version setting deserves specific attention. Windows 10 support ended October 2025; any device still running Windows 10 should be migrated to Windows 11 or replaced. Setting minimum to Windows 10 22H2 provides a grace period for in-flight migrations; tightening to Windows 11 as the minimum forces the migration. For most SMB tenants, the correct current setting is Windows 10 22H2 with a 6-month sunset to Windows 11 minimum.

## Deployment procedure

### Step 1: Confirm BitLocker recovery key storage is configured

Before requiring BitLocker, confirm that recovery keys will escrow to Entra ID. Without escrow, a device that needs recovery becomes unrecoverable.

Navigate to: **Entra admin center > Identity > Devices > All devices > Device settings**. Confirm:

* **Azure AD Join > Users may join devices to Azure AD**: set to All (or specific group)
* Scroll to **Enterprise State Roaming** section, not relevant here
* BitLocker recovery key escrow happens automatically when a device is Entra joined and BitLocker is enabled; verify by checking that at least one existing enrolled Windows device has a recovery key visible in the device's entry in Entra admin center

```powershell
./08-Verify-BitLockerEscrow.ps1
```

The script enumerates enrolled Windows devices and reports the count with and without recovery keys escrowed. Expected: devices that have completed BitLocker enablement should show recovery keys.

### Step 2: Deploy the Windows compliance policy in non-enforcing mode

The policy is created and assigned but with enforcement actions set to notify-only initially:

```powershell
./08-Deploy-WindowsCompliancePolicy.ps1 `
    -PolicyName "Windows Compliance Baseline" `
    -NonComplianceActionMode "NotifyOnly" `
    -AssignToAllDevices
```

The script creates the policy with the settings in the target configuration table and assigns it to all Windows devices (or to the specified device group).

Initial non-compliance action mode is notify-only: the policy evaluates devices and flags non-compliance but does not actually mark them as non-compliant for Conditional Access purposes. This produces reporting without enforcement impact.

### Step 3: Monitor compliance reporting for 7 days

```powershell
./08-Monitor-WindowsCompliance.ps1 -LookbackDays 7
```

The script reports:

* Total Windows devices evaluated
* Compliance pass rate
* Top failure reasons (BitLocker not enabled, Secure Boot disabled, OS version below minimum, firewall off, etc.)
* Devices in each failure category with their users

Review the output. For each failure category, plan remediation:

* **BitLocker not enabled:** typically requires an Intune configuration profile that enables BitLocker via endpoint security baseline. Some devices cannot enable BitLocker (no TPM, Windows Home edition); those devices need replacement.
* **Secure Boot disabled:** BIOS configuration. Update via OEM BIOS management tools or manual user configuration with documentation.
* **OS version below minimum:** Windows Update or Windows 11 upgrade. Devices that cannot reach the minimum (hardware too old) need replacement.
* **Firewall off:** endpoint security baseline typically enables firewall; investigate why devices are reporting it off.
* **Antivirus inactive:** Defender is Microsoft's built-in antivirus and should be active by default. Devices reporting antivirus inactive typically have a third-party antivirus installed that disabled Defender without properly registering itself. Investigate per device.

### Step 4: Configure non-compliance actions

After the observation period, enable the graduated non-compliance actions:

```powershell
./08-Configure-ComplianceActions.ps1 -PolicyName "Windows Compliance Baseline"
```

The script configures:

| Day of non-compliance | Action |
|---|---|
| Day 0 | Send email notification to user |
| Day 3 | Send follow-up email to user |
| Day 7 | Mark device as non-compliant (enforcement begins) |
| Day 14 | Email notification to admin distribution |
| Day 30 | Retire device (remove corporate data) - **optional, disabled by default** |

The retire-device action is the most aggressive; it removes corporate data from the device but leaves personal data intact. Most organizations leave this disabled initially and enable it only after demonstrating the earlier notification steps work reliably.

### Step 5: Enforce CA007 (compliant device requirement)

CA007 was deployed in Runbook 02 in report-only mode. With the Windows compliance policy now in place and providing real compliance signals, enforce CA007:

```powershell
./08-Enforce-CA007.ps1
```

The script switches CA007 from report-only to enabled. Devices that fail Windows compliance now fail CA007 on Microsoft 365 access.

Before running: confirm CA007 monitoring shows compliant device availability:

```powershell
./08-Monitor-CA007.ps1 -LookbackDays 14
```

Expected: report-only mode shows CA007 would succeed for the majority of Windows sign-ins (devices are reporting compliant). A pass rate below 90 percent indicates compliance policy tuning issues that should be resolved before enforcement.

### Step 6: Update operations runbook

Document:

* Windows compliance policy name and assignment scope
* Current minimum OS version and the planned tightening schedule (for example, "raise minimum to Windows 11 on 2026-10-01")
* Non-compliance action schedule
* Who monitors the admin-notification destination at day 14
* Escalation process for devices that cannot be remediated
* Quarterly review of compliance failure patterns

## Automation artifacts

* `automation/powershell/08-Verify-BitLockerEscrow.ps1` - Confirms BitLocker recovery key storage is working
* `automation/powershell/08-Deploy-WindowsCompliancePolicy.ps1` - Creates and assigns the Windows compliance policy
* `automation/powershell/08-Monitor-WindowsCompliance.ps1` - Reports compliance status across the Windows fleet
* `automation/powershell/08-Configure-ComplianceActions.ps1` - Configures graduated non-compliance actions
* `automation/powershell/08-Monitor-CA007.ps1` - Reports CA007 evaluation during observation
* `automation/powershell/08-Enforce-CA007.ps1` - Switches CA007 from report-only to enabled
* `automation/powershell/08-Verify-Deployment.ps1` - Confirms the runbook's target state

## Verification

### Configuration verification

```powershell
./08-Verify-Deployment.ps1
```

Expected output:

```
Windows Compliance Baseline policy:
  Exists: Yes
  Assigned to: All Windows devices
  BitLocker required: Yes
  Secure Boot required: Yes
  Code Integrity required: Yes
  Minimum OS version: 10.0.19045
  Antivirus required: Yes
  Firewall required: Yes

Non-compliance actions:
  Day 0: Notify user
  Day 3: Notify user
  Day 7: Mark non-compliant
  Day 14: Notify admin

Current fleet status:
  Total Windows devices: [N]
  Compliant: [N] ([percent]%)
  Non-compliant: [N]

CA007 (compliant device requirement): Enabled (enforcing)
```

### Functional verification

1. **Compliant device access succeeds.** A compliant Windows device signs in to Microsoft 365 resources. Access succeeds with MFA only; no device-related challenges.
2. **Non-compliant device is blocked.** Temporarily disable BitLocker on a test device (or use a device that is legitimately non-compliant). The device syncs to Intune and reports non-compliant. Attempt Microsoft 365 access. Expected: CA007 blocks access with a compliance-related error.
3. **Grace period works for new enrollments.** Enroll a fresh Windows device. During the initial sync and BitLocker enablement window, the device should be permitted access (grace period). Once the grace period elapses, compliance state becomes authoritative.
4. **User notifications arrive.** Non-compliant users receive the day-0 email. Verify one such email has arrived (may require waiting until a non-compliance event occurs).

## Additional controls (add-on variants)

### Additional controls with Defender Suite or E5 Security (Defender for Endpoint Plan 2)

For tenants with Defender for Endpoint Plan 2, the compliance policy can incorporate Defender for Endpoint risk signals as a compliance input:

```powershell
./08-Add-DefenderRiskCompliance.ps1 `
    -PolicyName "Windows Compliance Baseline" `
    -MaxAllowedRisk "Medium"
```

The script modifies the existing compliance policy to require Defender for Endpoint reporting a machine risk of Medium or lower. Devices reporting High risk from Defender for Endpoint become non-compliant even if all other compliance settings pass. Intune and Defender XDR communicate this through the Defender compliance connector (configured by default for tenants with Defender for Endpoint Plan 2 licensing).

This additional control is valuable because device compliance from static posture (BitLocker, Secure Boot, etc.) does not catch active compromise. A device with perfect compliance configuration but active malware running is compliant per the baseline policy; adding Defender risk as an input catches the active-compromise case.

For plain Business Premium (Defender for Endpoint Plan 1), the machine risk signal is not available as a compliance input; the baseline policy alone provides the static-posture coverage.

## What to watch after deployment

* **First-week compliance pass rate.** Expect 70 to 90 percent compliant initially; the remaining devices surface the remediation work. A pass rate below 70 percent indicates either unusual device population (lots of older hardware) or a policy setting that does not match the fleet's actual configuration.
* **Help desk tickets for specific failure categories.** Common patterns in the first two weeks: BitLocker prompts for recovery keys after Windows updates, users seeing the non-compliance notification and calling IT, devices that simply cannot meet minimum OS version because the hardware is too old.
* **Grace period bypasses.** If any device pattern routinely exploits the grace period (for example, a scheduled reprovisioning workflow that produces a fresh non-compliant device every week), the grace period is being misused. Investigate.
* **CA007 block events.** Each CA007 block is a user attempting access from a non-compliant device. Track the rate; sudden spikes indicate a widespread compliance regression (Windows Update breaking BitLocker, Defender antivirus signatures stale, etc.).
* **Compliance policy drift.** Intune's portal allows editing compliance policies directly; an administrator who edits without updating the automation artifacts produces drift. Monitor for policy changes via the audit runbook (scheduled for a later deployment) and enforce the change-management pattern: modifications to compliance policies go through the automation artifact, not through the portal directly.

## Rollback

Rollback of the Windows compliance policy:

```powershell
./08-Disable-CompliancePolicy.ps1 -PolicyName "Windows Compliance Baseline" -Reason "Documented reason"
```

Disabling the policy reverts devices to Intune's default compliance state. CA007 continues to require compliant devices; devices without an assigned compliance policy report as compliant-by-default in most cases, which means CA007 effectively permits everything.

For a more targeted rollback (for example, reverting a specific failing setting while keeping the rest of the policy active), modify the policy through the automation artifact rather than disabling the whole policy.

Full rollback is appropriate only if a tenant-wide issue prevents any device from achieving compliance. The more common scenario is a specific setting being misconfigured; address that setting specifically.

## References

* Microsoft Learn: [Device compliance policy settings for Windows 10 and later](https://learn.microsoft.com/en-us/mem/intune/protect/compliance-policy-create-windows)
* Microsoft Learn: [Actions for noncompliance](https://learn.microsoft.com/en-us/mem/intune/protect/actions-for-noncompliance)
* Microsoft Learn: [BitLocker policy settings](https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices)
* Microsoft Learn: [Integrate Microsoft Defender for Endpoint with Intune](https://learn.microsoft.com/en-us/mem/intune/protect/advanced-threat-protection-configure)
* M365 Hardening Playbook: [Compliant device status not required for access to sensitive applications](https://github.com/pslorenz/m365-hardening-playbook/blob/main/device-security/compliant-device-required.md)
* M365 Hardening Playbook: [VBS and Credential Guard not enforced via Intune](https://github.com/pslorenz/m365-hardening-playbook/blob/main/device-security/vbs-credential-guard-not-enforced.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Windows compliance policy recommendations
* NIST CSF 2.0: PR.DS-06, PR.AC-04, DE.CM-07
