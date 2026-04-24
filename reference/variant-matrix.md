# Licensing Variant Matrix

This document maps each control in the baseline to the Business Premium licensing variant(s) where it is available. Consult this matrix first if you are unsure which sections of the baseline apply to your licensing state.

## Variants covered by this baseline

| Variant | SKU part numbers | Adds to plain Business Premium |
|---|---|---|
| **Plain Business Premium** | `SPB` | (baseline) |
| **+ Defender Suite for Business Premium** | `SPB` + `Microsoft_Defender_Suite_for_SMB` | Entra ID P2, Defender for Office 365 P2, Defender for Endpoint P2, Defender for Identity, Defender for Cloud Apps |
| **+ Purview Suite for Business Premium** | `SPB` + `Microsoft_Purview_Suite_for_SMB` | Insider Risk Management, Information Protection (sensitivity labels), DLP, Message Encryption, Customer Key, Communication Compliance, DSPM for AI, Records and Data Lifecycle Management, eDiscovery Premium, Audit Premium, Compliance Manager |
| **+ Defender & Purview Suites for Business Premium** | `SPB` + `Microsoft_Defender_Suite_for_SMB` + `Microsoft_Purview_Suite_for_SMB` (or combined SKU) | Union of the two suites above. Microsoft bundles this at a discount compared to buying both separately. |
| **+ E5 Security (legacy)** | `SPB` + `IDENTITY_THREAT_PROTECTION` | Functionally equivalent to Defender Suite for the controls this baseline covers. Legacy path; new tenants should use Defender Suite. |
| **+ EMS E5** | `SPB` + `EMSPREMIUM` | Entra ID P2 only. Does not include Defender for Office 365 P2 or Defender for Endpoint P2. |
| **M365 E5 (full)** | `SPE_E5` | All of the above plus E5 Compliance (which includes Administrative Unit scoping for DLP and Information Protection, endpoint DLP, and a handful of capabilities not included in Purview Suite). |

## About the Business Premium add-ons

The **Defender Suite for Business Premium** and **Purview Suite for Business Premium** add-ons launched in September 2025 at $10/user/month each, with the combined bundle at $15/user/month. They bring enterprise-grade Defender and Purview capabilities to SMBs at a Business-Premium-scale price point.

The Purview Suite initially launched with several capability gaps compared to full E5 Compliance (Compliance Manager limitations, missing Adaptive Protection in Insider Risk Management, missing premium assessment templates). Microsoft rolled out fixes across October and November 2025, bringing Purview Suite to functional parity with E5 Compliance for most capabilities.

**The material gaps that remain (as of 2026):**

* **Administrative Unit scoping** for DLP and Information Protection policies. Purview Suite applies policies tenant-wide; E5 Compliance supports scoping to specific administrative units. For pilot rollouts, use DLP enforcement mode "test" rather than AU scoping.
* **Endpoint DLP** (device control, clipboard monitoring, USB blocking). Requires E5 Compliance. Not in Purview Suite.
* **Privileged Access Management** (PAM) for Exchange operations. Requires E5 Compliance.

The Defender Suite for Business Premium and the legacy E5 Security add-on are functionally equivalent for the controls this baseline covers. Tenants with existing E5 Security assignments continue to work; new tenants should use Defender Suite.

## How to check which variants you have

```powershell
Connect-MgGraph -Scopes "Organization.Read.All"

$tenantSkus = Get-MgSubscribedSku | Where-Object { $_.PrepaidUnits.Enabled -gt 0 } |
    Select-Object -ExpandProperty SkuPartNumber

[PSCustomObject]@{
    HasBusinessPremium    = "SPB" -in $tenantSkus
    HasDefenderSuite      = "Microsoft_Defender_Suite_for_SMB" -in $tenantSkus
    HasPurviewSuite       = "Microsoft_Purview_Suite_for_SMB" -in $tenantSkus
    HasE5Security_Legacy  = "IDENTITY_THREAT_PROTECTION" -in $tenantSkus
    HasEMSE5              = "EMSPREMIUM" -in $tenantSkus
    HasEntraP2Standalone  = "AAD_PREMIUM_P2" -in $tenantSkus
    HasM365E5             = "SPE_E5" -in $tenantSkus
    HasE5ComplianceOnly   = "INFORMATION_PROTECTION_COMPLIANCE" -in $tenantSkus
}
```

The deployment scripts in `automation/powershell/` read this information at runtime and apply the variant-specific configuration automatically. The matrix in this document is the reference for understanding what each variant does and does not include.

## Controls by area

