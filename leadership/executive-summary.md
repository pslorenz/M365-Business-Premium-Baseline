# Executive Summary: Microsoft 365 Business Premium Security Baseline

This document is written for MSP leadership and IT leadership making decisions about Microsoft 365 security posture, licensing, and tooling. It summarizes what the baseline deploys, what it costs in time and licensing, and how it compares to the alternatives.

The technical runbooks in this repository describe exactly what and how. This document describes why.

## The problem

Microsoft 365 Business Premium is a capable security product that most SMBs do not use as such. The default tenant configuration out of the box in 2026 is materially better than it was three years ago, but a default configuration is not a secure configuration. Security Defaults is a baseline, not a target. The controls Business Premium actually includes - Intune device compliance, Conditional Access, Defender for Office 365 Plan 1 anti-phishing, Unified Audit Log ingestion - are capable of defending against the attacks that are actually hitting SMBs. They are also rarely deployed to the level where they defend against those attacks.

The practical result in an incident is that an SMB customer pays Microsoft for Business Premium, paid an MSP to manage Business Premium, and still experienced a phishing-to-tenant-compromise incident that Business Premium was technically equipped to prevent. The failure is configuration, not capability.

This baseline helps close that gap. It specifies what a correctly-configured Business Premium tenant looks like and provides the deployment automation to get any tenant to that state.

NOTE ON COMPLETENESS: this is and probably forever will be a work in progress and is not a substitute for research and generally knowing the tools you manage.

## What the baseline delivers

A tenant that has completed the phase 1 deployment of this baseline has:

**A fully-configured identity posture.** Two cloud-only break glass accounts that work and are tested annually. Dedicated admin accounts separated from daily-driver accounts. Legacy authentication blocked. Security Defaults disabled with a complete Conditional Access policy stack enforcing MFA, blocking legacy auth, requiring compliant devices, and filtering sign-ins by country. For tenants with an add-on (Defender Suite, E5 Security, or EMS E5), Privileged Identity Management in place for all tier-zero roles with approval workflows and Identity Protection policies enforcing on risky sign-ins and compromised users.

**Device compliance enforcement that works.** Intune compliance policies that actually require meaningful configuration (BitLocker, TPM 2.0, Secure Boot, current OS version, Credential Guard and VBS enforced). Conditional Access policies that check device compliance before granting access to Microsoft 365 resources. Attack surface reduction rules deployed. BYOD device support through app protection policies for tenants that allow BYOD.

**Email protection that matches commodity attack patterns.** Anti-phishing policies tuned for impersonation protection. Safe Links and Safe Attachments configured with sensible defaults. DKIM enabled and DMARC policy managed. For tenants with the add-on, Plan 2 features enabled including dynamic Safe Attachment delivery, time-of-click URL scanning, and Teams integration.

**Audit and alerting that produce actionable signal.** Unified Audit Log ingestion verified. Diagnostic settings routing Entra logs, Office activity, and risk events to a monitored destination (Sentinel, Defender XDR, or a Log Analytics workspace). Alert rules on break glass sign-in, PIM tier-zero activation, new high-privilege consent grants, and other high-signal events. An MSP watching the configured destinations sees an intrusion in hours, not weeks.

**Operational runbooks for ongoing maintenance.** Monthly, quarterly, and annual checklists that keep the tenant at baseline. Drift happens; the operational cadence catches it.

## What it costs

Deployment time: roughly 2 to 5 working days per tenant for an MSP technician running the automation artifacts, depending on the size of the tenant and the amount of existing configuration that needs to be consolidated. Greenfield tenants are faster than tenants that have accumulated configuration from previous administrators. Day one is the deployment itself; subsequent days are observation of the Conditional Access policies in report-only mode before enforcement.

Ongoing maintenance: roughly 2 to 4 hours per month per tenant for monthly review, 8 hours per quarter per tenant for quarterly review, 16 hours per year per tenant for annual review. For an MSP managing 20 customer tenants, that is roughly 80 to 120 hours of tenant maintenance per month, plus the shared capacity for responding to alerts and triaging incidents. I'm working on the automations for this, but that may take a while.

Licensing: the baseline works under plain Business Premium. The add-ons (Defender Suite, E5 Security, EMS E5) enable additional controls that the baseline documents clearly. The Defender Suite add-on at roughly $10 per user per month is the price-efficient path to the advanced controls for SMBs; see the [Variant Matrix](../reference/variant-matrix.md) for the capability comparison.

Third-party tool licensing: the baseline itself requires no third-party tools. Many MSPs deploy third-party multi-tenant management tools (Inforcer, CIPP, Rewst, Augmentt) to operate fleets; the baseline works with or without those tools. See [Tools in the Market](./tools-in-market-comparison.md) for the honest comparison.

