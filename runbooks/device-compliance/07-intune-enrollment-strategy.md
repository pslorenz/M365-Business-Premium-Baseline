# 07 - Intune Enrollment Strategy

**Category:** Device Compliance
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [01 - Tenant Initial Configuration and Break Glass Accounts](../identity-and-access/01-tenant-initial-and-break-glass.md) completed
* [02 - Conditional Access Baseline Policy Stack](../conditional-access/02-ca-baseline-policy-stack.md) completed with CA007 (compliant device requirement) planned or deployed in report-only
**Time to deploy:** 2 to 4 hours to configure the MDM authority, enrollment profiles, and auto-enrollment; additional time scales with device count
**Deployment risk:** Low. The configuration established here is foundational; device-level effects occur only as devices enroll, and report-only CA007 provides the observation window before access enforcement.

## Purpose

This runbook establishes the device enrollment strategy for the tenant. Every subsequent device compliance runbook assumes devices are being enrolled through a documented path, that enrollment produces predictable configuration, and that the enrollment method is aligned with the organization's device procurement and lifecycle patterns. Without a deliberate strategy, device enrollment drifts: users enroll manually from personal devices, corporate devices miss Autopilot, BYOD devices accumulate with inconsistent configuration, and the device compliance CA policy (CA007) blocks legitimate work because the affected devices never completed the compliance checkpoints the policy requires.

The strategy covers three distinct device populations:

* **Corporate-owned Windows devices** (employee laptops, desktops). Primary enrollment path: Windows Autopilot. Provides zero-touch provisioning, pre-configured compliance policies, and standardized naming.
* **Corporate-owned mobile devices** (iPhones, iPads, Android phones issued by the organization). Primary enrollment path: Apple Business Manager for iOS, Android Enterprise dedicated for Android.
* **Personal devices used for work** (BYOD). Primary path: Intune app protection policies (MAM without enrollment). Does not enroll the device in Intune; applies protection at the app layer. Alternative: MDM enrollment with narrow policy scope. The choice depends on the organization's BYOD position.

The tenant before this runbook: the MDM authority may be set to Intune (current Microsoft default) or may be unset in older tenants. No Autopilot configuration exists, no enrollment profiles, no automatic enrollment tied to Entra. Users enrolling devices go through manual workflows that produce unpredictable results.

The tenant after: Intune is set as the MDM authority, Windows devices automatically enroll when users sign in to an Entra-joined device, Autopilot profiles exist for zero-touch provisioning, Apple enrollment is configured for managed iOS, Android Enterprise enrollment is configured for managed Android, and a BYOD policy documents the organization's position on personal devices. Compliance policies and app protection policies are deployed in later runbooks; this runbook establishes the enrollment paths those policies will target.

## Prerequisites

* Microsoft 365 Business Premium, E3, or E5 (Intune is included in all three); or Intune standalone licensing
* All users who will have devices enrolled have Intune licensing assigned
* For Autopilot: partner relationship with the hardware OEM (Dell, HP, Lenovo, etc.) that supports hardware hash registration, or a process to register hashes manually at first boot
* For Apple enrollment: Apple Business Manager account for the organization, and Apple Push Notification Service (APNs) certificate will be created during this runbook
* For Android Enterprise: Google account for the organization, managed Google Play association will be created
* For BYOD: documented organizational position on whether BYOD is permitted and under what terms

## Target configuration

At completion:

* **MDM authority** is set to Intune
* **Automatic MDM enrollment** is enabled for all users through Entra ID device settings
* **Windows Autopilot** is configured with at least one deployment profile (user-driven by default; self-deploying for kiosks if applicable)
* **Enrollment Status Page** is configured to block device use until initial policies and applications are deployed
* **Apple APNs certificate** is configured and refreshed; Apple Business Manager token imported
* **Apple Automated Device Enrollment (ADE)** profile exists for managed iOS
* **Apple User Enrollment** profile exists for BYOD iOS (if BYOD is permitted)
* **Android Enterprise** binding is configured with managed Google Play
* **Android work profile** enrollment profile exists for BYOD Android
* **Android fully managed** enrollment profile exists for corporate-owned Android (if applicable)
* **Enrollment restrictions** prevent personal device enrollment if BYOD is not permitted; permit enrollment with specific platform versions if BYOD is permitted
* **Device naming convention** is configured (standard pattern: `[OrgCode]-[UserLastName]-[DeviceType]`; or similar)

## Deployment procedure

### Step 1: Confirm Intune is the MDM authority

For most tenants, Intune is already the MDM authority by default. Confirm:

```powershell
./07-Verify-MDMAuthority.ps1
```

Expected output:

```
MDM authority: Microsoft Intune
Tenant ID: [tenant ID]
Intune service reachable: Yes
```

