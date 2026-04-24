# 10 - VBS, Credential Guard, and TPM Hardware Enforcement

**Category:** Device Compliance
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [08 - Windows Device Compliance Policy](./08-windows-compliance-policy.md) completed and CA007 enforced on Windows
**Time to deploy:** 60 minutes active work for policy deployment, plus device-level remediation time that scales with fleet size (days to weeks for hardware-level BIOS changes and device replacements)
**Deployment risk:** Medium. Hardware-level requirements expose devices that cannot meet them; those devices need BIOS configuration changes or replacement.

## Purpose

This runbook deploys hardware-layer protections on Windows devices: Virtualization-Based Security (VBS), Credential Guard, Hypervisor-protected Code Integrity (HVCI), and TPM 2.0 enforcement through compliance policy. The Windows compliance policy deployed in Runbook 08 covers software-layer compliance (BitLocker, Secure Boot, OS version, firewall, antivirus); this runbook adds the hardware-isolated protections that defend against specific credential theft and persistence attack patterns.

Credential Guard specifically is the single most valuable hardware-layer control for M365 environments. It protects the Primary Refresh Token (PRT) that Windows holds for signed-in users, which is the credential artifact that enables single sign-on from the managed Windows device to all Microsoft 365 services. A PRT on an unprotected device can be extracted by commodity tooling (Mimikatz, ROADtoken, AADInternals) and used from attacker infrastructure to impersonate the user across M365. Credential Guard moves the PRT into a VBS-isolated memory region that is inaccessible to normal kernel code, including code running as SYSTEM; an attacker with full endpoint compromise cannot extract the PRT through standard tooling.

The tenant before this runbook: Windows devices enrolled per Runbook 07 and compliant per Runbook 08 meet software-layer baseline. VBS may or may not be enabled per device (typically not enabled by default on clean Windows installs, though Windows 11 enables HVCI by default on new deployments). Credential Guard is not enabled. The PRT on each managed device is extractable through local admin compromise.

The tenant after: an Intune endpoint security profile deploys VBS, HVCI, and Credential Guard across the fleet with UEFI Lock enabled. The compliance policy is updated to require TPM 2.0 presence, which forces hardware-refresh conversations for devices that cannot meet the requirement. Credential theft attacks against PRT, cached Kerberos tickets, and NTLM hashes are significantly harder for an attacker with endpoint compromise.

## Prerequisites

* Windows compliance policy deployed and enforced (Runbook 08)
* Hardware inventory of the Windows fleet available: TPM version per device, Secure Boot state per device, UEFI vs. legacy BIOS
* BIOS management tooling for the organization's device OEMs (Dell Command Configure, HP BIOS Configuration Utility, Lenovo BIOS Update for Windows) if available, or documented manual BIOS configuration process
* Change-management approval for hardware-level changes; this runbook produces BIOS reconfiguration and may force device replacement

## Target configuration

At completion:

* **VBS, Credential Guard, HVCI** deployed via Intune Endpoint Security Account Protection profile
* **UEFI Lock enabled** on the deployment (locks settings in firmware, prevents software-based disable)
* **Profile assigned** to all Windows devices that meet hardware requirements
* **TPM 2.0 requirement** added to the Windows compliance policy
* **Hardware remediation tracking** for devices that cannot meet TPM 2.0 or VBS requirements

Settings deployed by the Endpoint Security Account Protection profile:

| Setting | Value |
|---|---|
| Turn on Virtualization Based Security | Enable with UEFI Lock |
| Secure Boot and DMA Protection | Secure Boot and DMA Protection |
| Launch System Guard | Enabled (where platform supports) |
| Credential Guard | Enable with UEFI Lock |
| Memory Integrity (HVCI) | Enabled with UEFI Lock |

Compliance policy addition:

| Setting | Value |
|---|---|
| Require a Trusted Platform Module (TPM) chip | Require |

## Deployment procedure

### Step 1: Audit the Windows fleet's hardware readiness

Before deploying, understand which devices can meet the requirements and which cannot:

```powershell
./10-Audit-HardwareReadiness.ps1 -OutputPath "./hardware-audit-$(Get-Date -Format 'yyyyMMdd').csv"
```

The audit script enumerates Windows devices and reports per device:

* TPM version (2.0, 1.2, or absent)
* Secure Boot state
* BIOS mode (UEFI vs. Legacy)
* Manufacturer and model
* OS edition (Enterprise, Pro, Home)
* Compliant or non-compliant under the Windows compliance policy (Runbook 08)
* VBS readiness prediction

Review the output. Categorize each device:

* **Ready for VBS:** TPM 2.0, Secure Boot enabled, UEFI, Windows 10/11 Enterprise or Pro. No action required before deployment.
* **Needs BIOS configuration:** TPM 2.0 hardware present but disabled; Secure Boot disabled; UEFI available but running in legacy BIOS mode. BIOS reconfiguration is required; vendor BIOS tools can push settings at scale for managed fleets.
* **Needs replacement:** TPM 1.2 only, or no TPM, or hardware that cannot run UEFI. Plan replacement with appropriate lead time.
* **Edition mismatch:** Windows Home devices. Not supported by VBS/Credential Guard; upgrade to Pro or Enterprise, or replace.

For a typical SMB fleet, expect 80 to 95 percent ready, 5 to 15 percent needing BIOS configuration, 0 to 5 percent needing replacement. Older-fleet SMBs (devices averaging 4+ years old) may see 30 to 50 percent in the BIOS-configuration category.

### Step 2: Remediate BIOS-configuration devices

Use vendor BIOS management tools to push the required settings. Common vendor approaches:

* **Dell:** Dell Command Configure can push Secure Boot enablement and TPM activation via an Intune Win32 app deployment
* **HP:** HP BIOS Configuration Utility similar
* **Lenovo:** Lenovo BIOS setup via Intune Win32 app

For fleets without vendor tooling, document the manual BIOS configuration procedure per device model. Coordinate with deskside support to execute during scheduled device touches (user check-ins, IT visits, warranty service windows).

The BIOS-configuration remediation can proceed in parallel with Step 3 policy deployment; devices that are not yet remediated will fail compliance after enforcement, which is the forcing function.

### Step 3: Deploy the Endpoint Security profile

```powershell
./10-Deploy-AccountProtectionProfile.ps1 `
    -ProfileName "Windows VBS and Credential Guard" `
    -EnableUEFILock
```

The script creates an Intune Endpoint Security Account Protection profile with VBS, Credential Guard, and HVCI all set to Enable with UEFI Lock. The profile is assigned to all Windows devices.

Note on UEFI Lock: once UEFI Lock is applied and the device is rebooted, disabling VBS or Credential Guard requires physical access to the device and a specific UEFI-level procedure (Microsoft publishes a script for this). This is a deliberate characteristic of the setting; it prevents malware or compromised local admin from disabling VBS from within Windows. Review the one-way-ness of the setting before deploying; for most SMB tenants committed to Credential Guard indefinitely, UEFI Lock is the correct choice.

### Step 4: Monitor deployment progress

```powershell
./10-Monitor-VBSDeployment.ps1 -LookbackDays 14
```

The script queries Intune device reporting for VBS status, Credential Guard status, and HVCI status across the Windows fleet. Reports:

* Total devices with policy assigned
* Devices where policy application succeeded (VBS running, Credential Guard running, HVCI running)
* Devices where policy application failed (policy assigned but settings not active)
* Devices reporting errors

Expected after 2 weeks: 85 to 95 percent of capable devices have VBS running. Lower rates indicate BIOS configuration issues (Step 2 incomplete) or hardware incompatibilities.

### Step 5: Add TPM 2.0 to compliance policy

Once the VBS profile is deploying successfully to the fleet, add the TPM 2.0 compliance requirement:

```powershell
./10-Add-TPMCompliance.ps1 -PolicyName "Windows Compliance Baseline"
```

The script modifies the Windows compliance policy (deployed in Runbook 08) to require TPM 2.0. Devices without TPM 2.0 become non-compliant and are blocked by CA007.

Before running: confirm the hardware-readiness audit (Step 1) identified all devices that cannot meet TPM 2.0, and that replacement or exception plans are in place for those devices. Enforcing TPM 2.0 before the remediation path is clear produces access-denied events for users whose devices have not yet been replaced.

### Step 6: Monitor and remediate TPM non-compliance

