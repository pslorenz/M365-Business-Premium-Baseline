# 26 - Message Encryption and Communication Compliance

**Category:** Data Protection (cross-categorized; message encryption is data-in-transit, communication compliance is behavioral)
**Applies to:**
* **Plain Business Premium:** Basic Office Message Encryption only (encrypt email to external recipients). No branded templates, no Advanced features.
* **+ Defender Suite:** Same as Plain BP.
* **+ Purview Suite:** OME Advanced (custom branding, expiration, revocation) and Communication Compliance.
* **+ Defender & Purview Suites:** Full OME Advanced and Communication Compliance.
* **+ EMS E5:** Basic OME.
* **M365 E5:** Full OME Advanced and Communication Compliance with Administrative Unit scoping.

**Prerequisites:**
* [11 - Anti-Phishing and Anti-Malware Policies](../defender-for-office/11-anti-phish-anti-malware.md) completed
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed
* [21 - Sensitivity Labels Baseline](../data-protection/21-sensitivity-labels-baseline.md) recommended for label-triggered encryption

**Time to deploy:** 3 to 4 hours active work; Communication Compliance adds 2 to 3 hours for policy and reviewer setup
**Deployment risk:** Medium. Encryption templates change how recipients experience mail. Communication Compliance produces reviewable content that needs HR and legal oversight before deployment.

## Purpose

This runbook deploys two capabilities that sit adjacent to each other in Purview but serve distinct functions. Message encryption protects email content in transit and at rest when it leaves the tenant; the recipient sees an encrypted message that requires authentication to read rather than cleartext delivered to wherever their mail is stored. Communication Compliance monitors email and Teams content for inappropriate patterns (harassment, regulated information disclosure, confidential content in inappropriate channels) and routes matches to designated reviewers for action. The first control addresses external threat: an attacker who intercepts email cannot read it. The second control addresses internal threat: an employee who sends harassing messages, leaks confidential information, or violates regulatory communication requirements produces a reviewable audit trail with workflow for action.

The tenant before this runbook: external email moves as cleartext by the time it leaves Microsoft's infrastructure (TLS between servers, cleartext at rest on recipient mail servers). Employees can send sensitive content externally with no encryption beyond the default; recipients see the content as ordinary mail subject to whatever security their mail system has. Inappropriate communication patterns are invisible unless someone complains; the email is preserved by retention but nothing proactively surfaces concerns. A customer sends a complaint that an employee sent them harassing email; finding the email requires eDiscovery case creation.

The tenant after: users can encrypt email by typing "Encrypt" in the subject line or selecting an encryption option from Outlook. Three encryption templates are available: Encrypt Only (recipient authenticates, can forward as they choose), Do Not Forward (recipient authenticates, cannot forward or print), and a company-branded Confidential template. Sensitivity labels (if deployed from runbook 21) automatically apply encryption to Confidential and Highly Confidential content. External recipients who receive encrypted mail from the tenant authenticate through Microsoft's OME portal or through native Outlook integration if they have a Microsoft 365 tenant themselves.

Communication Compliance policies scan a sample of email and Teams content for configured patterns. Three baseline policies cover inappropriate content (offensive language, harassment, threatening messages), regulatory compliance (insider trading keywords for financial-services tenants, unauthorized disclosure patterns), and sensitive information (confidential content sent externally without encryption). Matches route to designated reviewers: HR compliance for harassment, security admin for regulatory compliance, data protection officer for sensitive information. Reviewers triage matches and take action: close as no issue, notify the sender, escalate to investigation, or preserve for legal matter.

## Prerequisites

* Global Administrator or Compliance Administrator role
* Company branding assets for OME Advanced (logo, color scheme, message text)
* HR and legal coordination for Communication Compliance policies (deployment touches employee monitoring, privacy, and workplace conduct)
* Designated reviewers for Communication Compliance:
  * HR compliance contact (for inappropriate content)
  * Security admin (for regulatory compliance)
  * Data protection officer or equivalent (for sensitive information)
* Decision on scope: tenant-wide monitoring, or department-specific (E5 Compliance only; Purview Suite applies tenant-wide)
* Retention policies (runbook 23) deployed; Communication Compliance preserves flagged content until review completes

## Target configuration

### Message encryption

**OME Baseline (all variants):**

* Office Message Encryption enabled
* Default encryption template: Encrypt Only
* Users can trigger encryption by typing "Encrypt" in the subject line