### Identity and access

| Control | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | + EMS E5 | M365 E5 |
|---|---|---|---|---|---|---|
| Security Defaults disabled, CA in place | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Break glass accounts | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Dedicated admin accounts (tier separation) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| PIM for tier-zero roles | Not available | ✓ | Not available | ✓ | ✓ | ✓ |
| PIM approval workflow | Not available | ✓ | Not available | ✓ | ✓ | ✓ |
| Access reviews for privileged roles | Not available | ✓ | Not available | ✓ | ✓ | ✓ |
| Entra ID Governance lifecycle workflows | Not available | ✓ | Not available | ✓ | ✓ | ✓ |

### Conditional Access

| Control | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | + EMS E5 | M365 E5 |
|---|---|---|---|---|---|---|
| CA policies (core set) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| MFA required for all users | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Named locations and country blocking | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Device compliance requirement | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Sign-in risk policy enforcement | Detection-only | ✓ | Detection-only | ✓ | ✓ | ✓ |
| User risk policy enforcement | Detection-only | ✓ | Detection-only | ✓ | ✓ | ✓ |
| Authentication context (step-up for admin portals) | Not available | ✓ | Not available | ✓ | ✓ | ✓ |
| Phishing-resistant MFA authentication strength | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

### Device compliance and endpoint

| Control | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | + EMS E5 | M365 E5 |
|---|---|---|---|---|---|---|
| Intune MDM enrollment | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Device compliance policies (Win, macOS, iOS, Android) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| App protection policies (MAM) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| VBS, Credential Guard, HVCI enforcement | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| BitLocker enforcement | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Defender for Endpoint | Plan 1 (Defender for Business) | Plan 2 | Plan 1 | Plan 2 | Plan 1 | Plan 2 |
| Attack surface reduction rules | Basic set (P1) | Full set (P2) | Basic set (P1) | Full set (P2) | Basic set (P1) | Full set (P2) |
| Web content filtering | Not available | ✓ | Not available | ✓ | Not available | ✓ |
| Advanced EDR and hunting | Not available | ✓ | Not available | ✓ | Not available | ✓ |
| Automated investigation and response | Not available | ✓ | Not available | ✓ | Not available | ✓ |
| Defender for Identity (on-prem AD integration) | Not available | ✓ | Not available | ✓ | Not available | ✓ |

### Defender for Office 365

| Control | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | + EMS E5 | M365 E5 |
|---|---|---|---|---|---|---|
| Anti-phishing policy | ✓ | ✓ (enhanced) | ✓ | ✓ (enhanced) | ✓ | ✓ (enhanced) |
| Anti-malware and anti-spam | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Safe Attachments (email, SPO, OneDrive, Teams) | ✓ | ✓ (dynamic delivery) | ✓ | ✓ (dynamic delivery) | ✓ | ✓ (dynamic delivery) |
| Safe Links (email, Office clients, Teams) | ✓ (email, Office) | ✓ (+ Teams, URL detonation) | ✓ (email, Office) | ✓ (+ Teams, URL detonation) | ✓ (email, Office) | ✓ (+ Teams, URL detonation) |
| Attack Simulation Training | Not available | ✓ | Not available | ✓ | Not available | ✓ |
| Advanced Threat Explorer | P1 (real-time detections) | P2 (Threat Explorer) | P1 | P2 | P1 | P2 |
| Automated Investigation and Response | Not available | ✓ | Not available | ✓ | Not available | ✓ |
| DKIM signing and DMARC management | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

### Audit and alerting

| Control | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | + EMS E5 | M365 E5 |
|---|---|---|---|---|---|---|
| Unified Audit Log | ✓ (180 day retention) | ✓ (180 day retention) | ✓ (Audit Premium, up to 10 years) | ✓ (Audit Premium) | ✓ (180 day) | ✓ (Audit Premium) |
| Sign-in logs, audit logs, risk events export | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Sentinel ingestion (requires Sentinel licensing) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Defender XDR custom detections | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Risky user and sign-in events in audit | Detection | Full (with Identity Protection) | Detection | Full | Full | Full |

### Data protection (phase 2)

