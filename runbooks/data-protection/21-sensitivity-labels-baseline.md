# 21 - Sensitivity Labels Baseline

**Category:** Data Protection
**Applies to:**
* **Plain Business Premium:** Manual label application only. No encryption enforcement, no automatic labeling.
* **+ Defender Suite:** Same as Plain BP; sensitivity labels are not part of Defender Suite.
* **+ Purview Suite:** Full sensitivity labels including encryption, automatic labeling, content-based labeling recommendations.
* **+ Defender & Purview Suites:** Full sensitivity labels as Purview Suite.
* **+ EMS E5:** Manual label application only.
* **M365 E5:** Full sensitivity labels including automatic labeling across Exchange, SharePoint, and endpoints.

**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed
* [20 - Microsoft Purview Data Loss Prevention Baseline](./20-dlp-baseline.md) recommended

**Time to deploy:** 4 to 6 hours active work, plus ongoing tuning of automatic labeling conditions
**Deployment risk:** Medium. Encryption-enforced labels change how files behave; users cannot open encrypted content without the right identity. Pilot with a specific group before tenant-wide rollout.

## Purpose

This runbook deploys a five-level sensitivity label taxonomy that classifies organizational content and drives protection based on classification. Sensitivity labels are the user-visible classification mechanism in Microsoft 365: a label applied to a document, email, or meeting makes the classification part of the file metadata, and other controls (DLP, retention, access policies) can evaluate the label as a condition. Where DLP reacts to content patterns, labels express the user or auto-classifier's judgment about sensitivity; where labels apply encryption, they produce protection that persists with the file even when it leaves the tenant.

The tenant before this runbook: files and emails have no sensitivity classification. Users cannot easily distinguish confidential content from public content. External sharing is controlled by platform-level settings that apply uniformly regardless of the specific file's sensitivity. An executive's confidential strategy document has the same sharing defaults as a marketing announcement.

The tenant after: five sensitivity labels are available to users through Office applications, SharePoint, OneDrive, and Teams. Each label has a defined meaning, visible user guidance, and protection behavior. The highest-sensitivity labels apply encryption that restricts access to named users or groups regardless of where the file travels. DLP policies reference the labels for content-aware enforcement. Users develop a classification vocabulary that aligns with organizational sensitivity judgments.

The five-label taxonomy is deliberately small. Tenants with ten or more labels routinely misclassify content because users cannot keep the distinctions straight; five is the upper bound on what most users will apply correctly without extensive training. The five labels in this runbook map to common SMB classification needs: Public, General (the default), Internal, Confidential, and Highly Confidential. Tenants with specific regulatory requirements (HIPAA, SEC) can add a regulatory-specific label as a sixth, but should avoid expanding the taxonomy beyond seven total.

## Prerequisites

* UAL enabled (Runbook 14)
* Decision on encryption enforcement: Purview Suite or M365 E5 required for encrypted labels; Plain BP can deploy labels without encryption for classification only
* Identification of sensitive content types specific to the organization: financial reports, legal contracts, strategic plans, HR records
* Pilot group identified for initial rollout (10-20 users representing different departments)
* Communication plan for user rollout: training, guidance documents, helpdesk preparation

## Target configuration

The five-label taxonomy:

### 1. Public

* **Meaning:** Content approved for public disclosure. Marketing materials, press releases, published documentation.
* **Protection:** None. No encryption, no sharing restrictions.
* **Visual marking:** "Public" footer (subtle; mostly serves as positive classification)
* **Applies to:** Documents, emails, meetings

### 2. General (Default)

* **Meaning:** Ordinary business content with no specific sensitivity. Most day-to-day communication and documents.
* **Protection:** None beyond the tenant's standard external sharing settings.
* **Visual marking:** None.
* **Applies to:** Documents, emails, meetings
* **Auto-apply:** None. This is the default label for content that has not been explicitly classified.

### 3. Internal

* **Meaning:** Content intended for employees and specifically-contracted partners. Not for public disclosure.
* **Protection:** Header marking "Internal"; DLP policy prevents sharing with non-business domains without override.
* **Visual marking:** "Internal" header
* **Applies to:** Documents, emails, meetings
* **Auto-apply:** On Purview Suite+: apply to content containing specific internal project names or terminology (configurable)