**OME Advanced (Purview Suite and above):**

* Company branding applied: logo, color scheme, introduction text, disclaimer
* Three encryption templates available:
  * **Encrypt Only:** recipient authenticates; can forward, copy, print, save
  * **Do Not Forward:** recipient authenticates; cannot forward, copy, print
  * **Company Confidential** (branded): recipient authenticates; cannot forward or print; expires after 30 days
* Revocation enabled: sender can revoke encrypted messages after sending

**Mail flow rules for automatic encryption:**

* Mail to external recipients containing "confidential" or "privileged" in subject: Encrypt Only
* Mail to external recipients with sensitivity label Confidential: Encrypt Only
* Mail to external recipients with sensitivity label Highly Confidential: Do Not Forward
* Mail marked with a specific header (e.g., `x-encryption: do-not-forward`): Do Not Forward

### Communication Compliance policies

**Policy 1: Inappropriate Content**

* **Scope:** All users (Exchange email, Teams chat, Teams channel messages)
* **Detection:** Built-in classifiers for offensive language, harassment, threats
* **Sample rate:** 10% (policy reviews a sample of messages; full sampling is available but produces high volume)
* **Reviewer:** HR compliance contact
* **Action when matched:** Route to reviewer; preserve content

**Policy 2: Regulatory Compliance**

* **Scope:** All users or specific groups (traders, executives, etc. for financial-services tenants)
* **Detection:** Built-in regulatory classifiers plus custom keyword dictionaries:
  * Insider trading terms (MNPI, material non-public information, embargo, earnings)
  * Gift and bribery terms (per organizational regulatory profile)
  * Money laundering terms (per regulatory profile)
* **Sample rate:** 100% for scoped users
* **Reviewer:** Security admin and compliance officer
* **Action when matched:** Route to reviewer; preserve content

**Policy 3: Sensitive Information Disclosure**

* **Scope:** All users, external recipients only
* **Detection:** Sensitive info types (credit cards, SSNs, PHI) sent to external recipients without encryption
* **Sample rate:** 100%
* **Reviewer:** Data protection officer
* **Action when matched:** Route to reviewer; alert sender; preserve content

### Reviewer workflow

For each policy, reviewers see:

* Match queue in the compliance portal
* Message content and context
* Pattern that triggered the match
* Available actions:
  * Close as no issue
  * Notify sender (email to the sender noting the match)
  * Escalate to investigation
  * Preserve for legal matter
  * Tag for pattern analysis

Review SLA: 72 hours for inappropriate content, 24 hours for regulatory compliance, 48 hours for sensitive information.

## Deployment procedure

### Step 1: Verify licensing

```powershell
./26-Verify-OMECCLicensing.ps1
```

The script reports OME baseline availability (all variants), OME Advanced availability (Purview Suite and above), and Communication Compliance availability (Purview Suite and above).

### Step 2: Enable OME baseline

```powershell
./26-Enable-OMEBaseline.ps1
```

The script enables Office Message Encryption if not already enabled. OME is typically enabled by default in newer tenants but may require explicit activation in older tenants.

### Step 3: Configure OME Advanced branding (Purview Suite and above)

```powershell
./26-Configure-OMEBranding.ps1 `
    -LogoPath "./company-logo.png" `
    -IntroductionText "This is a confidential message from Contoso." `
    -DisclaimerText "The information contained in this message is confidential and intended only for the named recipient." `
    -PrimaryColor "#0078D4"
```

The script applies organizational branding to the OME portal and encrypted message interface.

### Step 4: Deploy encryption templates

```powershell
./26-Deploy-EncryptionTemplates.ps1
```

The script creates the three templates: Encrypt Only, Do Not Forward, Company Confidential. The Company Confidential template includes the configured branding and 30-day expiration.

### Step 5: Deploy mail flow rules for automatic encryption

```powershell
./26-Deploy-EncryptionMailFlowRules.ps1
```

The script creates mail flow rules (transport rules) that apply encryption based on content or recipient patterns:

* Keyword in subject → Encrypt Only
* Sensitivity label Confidential → Encrypt Only
* Sensitivity label Highly Confidential → Do Not Forward
* Specific header → per header value

### Step 6: Deploy Communication Compliance policies (Purview Suite and above)