| Control | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | + EMS E5 | M365 E5 |
|---|---|---|---|---|---|---|
| DLP for Exchange, SharePoint, OneDrive, Teams | Basic | Basic | ✓ | ✓ | Basic | ✓ |
| DLP with Administrative Unit scoping | Not available | Not available | Not available | Not available | Not available | ✓ |
| Endpoint DLP (device control, clipboard, USB) | Not available | Not available | Not available | Not available | Not available | ✓ |
| Sensitivity labels (manual application) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Sensitivity labels with automatic labeling | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Sensitivity labels with encryption enforcement | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Retention policies (basic) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Records management and disposition | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Insider Risk Management | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Insider Risk Management with Adaptive Protection | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Message Encryption (OME) | Basic | Basic | ✓ (Advanced) | ✓ | Basic | ✓ (Advanced) |
| Communication Compliance | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| DSPM for AI (Copilot and third-party AI monitoring) | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Customer Key (customer-managed encryption keys) | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| eDiscovery Standard | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| eDiscovery Premium | Not available | Not available | ✓ | ✓ | Not available | ✓ |
| Compliance Manager | Basic | Basic | ✓ | ✓ | Basic | ✓ |

## Capability gaps that remain in Purview Suite vs. E5 Compliance

| Capability | Purview Suite for BP | E5 Compliance |
|---|---|---|
| Administrative Unit scoping for DLP and Information Protection | Not available | ✓ |
| Endpoint DLP (device control, USB, clipboard monitoring) | Not available | ✓ |
| Privileged Access Management for Exchange | Not available | ✓ |
| Information Barriers | Not available | ✓ |

For tenants needing these specific capabilities, the path is E5 Compliance or full M365 E5 rather than Purview Suite. For most SMBs without specific regulatory drivers for these capabilities, Purview Suite provides functional parity with E5 Compliance at a significantly lower per-user cost.

## What is not in any Business Premium variant

Controls covered in the broader CIS benchmark and in Microsoft's enterprise security posture that are not available under any Business Premium variant or add-on, for context:

* **Defender for Cloud** (Azure resource protection). Separate Azure-native product.
* **Defender for Servers** (server workload protection beyond the server OS variants of Defender for Endpoint). Licensed through Defender for Cloud at a per-server rate.
* **Microsoft Sentinel ingestion quota.** Sentinel is a pay-per-GB Azure resource. Defender Suite customers get some Sentinel benefit for Defender-sourced data; other ingestion requires separate Sentinel budget.
* **Azure AD Privileged Identity Management for Azure resources.** The Entra PIM that Defender Suite adds covers Entra directory roles. PIM for Azure subscription resources (resource roles) is a separate capability requiring Entra ID P2 standalone.

If any of these controls are required for the organization's compliance or threat model, the correct path is to upgrade licensing rather than to attempt to work around the gap with the Business Premium baseline.

## Licensing cost framing (indicative, verify current)

For MSP leadership comparing the variants, approximate US commercial pricing as of early 2026:

| Product | Per user per month |
|---|---|
| Business Premium | $22 |
| + Defender Suite for Business Premium | $10 |
| + Purview Suite for Business Premium | $10 |
| + Defender & Purview Suites for Business Premium | $15 |
| + E5 Security (legacy) | $12 |
| + EMS E5 | $15 |
| Upgrade Business Premium to M365 E5 | ~$35 additional |

The Defender & Purview Suites bundle at $15/user/month is the most cost-efficient path to near-E5 capability for SMBs. A 50-user tenant pays roughly $1,850/month for BP + combined bundle, compared to roughly $2,850/month for BP + M365 E5 upgrade. The capability gap between the combined bundle and full E5 is primarily Administrative Unit scoping, endpoint DLP, and Information Barriers; for most SMB threat models, the combined bundle is the right answer.

Pricing is subject to change. Consult current Microsoft pricing and your partner channel for authoritative numbers.

## References

* Microsoft Tech Community: [Introducing new security and compliance add-ons for Microsoft 365 Business Premium](https://techcommunity.microsoft.com/blog/microsoft-security-blog/introducing-new-security-and-compliance-add-ons-for-microsoft-365-business-premi/4449297)
* Microsoft Learn: [Compare Microsoft 365 Business Premium to Microsoft 365 Enterprise](https://www.microsoft.com/en-us/microsoft-365/business/compare-all-plans)
* Microsoft Learn: [Microsoft Entra licensing overview](https://learn.microsoft.com/en-us/entra/fundamentals/licensing)
* Microsoft Learn: [Defender for Office 365 feature matrix](https://learn.microsoft.com/en-us/defender-office-365/mdo-support-teams-about)
* Microsoft Learn: [Compare Defender for Endpoint plans](https://learn.microsoft.com/en-us/defender-endpoint/defender-endpoint-plan-1-2)
* Microsoft Learn: [Microsoft Purview Data Loss Prevention plan comparison](https://learn.microsoft.com/en-us/purview/dlp-licensing)