### 4. Confidential

* **Meaning:** Business-sensitive content whose disclosure would cause meaningful harm. Financial plans, personnel matters, customer contracts, strategic initiatives.
* **Protection:** Encryption enforced (Purview Suite+). Access restricted to tenant members only by default. Specific groups can be designated for tighter access (e.g., Executives only, HR only).
* **Visual marking:** "Confidential" header and footer, watermark on print
* **Applies to:** Documents, emails, meetings
* **Auto-apply:** On Purview Suite+: apply to content matching sensitive info types (financial data, PII, internal-only trainable classifiers)

### 5. Highly Confidential

* **Meaning:** Extremely sensitive content whose disclosure would cause serious organizational harm. Pre-announcement M&A materials, executive compensation decisions, HR investigations, security incident details.
* **Protection:** Encryption with specific users or groups only. Cannot be forwarded, cannot be copied, cannot be printed. Expires after defined period if access control supports.
* **Visual marking:** "Highly Confidential" header, footer, watermark. Red color scheme visible in Office applications.
* **Applies to:** Documents, emails
* **Restriction:** Limited to users with specific roles or group membership; most employees should rarely encounter this label

## Deployment procedure

### Step 1: Verify licensing and prerequisites

```powershell
./21-Verify-LabelsLicensing.ps1
```

The script reports the label capability available for the tenant:

```
Sensitivity Labels Capability:
  Manual application:          Available (all variants)
  Encryption enforcement:      [Yes/No] (Purview Suite, M365 E5)
  Automatic labeling:          [Yes/No] (Purview Suite, M365 E5)
  Endpoint labeling:           [Yes/No] (M365 E5 only)
  Trainable classifiers:       [Yes/No] (Purview Suite, M365 E5)
```

Tenants without Purview Suite or equivalent can still deploy this runbook; the encryption-enforced labels simply operate as classification-only labels.

### Step 2: Deploy the label taxonomy

```powershell
./21-Deploy-SensitivityLabels.ps1 `
    -EnableEncryption $true `
    -HighlyConfidentialGroups @("Executives","Board Members") `
    -ConfidentialGroups @("All Employees")
```

The script creates the five labels with configured protection:

* Public, General, Internal: no encryption
* Confidential: encryption restricted to specified groups
* Highly Confidential: encryption restricted to specified groups with do-not-forward and do-not-copy rights

The `EnableEncryption` parameter is off by default to support Plain BP tenants deploying classification-only labels. Set to true for Purview Suite or E5 tenants.

### Step 3: Publish label policies

Labels must be published through a label policy for users to see them. The script creates a baseline publication policy targeting all users:

```powershell
./21-Deploy-LabelPolicy.ps1 `
    -PolicyName "Baseline Sensitivity Labels" `
    -ScopeAllUsers $true `
    -MandatoryLabeling $false `
    -DefaultLabel "General"
```

The policy assigns the default label (General) to new content without explicit classification. Mandatory labeling is off by default; enabling it requires users to select a label before sending email or saving a document, which is high-friction for users and typically deployed only after the taxonomy is well-established.

### Step 4: Communicate and train users

Before users see the labels in their applications, send a tenant-wide communication covering:

* The five labels and their meanings
* How to apply a label in Word, Excel, PowerPoint, Outlook
* What users see when they open an encrypted document (the Office protection notification)
* The helpdesk process for "I cannot open this file" issues
* The default label assignment (General) and what it means

Appendix: deploy a one-page reference card in the tenant's shared location.

### Step 5: Deploy to pilot group

Initial rollout targets 10-20 pilot users rather than the entire tenant. The script supports pilot scoping:

```powershell
./21-Deploy-LabelPolicy.ps1 `
    -PolicyName "Sensitivity Labels Pilot" `
    -ScopeGroup "Sensitivity Labels Pilot" `
    -DefaultLabel "General"
```

Pilot users see the labels; other users do not. Pilot runs for 2-4 weeks.

### Step 6: Transition to tenant-wide rollout

After pilot success, expand to the entire tenant:

```powershell
./21-Expand-LabelPolicy.ps1 `
    -PolicyName "Sensitivity Labels Pilot" `
    -NewPolicyName "Sensitivity Labels All Users" `
    -ScopeAllUsers $true
```

The script creates a new policy targeting all users while leaving the pilot policy in place. The pilot policy can be removed after confirming the new policy is active.

### Step 7: Deploy automatic labeling (Purview Suite and above)

Once the baseline classification behavior is established, deploy automatic labeling rules that apply labels based on content:

```powershell
./21-Deploy-AutoLabeling.ps1 `
    -ApplyInternalLabelOnProjectTerms @("Project Phoenix","Internal-Only") `
    -ApplyConfidentialOnFinancialData $true `
    -Mode "Recommendation"
```

The initial mode is "Recommendation" rather than "Automatic"; users see a suggestion to apply the label and can accept or dismiss. After 30 days of observation, transition to automatic application:

```powershell
./21-Transition-AutoLabeling.ps1 -Mode "Automatic"
```

Automatic labeling applies the label without user interaction. High-confidence rules (financial data → Confidential) are good candidates; low-confidence rules (general business keywords → Internal) should remain as recommendations.

### Step 8: Integrate with DLP

Update DLP policies from Runbook 20 to reference labels as match conditions:

```powershell
./21-Integrate-DLPLabels.ps1
```

The script updates the Confidential Business Information policy in Runbook 20 to match on the Confidential and Highly Confidential labels, in addition to the existing keyword-based conditions. This produces layered enforcement: content manually labeled Confidential triggers DLP regardless of the specific content.

### Step 9: Document the label posture

Update the operations runbook:

* Label taxonomy and definitions
* Label policy scope
* Automatic labeling rules and their mode
* DLP integration
* User communication sent
* Helpdesk escalation process for label and encryption issues

## Automation artifacts

* `automation/powershell/21-Verify-LabelsLicensing.ps1` - Reports label capability by licensing
* `automation/powershell/21-Inventory-SensitivityLabels.ps1` - Snapshots current label configuration
* `automation/powershell/21-Deploy-SensitivityLabels.ps1` - Creates the five-label taxonomy
* `automation/powershell/21-Deploy-LabelPolicy.ps1` - Publishes labels to users
* `automation/powershell/21-Expand-LabelPolicy.ps1` - Expands pilot to tenant-wide
* `automation/powershell/21-Deploy-AutoLabeling.ps1` - Creates automatic labeling rules
* `automation/powershell/21-Transition-AutoLabeling.ps1` - Changes auto-label mode
* `automation/powershell/21-Integrate-DLPLabels.ps1` - Updates DLP to reference labels
* `automation/powershell/21-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/21-Rollback-SensitivityLabels.ps1` - Reverts label deployment

## Verification

### Configuration verification

```powershell
./21-Verify-Deployment.ps1
```

Expected output covers label taxonomy, publication policy scope, automatic labeling rules, and DLP integration state.

### Functional verification

1. **Label selector visible in Office.** Open Word as a pilot or tenant user; a Sensitivity button appears in the ribbon with the five label options. Open Outlook; the same button appears in the compose window.
2. **Default label applied to new content.** Create a new Word document; observe that General is applied by default.
3. **Encryption enforcement.** Apply the Confidential label to a test document; attempt to open the file as a user outside the Confidential label's recipient group. Expected: access denied with Microsoft Purview message.
4. **DLP references label correctly.** After Step 8, send a test email with a manually-applied Confidential label; DLP policy tip for confidential business information should appear.
5. **Automatic labeling recommendation.** Create a document containing 10+ test credit card numbers; observe that the Confidential label appears as a recommendation (after autolabeling policy takes effect, typically 24 hours).

## Additional controls (add-on variants)

### Additional controls with Purview Suite or E5

**Trainable classifiers.** Purview Suite includes the ability to train custom classifiers on labeled example content (contracts, resumes, source code, etc.). Trained classifiers become available as conditions for both DLP and automatic labeling. For tenants with distinct content types not covered by built-in sensitive info types, this is a significant capability.

