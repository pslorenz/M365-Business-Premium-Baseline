# Microsoft 365 Business Premium Configuration Baseline

A prescriptive configuration baseline for Microsoft 365 Business Premium tenants, with explicit coverage of the Defender Suite, Purview Suite, combined Defender & Purview Suites, E5 Security (legacy), and EMS E5 add-ons. Written for MSP technicians deploying and standardizing tenants, MSP leadership evaluating tool and licensing decisions, and internal IT teams standing up a new Business Premium tenant with a deliberate security posture.

This baseline is a companion to the [M365 Hardening Playbook](https://github.com/pslorenz/m365-hardening-playbook). The playbook diagnoses what is broken in an existing tenant and walks through remediation. The baseline specifies what a correctly-configured tenant looks like and how to deploy it from scratch. A reader fixing problems reaches for the playbook; a reader building a standard reaches for the baseline.

## What this baseline is

A deployable target state for Microsoft 365 Business Premium, organized by deployment sequence. Each runbook produces a specific configured state, with prerequisites, procedure, and verification steps. Automation artifacts (PowerShell scripts, Conditional Access policy JSON, Intune configuration profiles) ship alongside the prose so that a tenant can be deployed by running the scripts rather than clicking through the portal.

The baseline covers the following licensing variants:

* **Plain Business Premium.** The majority of SMB tenants.
* **Business Premium + Defender Suite for Business Premium.** The September 2025 add-on that brings Entra ID P2 (PIM, Identity Protection), Defender for Office 365 Plan 2, Defender for Endpoint Plan 2, Defender for Identity, and Defender for Cloud Apps into Business Premium for $10 per user per month.
* **Business Premium + Purview Suite for Business Premium.** The September 2025 companion add-on that brings sensitivity labels with encryption, DLP across Teams, insider risk management, records management, DSPM for AI, premium audit, premium eDiscovery, and Compliance Manager for $10 per user per month.
* **Business Premium + Defender & Purview Suites.** Both add-ons bundled at $15 per user per month, roughly 68 percent savings vs. buying separately. The recommended path for mid-market SMBs (50 to 300 users).
* **Business Premium + E5 Security (legacy).** The older path to Defender Suite capability. Mechanically similar to Defender Suite with some licensing allocation differences. New customers should use Defender Suite.
* **Business Premium + EMS E5.** Adds Entra ID P2 only, not the Defender or Purview upgrades. Partial add-on; covered where applicable.
* **Microsoft 365 E5 (full).** All of the above plus E5 Compliance features (Administrative Unit scoping for DLP and Information Protection, endpoint DLP, Information Barriers, PAM for Exchange) that are not included in Purview Suite.

Content that applies to all variants is presented in the universal layer of each runbook. Content that depends on a specific add-on is isolated in a clearly-tagged add-on section near the end of the runbook, so readers on plain Business Premium read the universal content and skip the add-on sections without losing context.

## What this baseline is not

* **Not a checklist.** Every runbook has prerequisites, tradeoffs, and validation steps that need to be understood, not ticked off.
* **Not a marketing document.** Where Business Premium falls short of what a security-conscious organization would want, the baseline calls out the gap honestly and recommends the add-on path that closes it.
* **Not a replacement for the playbook.** The baseline documents target state. The playbook documents how to diagnose and remediate drift from target state. Both are needed.
* **Not a substitute for understanding.** MSPs using third-party baseline tools like Inforcer, CIPP, Rewst, or Augmentt benefit from knowing what the tools should be enforcing. The baseline is the reference for what good looks like. See the [Tools in the Market](./leadership/tools-in-market-comparison.md) document for a detailed comparison.

## Scope

Phase 1 covers identity, device compliance, Defender for Office 365 Plan 1 protections, and the audit and alerting foundation. These are the controls that together constitute a minimum-viable-secure Business Premium tenant. A tenant that has completed phase 1 deployment has the controls in place to defend against the most common attack patterns that hit SMBs: adversary-in-the-middle phishing, credential stuffing, illicit consent grants, and initial-access malware delivery via email.

**Phase 1 is complete** with 19 runbooks across identity and access, Conditional Access, device compliance, Defender for Office 365, audit and alerting, and operations.

**Phase 2 is in progress**, covering data protection (runbooks 20 to 26), endpoint and attack surface (runbooks 27 to 30), and operational maturity (runbooks 31 to 33). Data protection is complete (segments 8, 9, and the data protection portion of segment 10 cover runbooks 20-26); endpoint and attack surface is underway (runbooks 27 and 28 complete); remaining phase 2 segments are in active development.

Security operations content (incident response playbooks, BEC investigation, ransomware response, privileged access breach) will ship as a separate companion repository after phase 2 concludes. That content is scoped for incident responders rather than deployment engineers and belongs adjacent to the hardening playbook rather than inside the deployment baseline.

## Variant matrix

The full mapping of controls to licensing variants lives in [variant-matrix.md](./reference/variant-matrix.md). Consult it first if you are unsure which sections of the baseline apply to your licensing state.

High-level summary:

| Control area | Plain BP | + Defender Suite | + Purview Suite | + Defender & Purview | M365 E5 |
|---|---|---|---|---|---|
| Security Defaults off, CA MFA baseline | Full | Full | Full | Full | Full |
| Break glass accounts | Full | Full | Full | Full | Full |
| PIM for tier-zero roles | Not available | Full | Not available | Full | Full |
| Identity Protection risk policies | Not available | Full | Not available | Full | Full |
| Defender for Office 365 | Plan 1 | Plan 2 | Plan 1 | Plan 2 | Plan 2 |
| Defender for Endpoint | Plan 1 | Plan 2 | Plan 1 | Plan 2 | Plan 2 |
| Intune device compliance | Full | Full | Full | Full | Full |
| DLP (Exchange, SPO, OneDrive, Teams) | Basic | Basic | Full | Full | Full + AU scoping |
| Sensitivity labels with encryption | Not available | Not available | Full | Full | Full + endpoint |
| Insider Risk Management | Not available | Not available | Full | Full | Full |
| DSPM for AI | Not available | Not available | Full | Full | Full |
| eDiscovery Premium | Not available | Not available | Full | Full | Full |
| Audit log retention | 180 days | 180 days | 10 years (Premium) | 10 years | 10 years |

## Repository layout

```
m365-bp-baseline/
├── README.md                          This document
├── TEMPLATE.md                        Template for new runbooks
├── leadership/                        Executive summary, tools-in-market comparison
├── reference/                         Variant matrix and cross-reference documents
├── runbooks/
│   ├── identity-and-access/           Tenant initial config, break glass, admin separation, PIM
│   ├── conditional-access/            CA policy stack deployment
│   ├── device-compliance/             Intune enrollment, compliance policies, device CA enforcement
│   ├── defender-for-office/           Anti-phish, Safe Links, Safe Attachments, anti-malware
│   ├── audit-and-alerting/            UAL ingestion, Sentinel connector or Defender XDR custom detections
│   ├── data-protection/               DLP, sensitivity labels, external sharing, retention, DSPM for AI, insider risk, message encryption (phase 2)
│   ├── endpoint-and-attack-surface/   ASR rules, EDR tuning, web content filtering, macOS, BYOD (phase 2)
│   └── operations/                    Monthly, quarterly, annual review cadences
└── automation/
    ├── powershell/                    Deployment scripts per runbook
    └── ca-policies/                   Conditional Access policy JSON exports
```

## Runbook index

### Identity and access

* [Tenant initial configuration and break glass accounts](./runbooks/identity-and-access/01-tenant-initial-and-break-glass.md)
* [Admin account separation and tier model](./runbooks/identity-and-access/03-admin-account-separation.md)
* [PIM configuration (Defender Suite, E5 Security, EMS E5)](./runbooks/identity-and-access/04-pim-configuration.md)
* Planned: Entra Connect decision and hybrid identity posture

### Conditional Access

* [Conditional Access baseline policy stack](./runbooks/conditional-access/02-ca-baseline-policy-stack.md)
* [Named locations and travel exception workflow](./runbooks/conditional-access/05-named-locations-travel-exception.md)
* [Authentication context for admin portals (Defender Suite, E5 Security, EMS E5)](./runbooks/conditional-access/06-authentication-context-admin-portals.md)

### Device compliance

* [Intune enrollment strategy (Autopilot, user-driven, BYOD)](./runbooks/device-compliance/07-intune-enrollment-strategy.md)
* [Windows device compliance policy](./runbooks/device-compliance/08-windows-compliance-policy.md)
* [Mobile device compliance (iOS and Android)](./runbooks/device-compliance/09-mobile-compliance-policy.md)
* [VBS, Credential Guard, and TPM hardware enforcement](./runbooks/device-compliance/10-vbs-credential-guard-tpm.md)
* Planned: macOS device compliance policy
* Planned: App protection policies for BYOD (MAM without enrollment)

### Defender for Office 365

* [Anti-phishing and anti-malware policies](./runbooks/defender-for-office/11-anti-phish-anti-malware.md)
* [Safe Links and Safe Attachments](./runbooks/defender-for-office/12-safe-links-safe-attachments.md)
* [SPF, DKIM, and DMARC email authentication](./runbooks/defender-for-office/13-spf-dkim-dmarc.md)
* Planned: Anti-spam policy tuning
* Planned: Preset security policy strategy (Standard vs Strict)

### Audit and alerting

* [Unified Audit Log verification and retention](./runbooks/audit-and-alerting/14-ual-verification-retention.md)
* [Defender XDR and Sentinel baseline ingestion](./runbooks/audit-and-alerting/15-defender-xdr-sentinel-ingestion.md)
* [Alert rules for high-signal events](./runbooks/audit-and-alerting/16-alert-rules-high-signal.md)

### Operations

* [Monthly review checklist](./runbooks/operations/17-monthly-review.md)
* [Quarterly review checklist](./runbooks/operations/18-quarterly-review.md)
* [Annual review checklist](./runbooks/operations/19-annual-review.md)

### Data protection (phase 2)

* [Purview DLP baseline](./runbooks/data-protection/20-dlp-baseline.md)
* [Sensitivity labels baseline](./runbooks/data-protection/21-sensitivity-labels-baseline.md)
* [SharePoint and OneDrive external sharing controls](./runbooks/data-protection/22-external-sharing-controls.md)
* [Retention policies and records management](./runbooks/data-protection/23-retention-records-management.md)
* [Data Security Posture Management for AI](./runbooks/data-protection/24-dspm-for-ai.md)
* [Insider Risk Management](./runbooks/data-protection/25-insider-risk-management.md)
* [Message Encryption and Communication Compliance](./runbooks/data-protection/26-message-encryption-communication-compliance.md)

### Endpoint and attack surface (phase 2)

* [Attack surface reduction rules](./runbooks/endpoint-and-attack-surface/27-asr-rules.md)
* [Endpoint detection and response tuning](./runbooks/endpoint-and-attack-surface/28-edr-tuning.md)
* Planned: Web content filtering
* Planned: macOS device compliance policy
* Planned: App protection policies for BYOD (MAM without enrollment)

## How to use this baseline

**If you are deploying a new Business Premium tenant:** read the leadership executive summary first, consult the variant matrix to confirm which sections apply to your licensing, then work through the runbooks in the order listed. Automation artifacts in the `automation/` directory deploy the configuration described in each runbook; review the scripts before running them and run each in a test tenant first.

**If you are standardizing an existing MSP fleet:** the baseline is an example target state.  For each customer tenant, use the M365 Hardening Playbook to diagnose drift from baseline, then use the baseline's automation artifacts to deploy missing controls. The pairing of playbook (diagnostic) and baseline (prescriptive) is deliberate.

**If you are MSP leadership evaluating options:** read the [executive summary](./leadership/executive-summary.md) and [tools-in-market comparison](./leadership/tools-in-market-comparison.md). These cover the business case for the Defender Suite add-on, the honest assessment of third-party baseline tools, and the staffing implications of deploying and maintaining the baseline.

## Automation artifacts

Each runbook ships with at least one automation artifact:

* **PowerShell deployment scripts** (`automation/powershell/`) configure the tenant-level settings described in each runbook. Scripts are idempotent where possible; running a script against a tenant that already has the configuration applied produces no change. Scripts are variant-aware; the script reads the tenant's licensing and applies the variant-specific configuration automatically.
* **Conditional Access policy JSON** (`automation/ca-policies/`) contains exported Conditional Access policies in the Microsoft Graph JSON format, ready to be imported into a target tenant. Each JSON file has a header comment indicating which variant it requires.

Automation artifacts are opinionated. Review and understand them. I make typo's. You break a tenant, it is on you to fix it. They deploy the baseline's prescriptive configuration. Organizations with specific requirements that deviate from the baseline should fork the artifacts and modify them rather than disabling specific steps at runtime.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Use [TEMPLATE.md](./TEMPLATE.md) for new runbooks. Consistency is what makes this baseline useful across tenants.

## License

MIT. See [LICENSE](./LICENSE).

## Disclaimer

This baseline describes configuration for tenants you own or are authorized to administer under a GDAP relationship. Automation artifacts execute against live tenants and make real configuration changes. Run every script against a test tenant first. Pair on changes that touch tier-zero (Global Administrator, PIM, break glass, Conditional Access policies that apply to All users). Do not deploy the baseline to a customer tenant without the customer's documented authorization for each change.
