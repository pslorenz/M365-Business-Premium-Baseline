# 09 - Mobile Device Compliance (iOS and Android)

**Category:** Device Compliance
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [07 - Intune Enrollment Strategy](./07-intune-enrollment-strategy.md) completed with Apple APNs and Android Enterprise configured
**Time to deploy:** 60 minutes active work, plus 14 days observation per platform
**Deployment risk:** Low to Medium. Compliance policies are additive; CA007 enforcement for mobile devices is medium risk because mobile is often the most loosely-managed device class in SMB environments.

## Purpose

This runbook deploys compliance policies for iOS, iPadOS, and Android devices enrolled in Intune. Mobile devices sit in an awkward position in most SMB tenants: widely used for email and Teams, infrequently configured beyond enrollment, and rarely held to the same compliance bar as corporate Windows devices. The compliance policies here establish a baseline appropriate to mobile form factors (device encryption, screen lock, minimum OS version, jailbreak/root detection) without demanding configurations mobile devices cannot reasonably meet.

The tenant before this runbook: iOS and Android devices enrolled via Runbook 07 appear in Intune inventory with compliance state unknown. Users access Microsoft 365 from these devices without any device-level assurance; CA007 (deployed and enforced in Runbook 08 for Windows) either excludes mobile platforms or passes them through without meaningful evaluation.

The tenant after: iOS/iPadOS and Android have separate compliance policies appropriate to their platform capabilities. Mobile devices that meet the baseline (encryption on, screen lock configured, modern OS, not jailbroken or rooted) are compliant; devices that fail are non-compliant and blocked from corporate access. Defender for Endpoint mobile integration (for Plan 2 tenants) adds active-threat detection as a compliance input.

The separation between iOS and Android reflects the different platform capabilities: iOS has user enrollment (BYOD) with limited device-level visibility, Android has both work profile and fully managed modes with varying visibility. The policies differentiate accordingly.

## Prerequisites

* Apple APNs certificate is current and not nearing expiration
* Apple Business Manager (ABM) token is valid (if managing corporate iOS)
* Android Enterprise binding is active
* Test iOS and Android devices are enrolled for initial validation
* App protection policies (MAM) are planned as a separate runbook; this runbook covers MDM compliance only

## Target configuration

At completion:

* **iOS/iPadOS compliance policy** deployed and assigned to all iOS devices
* **Android Enterprise Work Profile compliance policy** deployed and assigned to BYOD Android devices (if BYOD Android is permitted)
* **Android Enterprise Fully Managed compliance policy** deployed and assigned to corporate-owned Android (if applicable)
* **Non-compliance actions** configured for each policy with graduated escalation
* **CA007** updated to include iOS and Android platforms with appropriate grace period

### iOS/iPadOS policy settings

| Category | Setting | Value |
|---|---|---|
| Device Health | Jailbroken devices | Block |
| Device Health | Require device to be at or under Mobile Threat Defense level | Low (if MTD is configured) |
| Device Properties | Minimum OS version | 16.0 (iOS 16.0) |
| Device Properties | Maximum OS version | Not configured |
| System Security | Require password | Require |
| System Security | Simple passwords | Block |
| System Security | Password type | Numeric or Alphanumeric (default: Device default) |
| System Security | Minimum password length | 6 characters |
| System Security | Maximum minutes of inactivity | 15 |
| System Security | Password expiration | Not configured (iOS handles device-level password policy separately) |
| System Security | Number of previous passwords | Not configured |
| System Security | Require encryption of data storage | Require (iOS devices with passcodes are encrypted by default) |
| Email | Email profile must be managed by Intune | Not configured (email is typically managed by Intune in BYOD iOS) |

### Android (both work profile and fully managed) policy settings

| Category | Setting | Value |
|---|---|---|
| Device Health | Rooted devices | Block |
| Device Health | Require device to be at or under Mobile Threat Defense level | Low (if MTD is configured) |
| Device Health | Play Integrity verdict | Check basic integrity and certified devices |
| Device Properties | Minimum OS version | 11.0 |
| Device Properties | Maximum OS version | Not configured |
| Device Properties | Required Google Play Services version | Latest |
| System Security | Require password | Require |
| System Security | Minimum password length | 6 characters |
| System Security | Password type | Alphanumeric (or Numeric complex) |
| System Security | Password expiration | Not configured |
| System Security | Number of previous passwords | Not configured |
| System Security | Maximum minutes of inactivity | 15 |
| System Security | Encryption of data storage on device | Require |
| System Security | Block USB debugging on device | Require (Fully Managed only) |
| Defender for Endpoint | Device must be at or under machine risk score | Medium (if Defender for Endpoint on Android is onboarded) |

The Android policy differs between Work Profile and Fully Managed modes in specific settings that only apply to one mode. The deployment script handles the differentiation.

## Deployment procedure

### Step 1: Verify enrollment foundation

Before deploying compliance policies, confirm the enrollment infrastructure from Runbook 07 is healthy:

```powershell
./09-Verify-MobileInfrastructure.ps1
```

The script checks:
* Apple APNs certificate presence and expiration (warns if less than 90 days remaining)
* Apple Business Manager token status
* Android Enterprise binding status
* Count of currently-enrolled iOS devices
* Count of currently-enrolled Android devices

Address any infrastructure issue before deploying compliance policies. An expired APNs certificate, for example, will show as "broken iOS management" if a compliance policy is deployed against it; easier to catch and fix the certificate first.

### Step 2: Deploy iOS compliance policy in notify-only mode

```powershell
./09-Deploy-iOSCompliancePolicy.ps1 `
    -PolicyName "iOS Compliance Baseline" `
    -NonComplianceActionMode "NotifyOnly" `
    -AssignToAllDevices
```

The script creates the iOS compliance policy with the settings in the target configuration, assigns it to all iOS devices, and sets non-compliance actions to notify-only for the initial observation period.

### Step 3: Deploy Android compliance policies

Work Profile (BYOD) and Fully Managed (corporate) Android each get a dedicated compliance policy because the setting availability differs:

```powershell
./09-Deploy-AndroidCompliancePolicy.ps1 `
    -PolicyName "Android Work Profile Compliance" `
    -EnrollmentMode "WorkProfile" `
    -NonComplianceActionMode "NotifyOnly"

./09-Deploy-AndroidCompliancePolicy.ps1 `
    -PolicyName "Android Fully Managed Compliance" `
    -EnrollmentMode "FullyManaged" `
    -NonComplianceActionMode "NotifyOnly"