```powershell
./10-Monitor-TPMCompliance.ps1 -LookbackDays 7
```

Report shows devices failing the TPM 2.0 requirement. For each:

* Device with TPM hardware but disabled in BIOS: Step 2 remediation
* Device with TPM 1.2 only: replacement required
* Device with no TPM: replacement required
* Windows Home edition device: edition upgrade or replacement required

Track remediation in the operations runbook. Devices that stay non-compliant beyond 30 days should escalate to management for replacement decisions.

### Step 7: Update operations runbook

Document:

* Endpoint Security profile name and assignment
* UEFI Lock status (enabled)
* Current VBS deployment rate across the Windows fleet
* Current TPM 2.0 compliance rate
* Devices with outstanding hardware remediation (BIOS, replacement)
* Hardware refresh timeline tied to TPM 2.0 enforcement

## Automation artifacts

* `automation/powershell/10-Audit-HardwareReadiness.ps1` - Reports VBS readiness per device
* `automation/powershell/10-Deploy-AccountProtectionProfile.ps1` - Creates the Endpoint Security Account Protection profile
* `automation/powershell/10-Monitor-VBSDeployment.ps1` - Reports VBS and Credential Guard running status
* `automation/powershell/10-Add-TPMCompliance.ps1` - Adds TPM 2.0 requirement to Windows compliance policy
* `automation/powershell/10-Monitor-TPMCompliance.ps1` - Reports TPM 2.0 compliance across the Windows fleet
* `automation/powershell/10-Verify-Deployment.ps1` - Confirms the runbook's target state

## Verification

### Configuration verification

```powershell
./10-Verify-Deployment.ps1
```

Expected output:

```
Endpoint Security Account Protection profile:
  Name: Windows VBS and Credential Guard
  Assigned to: All Windows devices
  VBS: Enable with UEFI Lock
  Credential Guard: Enable with UEFI Lock
  HVCI: Enabled with UEFI Lock

Windows compliance policy (from Runbook 08):
  TPM 2.0 requirement: Required

Fleet status:
  Total Windows devices: [N]
  VBS running: [N] ([percent]%)
  Credential Guard running: [N] ([percent]%)
  HVCI running: [N] ([percent]%)
  TPM 2.0 compliant: [N] ([percent]%)

Remediation pending:
  BIOS configuration needed: [N]
  Hardware replacement needed: [N]
```

### Functional verification

1. **VBS and Credential Guard running on a sample device.** Check on a test device:
   ```powershell
   Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard |
       Select VirtualizationBasedSecurityStatus, SecurityServicesRunning
   ```
   Expected: `VirtualizationBasedSecurityStatus = 2` (Running), `SecurityServicesRunning` contains 1 (Credential Guard) and 2 (HVCI).

2. **PRT extraction blocked.** On a VBS-enabled test device (with appropriate authorization), attempt PRT extraction via Mimikatz. Expected: extraction fails with LSA isolation error. On a non-VBS comparison device, extraction succeeds (for contrast). Only run this test in a sanctioned lab environment.

3. **Non-TPM device blocked by CA007.** A device without TPM 2.0 fails the compliance policy, becomes non-compliant, and is blocked by CA007 on Microsoft 365 access.

4. **UEFI Lock persists across reboots.** Disable Credential Guard via regedit on a test device that has UEFI Lock applied. Reboot. Expected: Credential Guard remains enabled because UEFI Lock supersedes the registry setting.

## Additional controls (add-on variants)

### Additional controls with Defender Suite or E5 Security (Defender for Endpoint Plan 2)

Defender for Endpoint Plan 2 includes Attack Surface Reduction (ASR) rules that complement VBS and Credential Guard. ASR rules block specific attacker behaviors: execution of obfuscated scripts, credential-theft techniques against LSASS memory, Office applications launching child processes, and several other patterns. Deploying ASR alongside Credential Guard produces defense-in-depth: Credential Guard prevents PRT extraction from VBS-isolated memory; ASR prevents the broader class of credential theft and initial-access techniques that would be used to obtain the local admin access needed to attempt the extraction.

ASR rule deployment is a separate runbook (planned for the Defender for Endpoint phase). This runbook does not deploy ASR; the note here is that the two capabilities are complementary and an MSP managing Defender Suite tenants should deploy both.

