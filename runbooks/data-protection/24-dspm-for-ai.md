# 24 - Data Security Posture Management for AI

**Category:** Data Protection
**Applies to:**
* **Plain Business Premium:** Not available.
* **+ Defender Suite:** Not available. Defender for Cloud Apps (part of Defender Suite) provides shadow AI discovery; full DSPM for AI requires Purview.
* **+ Purview Suite:** Full DSPM for AI including Copilot activity monitoring, third-party AI interaction tracking, sensitive data detection in prompts and responses.
* **+ Defender & Purview Suites:** Full DSPM for AI with Defender for Cloud Apps integration for richer third-party AI visibility.
* **+ EMS E5:** Not available.
* **M365 E5:** Full DSPM for AI as Purview Suite.

**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed
* [20 - Microsoft Purview Data Loss Prevention Baseline](./20-dlp-baseline.md) recommended
* [21 - Sensitivity Labels Baseline](./21-sensitivity-labels-baseline.md) recommended

**Time to deploy:** 2 to 3 hours active work, plus 30 days observation before enforcement
**Deployment risk:** Low. DSPM for AI starts as a monitoring capability; enforcement actions are layered on top of monitoring after patterns are understood.

## Purpose

This runbook deploys Data Security Posture Management for AI, which provides visibility and control over how AI tools interact with organizational data. DSPM for AI is a Purview Suite capability (and M365 E5) that did not exist in the Microsoft security stack two years ago; Microsoft introduced it as Copilot and third-party generative AI became pervasive in business workflows. Where DLP catches sensitive data leaving through email or file shares, and sensitivity labels classify the data itself, DSPM for AI watches the specific channel that was not previously a category: the conversation between a user and an AI system. An employee pastes a customer contract into ChatGPT for summarization. A Copilot prompt asks "show me everyone's salaries"; Copilot returns the query results because the user has the access. A developer uses GitHub Copilot with proprietary source code in their IDE; the prompts and responses flow through the AI system's infrastructure.

The tenant before this runbook: AI usage is invisible. Copilot for Microsoft 365 is deployed (or not) with default behaviors; no organizational visibility into what prompts are being used, what data is referenced in prompts, or what responses contain. Third-party AI usage (ChatGPT, Gemini, Claude, Perplexity) happens in browsers and desktop apps with no organizational telemetry. When a data breach notification arrives claiming sensitive company data was shared with an external AI service, there is no way to verify or refute the claim from organizational logs.