If MDM authority is unset or set to a different value, contact Microsoft Support to correct; self-service change of MDM authority is not always available.

Portal check: **Microsoft Intune admin center > Tenant administration > Tenant details > MDM authority**.

### Step 2: Configure automatic MDM enrollment for Entra-joined devices

When a user signs in to a new Windows device and joins it to Entra ID, the device should automatically enroll in Intune without additional user action:

```powershell
./07-Configure-AutoEnrollment.ps1 -Scope "All users"
```

The script configures the Intune mobile device management settings in the Entra admin center:

* MDM user scope: All users (or the specific group containing Intune-licensed users)
* MAM user scope: All users (or specific group)
* MDM terms of use URL: organization-specific URL if available, otherwise Microsoft default
* MDM discovery URL: Microsoft default (https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc)
* MAM discovery URL: Microsoft default

Portal path: **Entra admin center > Identity > Devices > All devices > Device settings > Automatic enrollment**.

Verification: a test Windows 11 device that signs in to Entra ID with a licensed user should appear in **Intune admin center > Devices > All devices** within 30 minutes.

### Step 3: Configure the Windows Autopilot deployment profile

Windows Autopilot provisions Windows devices out of the box: the user signs in on first boot, and the device is automatically joined to Entra ID, enrolled in Intune, and configured with the organization's policies and applications. No manual imaging is required.

```powershell
./07-Create-AutopilotProfile.ps1 `
    -ProfileName "Corporate Windows 11 - User-driven" `
    -DeploymentMode "UserDriven" `
    -JoinType "EntraJoin" `
    -DeviceNamePattern "CORP-%RAND:5%"
```

Profile settings:

* **Deployment mode:** User-driven (the user signs in during out-of-box experience; default for SMB)
* **Join type:** Entra joined (not hybrid; SMB tenants typically do not have on-premises Active Directory)
* **Skip AAD premium prompt:** Yes
* **Skip privacy settings:** Yes
* **Skip EULA:** No (users should acknowledge; required in some jurisdictions)
* **Skip OOBE language selection:** No
* **User account type:** Standard (not administrator; principle of least privilege on endpoints)
* **Device name template:** Organization-specific pattern

For deployments supporting kiosks or shared devices, create an additional self-deploying profile:

```powershell
./07-Create-AutopilotProfile.ps1 `
    -ProfileName "Kiosk - Self-deploying" `
    -DeploymentMode "SelfDeploying" `
    -JoinType "EntraJoin" `
    -DeviceNamePattern "KIOSK-%RAND:5%"
```

Self-deploying profiles do not require user interaction at provisioning; appropriate for shared kiosks, signage devices, and some lab environments.

### Step 4: Configure the Enrollment Status Page

The Enrollment Status Page (ESP) blocks device use during initial provisioning until specific policies and applications are deployed. Without ESP configuration, users can access the Windows desktop before compliance policies, applications, and configuration profiles have applied, which produces a window where the device is provisioned but not protected.

```powershell
./07-Configure-EnrollmentStatusPage.ps1 `
    -ProfileName "Default ESP" `
    -BlockUntilComplete $true `
    -TimeoutMinutes 60
```

Settings:

* **Show app and profile installation progress:** Yes
* **Block device use until required apps are installed:** Yes
* **Timeout:** 60 minutes (after which the device proceeds even if not all apps installed, with a warning)
* **Show error when installation fails:** Yes
* **Required apps:** to be populated by the application deployment runbook (future phase)
* **Assignment:** All users with appropriate Intune scope

### Step 5: Configure Apple APNs and Apple Business Manager

Managing iOS and iPadOS requires Apple Push Notification Service (APNs) certificate and optionally Apple Business Manager for zero-touch enrollment.

**APNs certificate:**

1. Navigate to **Intune admin center > Devices > iOS/iPadOS > iOS/iPadOS enrollment > Apple MDM Push certificate**
2. Download the CSR from Intune
3. Upload the CSR to Apple Push Certificates Portal (https://identity.apple.com/pushcert), create a certificate, and download the `.pem` file
4. Upload the `.pem` file to Intune, providing the Apple ID associated with the certificate
5. Record the Apple ID and certificate expiration in the operations runbook (the certificate expires annually and must be renewed)

The process is manual and browser-based; not scriptable through Graph.

**Apple Business Manager (ABM):**

1. Create or confirm an ABM account at https://business.apple.com
2. Generate an MDM server token in ABM, associate it with Intune
3. Upload the token to **Intune admin center > Devices > Enrollment > Apple Enrollment > Enrollment program tokens**
4. Associate corporate-purchased Apple devices to the ABM token through the device reseller or Apple sales contact

Create the ADE profile:

```powershell
./07-Create-AppleADEProfile.ps1 `
    -ProfileName "Corporate iOS/iPadOS - Managed" `
    -Supervised $true `
    -UserAffinity "UserAffinity"
```