For plain Business Premium (Defender for Endpoint Plan 1), ASR rules are not available at full capability; Plan 1 includes a limited ASR rule set but not the full configuration surface.

## What to watch after deployment

* **VBS application failure rate.** A sudden spike in devices failing VBS application indicates a Windows Update that changed VBS behavior, a policy conflict with another Intune configuration, or a driver incompatibility. Investigate.
* **Driver incompatibilities.** Specific drivers (legacy USB device drivers, older VPN clients, some specialty hardware drivers) are incompatible with HVCI. Symptom: user reports hardware malfunction after VBS deployment. Resolution: update the driver to a HVCI-compatible version or replace the hardware. Microsoft publishes an HVCI compatibility list.
* **Boot failures after UEFI Lock.** Rare but serious. A device with UEFI Lock applied and a BIOS issue (bad RAM, failing firmware) may fail to boot. Recovery requires physical intervention. Track any such events in the operations runbook; if the rate exceeds 1 in 1000 devices, investigate the underlying BIOS stability.
* **TPM replacement rate.** The forcing function of TPM 2.0 compliance surfaces every older device that needs replacement. Track the rate; expect a one-time cost as the fleet cycles through older hardware, then steady-state as hardware refresh cycles match the compliance requirement.
* **Credential theft attempts post-deployment.** With Credential Guard active, attacker tooling for PRT and cached credential extraction fails. Alert on any attempted extraction (visible in Defender for Endpoint Plan 2 telemetry, or via Sysmon if deployed). Zero attempts is suspicious; attackers continue to try extraction even on protected devices, so a consistent zero means the detection is not working.

## Rollback

Rollback of the Endpoint Security profile is complicated by UEFI Lock: devices that have UEFI Lock applied cannot have VBS disabled through policy alone. The rollback sequence:

1. Remove the policy assignment (stops new devices from receiving the policy)
2. For UEFI-locked devices, use Microsoft's DG Readiness tool with the DisableCredentialGuard flag; run once per device. Requires physical access.
3. UEFI-locked VBS can be disabled only through UEFI firmware reset and specific vendor procedures.

Full rollback requires deliberate planning for each affected device. Do not deploy UEFI Lock unless the organization is committed to VBS and Credential Guard indefinitely.

For a limited rollback (excluding a specific device group from the profile while keeping others), update the policy assignment to exclude the specific group. The devices in the excluded group continue running VBS until their UEFI Lock is explicitly disabled; they remain protected but are removed from the policy's reporting scope.

```powershell
./10-Disable-AccountProtectionProfile.ps1 -Reason "Documented reason" -ExcludeGroup "Specific-Group-Name"
```

## References

* Microsoft Learn: [How Credential Guard works](https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/)
* Microsoft Learn: [Credential Guard requirements](https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/credential-guard-requirements)
* Microsoft Learn: [Virtualization-based Security and HVCI](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity)
* Microsoft Learn: [Deploy Credential Guard using Intune](https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/credential-guard-manage)
* Microsoft Learn: [Trusted Platform Module technology overview](https://learn.microsoft.com/en-us/windows/security/hardware-security/tpm/trusted-platform-module-overview)
* Microsoft Learn: [HVCI compatible driver list](https://learn.microsoft.com/en-us/windows-hardware/test/hlk/testref/driver-compatibility-with-device-guard)
* M365 Hardening Playbook: [VBS and Credential Guard not enforced via Intune](https://github.com/pslorenz/m365-hardening-playbook/blob/main/device-security/vbs-credential-guard-not-enforced.md)
* M365 Hardening Playbook: [TPM 2.0 not enforced as device compliance requirement](https://github.com/pslorenz/m365-hardening-playbook/blob/main/device-security/tpm-not-required-in-compliance.md)
* MITRE ATT&CK: [T1003.001 OS Credential Dumping: LSASS Memory](https://attack.mitre.org/techniques/T1003/001/)
* CIS Microsoft 365 Foundations Benchmark v4.0: Windows hardware security recommendations
* NIST CSF 2.0: PR.DS-06, PR.AC-04, PR.IP-01, DE.CM-07