## What it does not do

The baseline is explicit about its limits. A realistic framing for leadership:

**The baseline does not prevent all attacks.** A sophisticated adversary with novel tooling will find paths the baseline does not close. Nation-state actors, supply-chain attacks, and zero-day exploits are not addressed by configuration alone. The baseline stops the commodity attacks that constitute the overwhelming majority of actual SMB incidents: phishing, credential stuffing, illicit consent grants, and initial-access malware delivery.

**The baseline does not replace a security operations function.** Alerts fire into a destination; someone still has to triage them. The baseline's operations runbooks describe what to look for, but an organization without 24/7 monitoring capability benefits from a SOC-as-a-service partner (Huntress, Blumira, BHIS, or similar). The baseline produces actionable signal; the SOC function actually acts on it.

**The baseline does not cover every M365 workload.** Phase 1 covers identity, device compliance, and Defender for Office 365 Plan 1 protections. Exchange Online mail flow hardening beyond DfO, Purview data loss prevention and sensitivity labels, Power Platform governance, and Copilot configuration are out of scope for phase 1 and will be addressed in subsequent phases.

**The baseline does not replace thinking.** Every tenant has specifics: users who travel to unusual countries, line-of-business applications with legacy authentication requirements, partner relationships with unusual sharing patterns. The baseline provides the target state and the automation to reach it; applying the baseline to a specific tenant requires reading the runbooks, understanding the tradeoffs, and making organization-specific decisions. An MSP that deploys the baseline by clicking "run all scripts" on every tenant will produce incidents the baseline was supposed to prevent.

## Why this baseline exists

Two observations drove the decision to write it:

**Observation one: the market has several products claiming to be the answer and none of them are.** CIS publishes a detailed benchmark that is thorough but not organized for deployment. ScubaGear from CISA is an assessment tool, not a deployment tool. Microsoft's own recommendations are scattered across dozens of Learn articles and secure-score improvement actions. Third-party multi-tenant tools ship opinionated defaults that are often weaker than what a thoughtful baseline would deploy because they want to limit support needs. The gap was a deployment-oriented, Business-Premium-specific, MSP-usable reference that named tradeoffs honestly. This baseline fills that gap.

**Observation two: the configuration knowledge exists inside experienced MSPs but is not shared.** MSPs that deploy Business Premium well have built their own internal baselines over years of trial and error. Those internal baselines are not published because they are a competitive differentiator. The result is that new MSPs and new practitioners reinvent the baseline badly, or they defer to commercial tools that promise to handle it. Publishing a reference baseline raises the floor for the industry without substantially affecting the ceiling; the MSPs with deep internal expertise continue to outperform a generic baseline, and the MSPs without that expertise have somewhere to start.

The baseline is open-source for the same reason. Gatekeeping configuration knowledge does not improve SMB security; publishing it does.

## How to decide whether to adopt the baseline

The baseline is useful if:

* You are an MSP deploying new Business Premium tenants and want a standardized starting posture
* You are an MSP standardizing existing customer tenants and need a target state for drift remediation
* You are internal IT at a company with Business Premium and want a concrete reference for how to configure the tenant
* You are evaluating third-party baseline tools and need a reference for what good looks like

The baseline is not useful if:

* You are on Microsoft 365 E5 and want a configuration specifically optimized for E5's additional capabilities (phase 1 does not cover the E5-only controls)
* You need a compliance-attested baseline (CIS, CMMC, HIPAA); this baseline informs compliance work but does not itself claim conformance
* You are looking for a product that deploys and manages itself with no expertise required (no such product exists; treat anything that claims to be one with caution)

## Next steps

**For leadership:** read [Tools in the Market](./tools-in-market-comparison.md) for the honestly opinionated comparison of third-party options. Review the [Variant Matrix](../reference/variant-matrix.md) to decide which licensing variant the organization or customer base is targeting. Commit to the staffing model that supports deploying and maintaining the baseline; this is not a "run it once and forget" artifact.

**For technical leadership:** read the first two runbooks ([Tenant initial configuration and break glass](../runbooks/identity-and-access/01-tenant-initial-and-break-glass.md) and [Conditional Access baseline policy stack](../runbooks/conditional-access/02-ca-baseline-policy-stack.md)) to understand the pattern. Walk through the automation artifacts to confirm they match the organization's change-control requirements.

**For operators:** deploy the baseline to a test tenant first. Automation is opinionated; run it against a disposable environment and confirm the resulting configuration matches intent before deploying to a customer tenant.