**Automatic labeling at scale.** Auto-labeling policies can process existing content at rest in SharePoint and OneDrive, applying labels retroactively based on content. Deploy after the forward-looking automatic labeling has been tuned; retroactive labeling can produce unexpected results on large document libraries and should be piloted first.

### Additional controls with E5 only (Endpoint Labeling)

M365 E5 includes sensitivity labeling at the endpoint level through Microsoft Purview Information Protection client: files on Windows and macOS devices are labeled and protected even when they are outside the tenant's managed applications. Purview Suite does not include endpoint labeling; files leave the tenant and lose protection if stored locally and shared outside Office applications.

For tenants with significant endpoint-based data movement concerns, E5 is the only path. For tenants where most sensitive content flows through Office applications and SharePoint/OneDrive/Teams, Purview Suite's service-side labeling is sufficient.

### Co-authoring support

Sensitivity labels with encryption support co-authoring: multiple users can edit an encrypted document simultaneously through Office web or desktop applications, provided they all have access per the label's encryption configuration. This is enabled by default for new label deployments. Tenants with older label deployments (pre-2021) may need to migrate to the new format; the Deploy script creates labels in the current format.

## What to watch after deployment

* **User friction during rollout.** The first 30 days produce helpdesk volume: "I cannot open this file," "what does Confidential mean," "why is my document asking for a password." The helpdesk process and training materials are the difference between a smooth rollout and a reversed deployment.
* **Auto-labeling false positives.** Trainable classifiers and content-based rules produce false positives until well-tuned. Start with high-confidence rules only; tune lower-confidence rules in recommendation mode before transitioning to automatic.
* **External collaboration breakage.** Documents with encryption labels cannot be opened by external users unless explicitly granted. Collaboration patterns that worked before the rollout may break when a document is labeled Confidential mid-stream. Communication and process clarity matter.
* **Legacy content not labeled.** Content created before the rollout has no label and defaults to General. Retroactive auto-labeling (available on Purview Suite+) addresses some of this but runs slowly on large libraries.
* **Label taxonomy drift.** Users invent informal classifications ("super confidential," "board only," "do not share") that do not map to the formal labels. Without periodic review, the taxonomy fragments and the formal labels become less useful than informal conventions.
* **Encryption key management.** Microsoft-managed encryption keys are the default and appropriate for most SMBs. Tenants with specific regulatory requirements may need customer-managed keys (Customer Key, available in Purview Suite), but the complexity is meaningful and should be approached deliberately.

## Rollback

```powershell
./21-Rollback-SensitivityLabels.ps1 -InventorySnapshot "./labels-inventory-<DATE>.json" -Reason "Documented reason"
```

Rollback considerations:

* **Labels cannot be removed if content has been labeled with them.** Removing a label that has been applied to existing content breaks the content's protection. Rollback typically takes the form of unpublishing the label policy (users no longer see the labels) rather than deleting the labels themselves.
* **Encrypted content remains encrypted.** A rolled-back label leaves its encrypted content encrypted; users with the right identity can still open it, users without cannot. The encryption is a property of the file, not of the current label state.
* **Rolling back is rare.** More common patterns: pause automatic labeling (transition back to recommendation mode), narrow the scope of a label policy, adjust encryption permissions on a specific label.

## References

* Microsoft Learn: [Sensitivity labels overview](https://learn.microsoft.com/en-us/purview/sensitivity-labels)
* Microsoft Learn: [Create and configure sensitivity labels](https://learn.microsoft.com/en-us/purview/create-sensitivity-labels)
* Microsoft Learn: [Apply a sensitivity label to content automatically](https://learn.microsoft.com/en-us/purview/apply-sensitivity-label-automatically)
* Microsoft Learn: [Enable co-authoring for files with sensitivity labels](https://learn.microsoft.com/en-us/purview/sensitivity-labels-coauthoring)
* Microsoft Learn: [Learn about trainable classifiers](https://learn.microsoft.com/en-us/purview/classifier-learn-about)
* M365 Hardening Playbook: [No sensitivity classification of content](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/no-sensitivity-labels.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Information protection recommendations
* NIST CSF 2.0: PR.DS-01, PR.DS-05, ID.GV-04