Profile settings:

* **Supervised:** Yes (provides administrative capabilities on corporate devices; not appropriate for BYOD)
* **User affinity:** UserAffinity (device is associated with a specific user) for most corporate uses; NoUserAffinity for shared devices
* **Setup assistant:** skip location services, Siri setup, and other optional steps to reduce user friction during enrollment

### Step 6: Configure Apple User Enrollment for BYOD iOS (if applicable)

User Enrollment is Apple's BYOD-appropriate enrollment mode: the organization manages a work account on the device without controlling the entire device. Personal data remains outside the organization's reach; work data is in a managed container.

If BYOD iOS is permitted:

```powershell
./07-Create-AppleUserEnrollmentProfile.ps1 `
    -ProfileName "BYOD iOS - User Enrollment"
```

Profile settings:

* **Enrollment type:** User Enrollment with service account (Microsoft-managed Apple ID)
* **Associated compliance policy:** BYOD-specific compliance policy (to be deployed in a later runbook)
* **App protection policy:** applies through Intune app protection (covered in the app protection runbook)

### Step 7: Configure Android Enterprise

Android Enterprise is the Google-managed framework for corporate Android management. The binding connects Intune to managed Google Play.

1. Navigate to **Intune admin center > Devices > Android > Android enrollment > Managed Google Play**
2. Click "Launch Google to connect now"; a Google sign-in prompt opens
3. Use a Google account dedicated to the organization (not a personal Google account)
4. Accept the managed Google Play agreement
5. Intune automatically binds to the managed Google Play enterprise

For corporate-owned Android:

```powershell
./07-Create-AndroidEnrollmentProfile.ps1 `
    -ProfileName "Corporate Android - Fully Managed" `
    -EnrollmentMode "FullyManaged" `
    -TokenExpiration "Never"
```

For BYOD Android with work profile:

```powershell
./07-Create-AndroidEnrollmentProfile.ps1 `
    -ProfileName "BYOD Android - Work Profile" `
    -EnrollmentMode "WorkProfile" `
    -TokenExpiration "Never"
```

Each enrollment mode produces a different device experience:

* **Fully Managed:** the organization controls the entire device. Appropriate for corporate-owned devices; not BYOD.
* **Work Profile:** a separate work container on a personal device. Personal data and apps remain outside the organization's reach.
* **Dedicated (kiosk):** single-purpose devices, not user-associated. Appropriate for shared-use devices only.

### Step 8: Configure enrollment restrictions

Enrollment restrictions control which devices can enroll. Default Intune allows any device platform and any personal ownership type; this is usually too permissive.

```powershell
./07-Configure-EnrollmentRestrictions.ps1 `
    -BlockPersonalAndroid $false `
    -BlockPersonaliOS $false `
    -BlockPersonalWindows $true `
    -BlockPersonalMacOS $true `
    -MinimumWindowsVersion "10.0.19045" `
    -MinimumiOSVersion "16.0" `
    -MinimumAndroidVersion "11.0"
```