```

If the organization only uses one Android enrollment mode, deploy only the corresponding policy.

### Step 4: Monitor mobile compliance for 7 to 14 days

Mobile compliance evaluation typically takes a few sync cycles to stabilize. Monitor:

```powershell
./09-Monitor-MobileCompliance.ps1 -LookbackDays 14
```

The script reports per-platform compliance rates and top failure reasons. Common patterns:

* **iOS OS version below minimum:** users on older iPhones or iPads that cannot reach iOS 16. These devices need replacement or operate under exception.
* **Android OS version below minimum:** older Android phones that cannot reach Android 11. Typically replacement candidates.
* **Jailbroken/rooted detection:** rare in corporate fleets but occasionally catches a user device. Investigate individually.
* **No screen lock:** user has not configured a device passcode. Remediation is user-side (set a passcode).
* **Unknown integrity (Android):** Play Integrity check failed, possibly because the device is running custom firmware or is from a manufacturer that does not participate in Play Integrity. Review specific devices.

### Step 5: Update CA007 to include mobile platforms

CA007 was initially deployed in Runbook 02 and enforced in Runbook 08 with focus on Windows. Extend to cover iOS and Android:

```powershell
./09-Extend-CA007ForMobile.ps1
```

The script updates CA007 to include mobile platforms explicitly. Devices that fail iOS or Android compliance now fail CA007 on Microsoft 365 access.

Before running: confirm mobile compliance rates are acceptable (above 85 percent pass) via Step 4 output. Extending CA007 to mobile when 40 percent of phones are non-compliant produces unmanageable help desk volume.

### Step 6: Configure non-compliance actions

After observation:

```powershell
./09-Configure-MobileComplianceActions.ps1
```

The script configures graduated actions per policy:

| Day | Action (iOS and Android) |
|---|---|
| Day 0 | Send push notification and email to user |
| Day 3 | Follow-up notification |
| Day 7 | Mark device non-compliant (enforcement) |
| Day 21 | Admin notification; consider retiring the device |

Mobile devices get a longer grace period than Windows (21 days vs. 14) because mobile OS updates and remediation can take longer when users are away from wifi or in travel contexts.

### Step 7: Update operations runbook

Document:
* Each deployed mobile compliance policy with its assignment
* APNs certificate renewal date (annual task critical for iOS management)
* Apple Business Manager token renewal schedule
* Android Enterprise binding health check (quarterly)
* Current minimum OS versions and planned tightening schedule
* Exception process for mobile devices that cannot meet baseline (executive older iPhone, specialized field devices, etc.)

## Automation artifacts

* `automation/powershell/09-Verify-MobileInfrastructure.ps1` - Confirms APNs, ABM, and Android Enterprise are healthy
* `automation/powershell/09-Deploy-iOSCompliancePolicy.ps1` - Creates and assigns the iOS compliance policy
* `automation/powershell/09-Deploy-AndroidCompliancePolicy.ps1` - Creates and assigns Android compliance policies (Work Profile or Fully Managed)
* `automation/powershell/09-Monitor-MobileCompliance.ps1` - Reports mobile compliance rates
* `automation/powershell/09-Configure-MobileComplianceActions.ps1` - Configures graduated non-compliance actions
* `automation/powershell/09-Extend-CA007ForMobile.ps1` - Updates CA007 to enforce on mobile platforms
* `automation/powershell/09-Verify-Deployment.ps1` - Confirms the runbook's target state

## Verification

### Configuration verification

```powershell
./09-Verify-Deployment.ps1
```

Expected output covers each mobile platform: compliance policy presence, assignment, key settings, non-compliance action schedule, current fleet compliance rate, CA007 coverage.

### Functional verification

1. **Compliant iOS device access succeeds.** An enrolled iOS device with passcode, current iOS, not jailbroken, accesses Outlook mobile. Access succeeds.
2. **Non-compliant iOS device is blocked.** An enrolled iOS device with screen lock disabled (or an older OS version) fails iOS compliance. Attempting access is blocked by CA007.
3. **Compliant Android device access succeeds.** An enrolled Android device meeting all baseline requirements accesses Microsoft 365. Access succeeds.
4. **Jailbroken detection works.** A jailbroken iOS device (for security testing only, with appropriate authorization) is detected as non-compliant by the Jailbroken Devices check. Detection is probabilistic; confirm via portal.
5. **Grace period accommodates new enrollment.** A newly-enrolled mobile device has the grace window before compliance is evaluated authoritatively.

## Additional controls (add-on variants)

### Additional controls with Defender Suite or E5 Security (Defender for Endpoint on Mobile)

For tenants with Defender for Endpoint Plan 2, Mobile Threat Defense is available on iOS and Android. MTD detects active threats on mobile devices (malicious apps, network attacks, phishing) and reports a machine risk score that can be used as a compliance input.

To deploy Defender for Endpoint on mobile:

1. In the Microsoft Defender portal, onboard mobile platforms under **Settings > Endpoints > Device management > Enrollment > iOS / Android**
2. Deploy the Defender for Endpoint app to managed mobile devices via Intune (app assignment)
3. Configure the Intune connector to receive Defender risk signals

```powershell
./09-Enable-DefenderMobileCompliance.ps1 -MaxAllowedRisk "Medium"
```

The script modifies the existing iOS and Android compliance policies to require Defender machine risk of Medium or lower. Devices with High risk from Defender (active malware, known compromised networks, phishing site visits) become non-compliant even if other settings pass.

For plain Business Premium (Defender for Endpoint Plan 1 only, no mobile coverage), this additional control is not available; the baseline compliance policy alone provides static posture coverage.

## What to watch after deployment

* **iOS enrollment failures.** Users encountering new compliance requirements sometimes get stuck at the enrollment step if their device cannot meet a requirement (OS too old, jailbroken). Track enrollment failure rates and investigate spikes.
* **Android fragmentation.** Different Android OEMs (Samsung, Google, Motorola, OnePlus, etc.) have different Play Integrity behaviors, different update schedules, and different compliance patterns. Failures that cluster around a specific OEM may indicate a vendor-specific issue rather than a generic compliance problem.
* **OS version lag.** Mobile OS versions advance quickly; minimum OS version settings can become stale within 6 to 12 months. Schedule quarterly review of minimum OS versions to stay current with vendor support lifecycle.
* **Users switching devices.** Users replacing personal phones every 1 to 2 years means mobile fleet composition changes continuously. A minimum-OS requirement that is reasonable today may block a user whose new phone is 6 months old if the vendor did not ship with current OS. Monitor for these edge cases.
* **Certificate renewal dates.** APNs annual renewal is the single most likely cause of mobile management breaking in SMB environments. Track it in the operations runbook with a 60-day reminder.

## Rollback

Per-platform rollback via the corresponding Deploy script with the policy name:

```powershell
./09-Disable-MobileCompliancePolicy.ps1 -PolicyName "iOS Compliance Baseline" -Reason "Documented reason"
```

Full mobile rollback disables all deployed mobile compliance policies. Usually the wrong answer; if a specific setting is causing problems, modify that setting rather than disabling whole policies.

Extending CA007 to mobile and then needing to roll it back is handled through CA007 directly (via `02e-Disable-CAPolicy.ps1` from Runbook 02), which unblocks mobile access but preserves Windows enforcement.

## References

* Microsoft Learn: [Device compliance policy settings for iOS](https://learn.microsoft.com/en-us/mem/intune/protect/compliance-policy-create-ios)
* Microsoft Learn: [Device compliance policy settings for Android Enterprise](https://learn.microsoft.com/en-us/mem/intune/protect/compliance-policy-create-android-for-work)
* Microsoft Learn: [Play Integrity API in Intune](https://learn.microsoft.com/en-us/mem/intune/protect/mtd-connector-enable)
* Microsoft Learn: [Configure Defender for Endpoint on iOS](https://learn.microsoft.com/en-us/defender-endpoint/ios-install)
* Microsoft Learn: [Configure Defender for Endpoint on Android](https://learn.microsoft.com/en-us/defender-endpoint/android-intune)
* CIS Microsoft 365 Foundations Benchmark v4.0: Mobile device compliance
* NIST CSF 2.0: PR.DS-06, PR.AC-04, DE.CM-07