```powershell
./26-Deploy-CommComplianceInappropriateContent.ps1 -Reviewer "hr-compliance@contoso.com"
./26-Deploy-CommComplianceRegulatory.ps1 -Reviewer "security-admin@contoso.com"
./26-Deploy-CommComplianceSensitiveInfo.ps1 -Reviewer "dpo@contoso.com"
```

Each script creates the respective policy with the configured scope, detection settings, sample rate, and reviewer routing.

### Step 7: Configure reviewer permissions

```powershell
./26-Configure-CCReviewers.ps1 `
    -InappropriateReviewer "hr-compliance@contoso.com" `
    -RegulatoryReviewer "security-admin@contoso.com" `
    -SensitiveInfoReviewer "dpo@contoso.com"
```

The script grants reviewers the Communication Compliance Analyst or Investigator role as appropriate. Reviewers need the role to see flagged content.

### Step 8: Communicate to users

Before Communication Compliance policies become visible to users (through notifications and audit data), send a tenant-wide communication:

* Organizational policies on workplace communication
* What content may be flagged and why
* How flagged content is reviewed (reviewers, process, confidentiality)
* What users can expect if their content is flagged (notification, discussion, potential disciplinary action)
* Where to find the acceptable use policy and workplace conduct policy

This communication is required in most jurisdictions for employee monitoring disclosure.

### Step 9: Verify deployment

```powershell
./26-Verify-Deployment.ps1
```

### Step 10: Document the posture

Update the operations runbook:

* Encryption templates available and their meanings
* Automatic encryption triggers (mail flow rules)
* Communication Compliance policies and their scope
* Reviewer assignments
* Review SLA and escalation process
* User communication sent

## Automation artifacts

* `automation/powershell/26-Verify-OMECCLicensing.ps1` - License verification
* `automation/powershell/26-Enable-OMEBaseline.ps1` - Enable OME
* `automation/powershell/26-Configure-OMEBranding.ps1` - OME branding (Advanced)
* `automation/powershell/26-Deploy-EncryptionTemplates.ps1` - Create encryption templates
* `automation/powershell/26-Deploy-EncryptionMailFlowRules.ps1` - Automatic encryption triggers
* `automation/powershell/26-Deploy-CommComplianceInappropriateContent.ps1` - Inappropriate content policy
* `automation/powershell/26-Deploy-CommComplianceRegulatory.ps1` - Regulatory compliance policy
* `automation/powershell/26-Deploy-CommComplianceSensitiveInfo.ps1` - Sensitive info disclosure policy
* `automation/powershell/26-Configure-CCReviewers.ps1` - Reviewer role assignment
* `automation/powershell/26-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/26-Rollback-OMECC.ps1` - Reverts configuration

## Verification

### Configuration verification

```powershell
./26-Verify-Deployment.ps1
```

### Functional verification

1. **Manual encryption via subject keyword.** Send a test email from an internal account to an external recipient with "Encrypt" in the subject. Expected: message is encrypted; recipient receives encrypted message and authenticates to read.
2. **Label-driven encryption.** Apply the Confidential label to a message; send to an external recipient. Expected: mail flow rule applies Encrypt Only; recipient experiences encrypted delivery.
3. **Do Not Forward enforcement.** Send a Do Not Forward message to a test external recipient. Expected: recipient can read but cannot forward, print, or copy content.
4. **Inappropriate content detection.** Have a test user send a message containing deliberately inappropriate content (staged for testing). Expected: match appears in the reviewer's queue; content is preserved.
5. **Sensitive info disclosure detection.** Have a test user send a message containing test sensitive data externally. Expected: match appears in DPO's queue; content preserved.

## Additional controls (add-on variants)

### Additional controls with Purview Suite or E5 Compliance

**Communication Compliance trainable classifiers.** Purview Suite allows custom classifier training for organization-specific inappropriate patterns (slurs or pejoratives specific to the industry or regional language, internal code words for inappropriate activity). Train classifiers on labeled example content.

**Advanced OME templates.** Additional templates beyond the three baseline: Time-Limited Access, Specific Recipient Only, Internal Distribution. Configure per organizational needs.

**Revocation.** Senders can revoke encrypted messages after sending. Useful when a message was sent to the wrong recipient or contained an error. Does not revoke copies already opened by the recipient; limits future access.

### Additional controls with E5 Compliance (not in Purview Suite)

**Administrative Unit scoping.** E5 Compliance allows Communication Compliance policies to target specific AUs (stricter monitoring for trading floor, relaxed for general population). Purview Suite applies policies tenant-wide.

**Information Barriers integration.** E5 Compliance allows Communication Compliance to enforce information barriers (policy-defined user groups that cannot communicate with each other, e.g., investment banking vs. equity research for financial firms). Purview Suite does not include Information Barriers.

### Customer Key (customer-managed encryption keys)

Purview Suite includes Customer Key, which allows the organization to provide its own encryption keys for Microsoft 365 service encryption. This is distinct from OME (which encrypts specific messages); Customer Key encrypts the underlying mailbox, SharePoint, and OneDrive storage with customer-controlled keys. Appropriate for tenants with specific regulatory requirements (FIPS 140-2, certain financial regulations); unnecessary for most SMBs.

## What to watch after deployment

* **External recipient authentication friction.** First-time recipients of OME-encrypted mail experience authentication friction: they must create a one-time passcode, sign in with Microsoft 365, or sign in with a Google account. Some external contacts give up and ask for the content to be resent unencrypted. Plan for this experience in external communication.
* **Encryption template coverage.** Three templates cover common cases but cannot cover every scenario. Organizations with specific needs (regulatory expiration periods, particular rights configurations) may need additional templates or custom per-message handling.
* **Communication Compliance false positives.** Classifiers produce false positives at the 1-5% rate. Legitimate business discussion that uses language similar to harassment (discussing workplace concerns, negotiating contracts, debating policy) will produce matches. Reviewers need context to distinguish false positives; this is why the review workflow exists.
* **Reviewer workload.** A 10% sample rate for inappropriate content produces modest volume in tenants under 1000 users; larger tenants produce substantial queues. Dedicate reviewer time proportionate to tenant size. For SMBs without dedicated HR compliance capacity, consider a lower sample rate and tighter classifier tuning.
* **User surprise at monitoring disclosure.** Communication Compliance is a workplace monitoring capability. Employees who did not understand the monitoring scope may react negatively when they learn about it (through a flagged message notification, for example). The user communication in Step 8 is the difference between managed transparency and discovery surprise.
* **Regulatory classifier accuracy.** Microsoft's regulatory classifiers are trained on general industry patterns; they may not match a specific organization's regulatory terminology perfectly. Initial deployment produces both false positives (general business language matching) and false negatives (organization-specific patterns missed). Tune classifiers with custom keyword dictionaries over the first 90 days.
* **Encryption revocation timing.** OME Advanced revocation requires recipients to attempt to re-access the message; users who already have the message open remain able to read it. Revocation is useful but not instant.
* **Mail flow rule precedence.** Multiple mail flow rules with different encryption actions produce precedence questions. Test the combined effect of label-driven encryption, keyword-driven encryption, and manual user selection; the rule with higher priority wins. Document the precedence explicitly.

## Rollback

```powershell
./26-Rollback-OMECC.ps1 -Mode "CommComplianceOnly" -Reason "Documented reason"
```

Rollback modes:

* **CommComplianceOnly:** Removes Communication Compliance policies while preserving OME. Use when CC creates organizational friction but encryption is working correctly.
* **OMERulesOnly:** Removes automatic encryption mail flow rules while preserving OME baseline. Users can still manually encrypt with subject keyword.
* **Full:** Removes all policies and disables OME. Rarely appropriate; OME baseline is low-friction and high-value.

Historical Communication Compliance matches remain in the tenant per Purview retention; they are not removed by rollback.

## References

* Microsoft Learn: [Message encryption overview](https://learn.microsoft.com/en-us/purview/ome)
* Microsoft Learn: [Advanced Message Encryption](https://learn.microsoft.com/en-us/purview/ome-advanced-message-encryption)
* Microsoft Learn: [Learn about communication compliance](https://learn.microsoft.com/en-us/purview/communication-compliance)
* Microsoft Learn: [Create and manage communication compliance policies](https://learn.microsoft.com/en-us/purview/communication-compliance-policies)
* Microsoft Learn: [Encryption in Microsoft 365](https://learn.microsoft.com/en-us/purview/encryption)
* M365 Hardening Playbook: [External email sent cleartext](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/no-email-encryption.md) (pending)
* CIS Microsoft 365 Foundations Benchmark v4.0: Message encryption recommendations
* NIST CSF 2.0: PR.DS-02, DE.AE-02, DE.CM-03