The tenant after: DSPM for AI monitors Copilot activity across Microsoft 365 workloads (Word, Excel, PowerPoint, Outlook, Teams, SharePoint). Prompts containing sensitive data types (credit cards, SSNs, labeled Confidential content) are flagged. Responses containing oversharing (Copilot surfacing information the user should have but perhaps shouldn't have asked about) are flagged. Third-party AI interactions are discovered through Defender for Cloud Apps integration (requires Defender Suite + Purview Suite) with risk scoring and user counts. Alerts route to the security admin for review. Policy actions (DLP-style blocks in Copilot prompts, sensitivity label blocking of AI access to labeled content) are available after the monitoring baseline is established.

Two distinct AI surfaces need separate treatment:

* **First-party AI (Copilot for Microsoft 365).** Runs in Microsoft's tenant boundary. Subject to tenant data protection, Purview DLP, and sensitivity labels. Prompts and responses logged in Microsoft 365 audit. Cannot access content the user cannot access. Generally lower risk than third-party AI.
* **Third-party AI (ChatGPT, Gemini, Claude, Perplexity, various specialty AI tools).** Runs outside tenant boundary. Content shared with these services leaves organizational control. Discovery through network observation, Defender for Cloud Apps (when licensed), and endpoint monitoring. Governance options are limited to blocking at network or endpoint level.

DSPM for AI addresses both surfaces but with different enforcement paths: first-party AI gets policy-based control; third-party AI gets discovery and access control.

## Prerequisites

* Purview Suite or M365 E5 licensing
* Compliance Administrator or equivalent role
* Decision on Copilot deployment state: deployed for specific user groups, tenant-wide, or not yet deployed
* Decision on third-party AI posture: discovery-only, blocked at network, allow-listed specific tools, or blocked at endpoint
* Distribution list for AI-related alerts (typically the security admin or a dedicated AI governance contact)

## Target configuration

At completion, the tenant has:

### DSPM for AI baseline monitoring

* Copilot activity monitoring enabled across all supported workloads
* Sensitive info type detection in Copilot prompts and responses (credit cards, SSNs, passwords, custom types)
* Overshare detection in Copilot responses (when Copilot surfaces content the user rarely accesses)
* Risky prompt detection (prompts matching patterns indicative of attempted data exfiltration, jailbreak attempts, or policy evasion)
* Alert routing to security admin for high-severity activity

### Sensitivity label integration with Copilot

* Copilot cannot reference content labeled Highly Confidential in prompts from users outside the Highly Confidential access list
* Copilot responses referencing Confidential-labeled content require users to have access to the underlying content
* Labeled content behaves correctly when Copilot surfaces it in summaries or search

### Third-party AI visibility

* Defender for Cloud Apps catalog reviewed for AI applications in use (requires Defender Suite in addition to Purview Suite)
* Third-party AI usage tracked via endpoint telemetry and network signals
* High-risk AI applications identified and assessed for business necessity
* Access decision documented: allow, allow with DLP, block

### DLP integration with AI

* DLP policy (from runbook 20) extended with AI-specific conditions: prompts containing sensitive info types are flagged or blocked
* Policy tips in Copilot warn users when they attempt to include sensitive data in prompts
* Audit events capture prompt content for investigation

## Deployment procedure

### Step 1: Verify licensing and prerequisites

```powershell
./24-Verify-DSPMAILicensing.ps1
```

The script verifies Purview Suite or M365 E5 licensing, Copilot deployment state, and Defender for Cloud Apps availability (for third-party AI visibility).

### Step 2: Enable DSPM for AI baseline

```powershell
./24-Enable-DSPMAI.ps1
```

The script enables the DSPM for AI feature in the Purview compliance portal. On first enablement, a baseline monitoring policy is created covering Copilot activity across Microsoft 365 applications. The policy operates in discovery mode initially; no enforcement.

### Step 3: Deploy sensitive content detection in prompts

```powershell
./24-Deploy-PromptSensitiveContentRules.ps1 `
    -NotificationEmail "ai-governance@contoso.com" `
    -Mode "Audit"
```

The script creates detection rules that identify sensitive information types in Copilot prompts: credit cards, SSNs, passwords, and any custom sensitive info types from runbook 20. Initial mode is Audit (produces alerts without blocking).

### Step 4: Configure sensitivity label integration with Copilot

```powershell
./24-Configure-CopilotLabelIntegration.ps1
```

The script ensures that Copilot respects sensitivity label access controls. Users cannot ask Copilot about content they do not have access to; Copilot responses that would include Highly Confidential content are blocked for users outside the access list. This is a configuration verification rather than a new policy; the behavior is built into Copilot and labeled content, but needs to be validated after labels are deployed.

### Step 5: Review third-party AI usage (requires Defender for Cloud Apps)

```powershell
./24-Review-ThirdPartyAI.ps1 -LookbackDays 30
```

The script queries Defender for Cloud Apps for AI application usage in the past 30 days. Output includes:

* AI applications in use
* User count per application
* Session count per application
* Risk score per application
* Data upload patterns (if endpoint telemetry is available)

Review the output with business stakeholders. Each discovered AI application warrants a decision: sanction (allow with DLP), restrict (allow but monitor), or block.

### Step 6: Deploy third-party AI governance (variant-dependent)

For tenants with Defender Suite in addition to Purview Suite:

```powershell
./24-Deploy-ThirdPartyAIGovernance.ps1 `
    -AllowedAIApps @("Microsoft Copilot","GitHub Copilot") `
    -RestrictedAIApps @("ChatGPT","Gemini","Claude","Perplexity") `
    -BlockedAIApps @()
```

The script configures Defender for Cloud Apps policies to:

* Allow specified AI applications (standard enterprise AI tools)
* Restrict specified applications (require sign-in with organizational identity, monitor activity)
* Block specified applications (network-level block at cloud proxy)

For tenants without Defender for Cloud Apps, third-party AI governance falls back to endpoint-level blocking through Intune or web content filtering (runbook 29, pending).

### Step 7: Monitor for 30 days

```powershell
./24-Monitor-AIActivity.ps1 -LookbackDays 30
```

Report covers:

* Copilot prompt volume and frequency by user
* Sensitive content detection events in prompts
* Overshare events (Copilot surfacing rarely-accessed content)
* Third-party AI usage changes
* Blocked/restricted AI application activity

Review weekly for the first month. Common tuning:

* Users legitimately processing sensitive data through Copilot (HR asking Copilot to summarize employee feedback; finance asking Copilot to extract data from invoices) produce matches that should be acknowledged as legitimate
* Departments with specific AI tool needs (engineering with GitHub Copilot, marketing with content generation AI) need tool-specific policies
* Prompt patterns indicating attempted policy evasion (users trying to get Copilot to reveal content they should not access) warrant security review

### Step 8: Transition to enforcement mode

After 30 days of observation, transition the prompt sensitive content rules to enforcement:

```powershell
./24-Transition-AIEnforcement.ps1 -Mode "Block"
```

In Block mode, Copilot prompts containing sensitive data are blocked before Copilot processes them. The user sees a policy tip explaining the block and the policy that applies.

Hard block without override is appropriate for the most sensitive categories (SSN, credit card); block with override is appropriate for others (confidential business content where a user may have legitimate need).

### Step 9: Document the AI governance posture

Update the operations runbook:

* AI applications sanctioned for organizational use
* Restricted or blocked applications
* DLP integration posture
* Sensitivity label access controls for AI
* Alert routing and review cadence

## Automation artifacts

* `automation/powershell/24-Verify-DSPMAILicensing.ps1` - License and prerequisite check
* `automation/powershell/24-Enable-DSPMAI.ps1` - Enables DSPM for AI feature
* `automation/powershell/24-Deploy-PromptSensitiveContentRules.ps1` - Prompt detection rules
* `automation/powershell/24-Configure-CopilotLabelIntegration.ps1` - Label integration verification
* `automation/powershell/24-Review-ThirdPartyAI.ps1` - Third-party AI usage report
* `automation/powershell/24-Deploy-ThirdPartyAIGovernance.ps1` - Third-party AI policies (Defender for Cloud Apps)
* `automation/powershell/24-Monitor-AIActivity.ps1` - Activity monitoring report
* `automation/powershell/24-Transition-AIEnforcement.ps1` - Mode transition
* `automation/powershell/24-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/24-Rollback-DSPMAI.ps1` - Reverts configuration

## Verification

### Configuration verification

```powershell
./24-Verify-Deployment.ps1
```

### Functional verification

1. **Sensitive content detection in prompt.** Send a Copilot prompt containing a test credit card number. Expected: audit event logged; in Block mode, Copilot declines with policy explanation.
2. **Label access enforcement.** As a user outside the Highly Confidential access list, ask Copilot about content that is labeled Highly Confidential. Expected: Copilot cannot reference the content in its response.
3. **Third-party AI discovery.** Verify the Defender for Cloud Apps discovery output shows AI applications that are in use. New applications appearing should trigger review.
4. **Overshare detection.** Simulate a prompt that would cause Copilot to surface rarely-accessed content (requires test data setup). Expected: alert to AI governance contact.

## Additional controls (add-on variants)

### Additional controls with Defender Suite integration

Defender for Cloud Apps (part of Defender Suite) adds:

* Automatic discovery of third-party AI applications through endpoint, firewall, and proxy telemetry
* Risk scoring for each AI application (based on Microsoft's SaaS security catalog)
* Session control for approved AI apps (step-up authentication, download restrictions, copy restrictions)
* Real-time policy enforcement (block specific file types from upload to specific AI services)

For tenants with Purview Suite alone, third-party AI governance is limited to discovery and blunt blocking; Defender for Cloud Apps adds session-level control.

### Additional controls with E5 Compliance (not in Purview Suite)

**Administrative Unit scoping.** E5 Compliance allows DSPM for AI policies to target specific AUs (e.g., stricter enforcement for Finance department, looser for Marketing). Purview Suite applies policies tenant-wide.

### Copilot licensing and DSPM

DSPM for AI monitoring applies to Copilot for Microsoft 365 usage, which requires separate Copilot licensing ($30/user/month as of 2026). Tenants without Copilot licenses will have little Copilot activity to monitor; the DSPM for AI deployment is primarily forward-looking in that case.

Third-party AI monitoring (through Defender for Cloud Apps) does not depend on Copilot licensing.

## What to watch after deployment

* **Copilot prompt volume accumulation.** Audit events accumulate quickly in organizations with heavy Copilot use. Plan storage and review capacity accordingly.
* **False positive prompts.** Legitimate business use of Copilot in HR, legal, and compliance functions routinely includes sensitive data in prompts. Tune the policies to accept these patterns while catching anomalies.
* **Third-party AI evolution.** New AI applications appear monthly. The Defender for Cloud Apps catalog stays current but organizations may encounter AI tools that were not in the catalog at review time. Reprocess the discovery output monthly to catch new applications.
* **Shadow AI through personal accounts.** Users signing into ChatGPT with personal accounts on managed devices bypass tenant-level telemetry. Endpoint monitoring and device-level web content filtering catch this; Defender for Cloud Apps alone does not.
* **Copilot versus third-party AI tradeoff.** Stricter governance on third-party AI without offering Copilot as an alternative often produces worse outcomes (users use AI tools despite restrictions, and choose more easily-accessible third-party options). If third-party AI is blocked, ensure Copilot or similar sanctioned alternative is available.
* **Prompt content as audit evidence.** DSPM for AI captures prompt content in audit events. This is useful for investigation and compliance but creates a sensitive data repository in the audit log; prompts containing passwords, personal information, or confidential content are preserved in the audit system. Treat the audit system with appropriate access controls.

## Rollback

```powershell
./24-Rollback-DSPMAI.ps1 -Reason "Documented reason"
```

Rollback removes the DSPM for AI policies but does not remove historical audit data. Audit events about past Copilot activity remain queryable until audit retention expires.

## References

* Microsoft Learn: [Data Security Posture Management for AI](https://learn.microsoft.com/en-us/purview/ai-microsoft-purview)
* Microsoft Learn: [Considerations for deploying Microsoft Purview AI Hub and data security](https://learn.microsoft.com/en-us/purview/ai-microsoft-purview-considerations)
* Microsoft Learn: [Defender for Cloud Apps for generative AI applications](https://learn.microsoft.com/en-us/defender-cloud-apps/generative-ai-apps)
* Microsoft Learn: [Copilot data protection and sensitivity labels](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-data-protection)
* Microsoft Tech Community: [New security and compliance add-ons for Microsoft 365 Business Premium](https://techcommunity.microsoft.com/blog/microsoft-security-blog/introducing-new-security-and-compliance-add-ons-for-microsoft-365-business-premi/4449297)
* M365 Hardening Playbook: [No AI governance controls](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/no-ai-governance.md) (pending)
* NIST AI Risk Management Framework
* NIST CSF 2.0: PR.DS-05, DE.AE-02, DE.CM-07