Settings (adjust to the organization's BYOD position):

* **Windows personal:** Block if BYOD Windows is not permitted; allow if BYOD Windows is expected
* **macOS personal:** similar
* **iOS personal:** Allow for User Enrollment; block if corporate-only
* **Android personal:** Allow for Work Profile; block if corporate-only
* **Minimum OS versions:** set to currently-supported versions. Outdated devices cannot meet compliance anyway; enrollment restrictions catch them at the enrollment step.

### Step 9: Update operations runbook

Document:

* Current MDM authority and automatic enrollment scope
* Autopilot profiles with their deployment mode and assignment
* ESP configuration and timeout
* Apple APNs certificate expiration date (renewal reminder)
* Apple Business Manager token expiration
* Android Enterprise binding status
* Enrollment restrictions and the BYOD position they reflect
* Annual reviews: APNs certificate renewal, Apple BM token refresh, Android Enterprise binding health, enrollment restriction alignment with current BYOD policy

## Automation artifacts

* `automation/powershell/07-Verify-MDMAuthority.ps1` - Confirms Intune is the MDM authority
* `automation/powershell/07-Configure-AutoEnrollment.ps1` - Enables automatic MDM enrollment for Entra-joined devices
* `automation/powershell/07-Create-AutopilotProfile.ps1` - Creates a Windows Autopilot deployment profile
* `automation/powershell/07-Configure-EnrollmentStatusPage.ps1` - Configures the ESP
* `automation/powershell/07-Create-AppleADEProfile.ps1` - Creates an Apple Automated Device Enrollment profile
* `automation/powershell/07-Create-AppleUserEnrollmentProfile.ps1` - Creates an Apple User Enrollment profile (BYOD)
* `automation/powershell/07-Create-AndroidEnrollmentProfile.ps1` - Creates an Android Enterprise enrollment profile
* `automation/powershell/07-Configure-EnrollmentRestrictions.ps1` - Sets platform and version restrictions
* `automation/powershell/07-Verify-Deployment.ps1` - Confirms the runbook's target state

## Verification

### Configuration verification

```powershell
./07-Verify-Deployment.ps1
```

Expected output covers each enrollment path: MDM authority, auto-enrollment scope, Autopilot profiles count, ESP existence and configuration, Apple APNs status with expiration, ABM token status, Android Enterprise binding status, enrollment restrictions summary.

### Functional verification

1. **Windows auto-enrollment.** Sign in to a fresh Windows 11 device with a licensed user account. Expected: device enrolls in Intune automatically, appears in the Intune admin center within 30 minutes.
2. **Autopilot provisioning.** Register a test Windows device hardware hash with Autopilot, perform a fresh out-of-box setup. Expected: device provisions automatically through the configured Autopilot profile, ESP blocks user sign-in until required apps are installed.
3. **Apple enrollment.** If ABM is configured, enroll an Apple device through ABM. If user-driven, a test user installs Intune Company Portal on a personal iPhone and enrolls through User Enrollment. Expected: device appears in Intune as either corporate (ADE) or personal (User Enrollment).
4. **Android enrollment.** Enroll an Android device through the Work Profile or Fully Managed path. Expected: device appears in Intune with the correct ownership classification.
5. **Enrollment restrictions.** Attempt to enroll a device on a platform or OS version blocked by the restriction. Expected: enrollment fails with a clear error.

## Additional controls (add-on variants)

This runbook's configuration is identical across all variants; Intune is available in all Business Premium variants. No add-on-specific sections.

Defender for Endpoint onboarding (Plan 1 in plain Business Premium, Plan 2 with Defender Suite or E5 Security) is covered in a later device compliance runbook and builds on the enrollment paths established here.

## What to watch after deployment

* **APNs certificate expiration.** Apple APNs certificates expire 12 months after issuance. An expired certificate breaks all iOS management; no devices can check in, no policies apply. The operations runbook must track the expiration; a renewal reminder 30 days before expiration is essential.
* **Apple Business Manager token expiration.** Similar to APNs; the token refreshes through the browser-based workflow and must be renewed before expiration. Typically expires 1 year after creation.
* **Android Enterprise binding.** Usually stable but can be affected by changes to the Google account associated with the binding. If the Google account is disabled, the binding breaks.
* **Autopilot profile coverage.** New device models from a new OEM may not work with existing Autopilot profiles if the hash registration process differs. Document the OEM's hash registration path for each supported manufacturer.
* **Enrollment failures.** Alert on device enrollment failures in Intune (covered in the audit and alerting runbook). A spike in enrollment failures indicates a broken enrollment profile, expired certificate, or licensing issue.
* **BYOD policy drift.** User populations change; BYOD policies that made sense a year ago may no longer match the current workforce. Annual review of BYOD position and enrollment restrictions.

## Rollback

Rollback of the enrollment strategy is operationally rare because disabling enrollment paths breaks device onboarding for anyone whose device has not yet enrolled.

If a specific enrollment path needs to be removed (for example, ending BYOD support for a specific platform), the rollback is:

1. Update enrollment restrictions to block the specific platform or ownership type
2. Notify users with devices already enrolled under the path that are being removed; plan their migration to an alternative path or device replacement
3. Remove the specific enrollment profile after the user population has migrated

Do not delete the MDM authority or disable automatic enrollment wholesale; recovery from that state requires Microsoft Support engagement.

## References

* Microsoft Learn: [Microsoft Intune enrollment overview](https://learn.microsoft.com/en-us/mem/intune/enrollment/device-enrollment)
* Microsoft Learn: [Windows Autopilot overview](https://learn.microsoft.com/en-us/autopilot/windows-autopilot)
* Microsoft Learn: [Set up Apple Business Manager for automatic enrollment](https://learn.microsoft.com/en-us/mem/intune/enrollment/device-enrollment-program-enroll-ios)
* Microsoft Learn: [Set up Android Enterprise](https://learn.microsoft.com/en-us/mem/intune/enrollment/connect-intune-android-enterprise)
* Microsoft Learn: [Create an Apple MDM push certificate](https://learn.microsoft.com/en-us/mem/intune/enrollment/apple-mdm-push-certificate-get)
* M365 Hardening Playbook: [Compliant device status not required for access to sensitive applications](https://github.com/pslorenz/m365-hardening-playbook/blob/main/device-security/compliant-device-required.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Mobile device management
* NIST CSF 2.0: PR.IP-01, PR.IP-02, PR.AC-03
