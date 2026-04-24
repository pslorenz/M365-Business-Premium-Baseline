# 20 - Microsoft Purview Data Loss Prevention Baseline

**Category:** Data Protection
**Applies to:**
* **Plain Business Premium:** Basic DLP for Exchange, SharePoint, OneDrive. Limited built-in templates.
* **+ Defender Suite:** Same as Plain BP; DLP is not part of Defender Suite.
* **+ Purview Suite:** Full DLP including Teams chat and channel, advanced conditions, custom sensitive info types.
* **+ Defender & Purview Suites:** Full DLP as Purview Suite.
* **+ EMS E5:** Basic DLP. EMS E5 does not add DLP capability.
* **M365 E5:** Full DLP including Administrative Unit scoping and endpoint DLP (endpoint DLP covered separately in a future runbook).

**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed
* [21 - Sensitivity Labels Baseline](./21-sensitivity-labels-baseline.md) recommended but not required

**Time to deploy:** 3 to 4 hours active work for the baseline policies, plus 30 days in test mode before enforcement
**Deployment risk:** Medium. DLP policies in enforcement mode can block legitimate business activities during initial tuning. The runbook uses test mode for initial deployment and a staged progression to enforcement.

## Purpose

This runbook deploys Data Loss Prevention policies that catch sensitive data movement across Exchange, SharePoint, OneDrive, and Teams. Where the email protection runbooks (11-13) prevent threats from entering, and the identity and device runbooks prevent unauthorized access, DLP catches the specific scenario those controls miss: authorized users moving sensitive data out of the tenant through legitimate channels. Credit card numbers emailed to a personal address, Social Security numbers uploaded to a non-corporate OneDrive, confidential contracts shared externally through SharePoint, protected health information pasted into Teams chat with an external guest.

The tenant before this runbook: DLP is either off entirely or in default state with no custom policies. Sensitive data moves freely through the tenant's productivity surfaces. A compromised user account exfiltrates credit card data through email without detection. A well-meaning employee shares a document containing patient records with an external vendor who should not have access. An attacker-controlled OAuth application downloads the contents of a user's OneDrive.

The tenant after: DLP policies cover the four primary surfaces (Exchange, SharePoint, OneDrive, Teams) with baseline sensitive info type detection (credit cards, SSNs, passport numbers, bank account numbers, and regionally relevant regulated data types). Policies operate in "test with policy tips" mode initially, producing user notifications and audit events without blocking, for 30 days. After tuning based on observed matches, policies progress to enforcement mode with block-and-override for most matches and hard block for high-severity matches (PHI, large-volume credit card exposures).

DLP pairs with sensitivity labels (runbook 21) to produce layered protection: labels classify content, DLP enforces protection rules based on label and content. The two runbooks are deployed sequentially because DLP policies can reference labels as a match condition, but labels can exist without DLP. Deploying DLP first with content-based conditions, then labels, then re-tuning DLP to reference labels, is the recommended sequence and what this runbook assumes.

## Prerequisites

* UAL enabled with appropriate retention (Runbook 14)
* List of regulated data types applicable to the organization: credit card (any tenant processing payments), SSN (US tenants), NHS number (UK tenants), tax file number (Australian tenants), PHI (healthcare), etc.
* Decision on user notification posture: silent (audit only), policy tips (visible to user), or block with override
* Security admin or compliance admin distribution list for incident notifications
* Decision on pilot vs. tenant-wide rollout: Purview Suite does not support Administrative Unit scoping, so pilot rollout uses test mode on the full tenant rather than enforcement on a subset

## Target configuration

At completion, the tenant has five DLP policies covering:

### Policy 1: US Financial Data (Payment Cards, Bank Accounts)

* **Scope:** Exchange, SharePoint, OneDrive, Teams chat and channel
* **Conditions:** Credit card numbers (threshold 1), ABA routing numbers (threshold 1), US bank account numbers (threshold 1)
* **Actions:** Policy tip to user, notify security admin on match, block external sharing for SharePoint/OneDrive matches
* **Exceptions:** Legitimate business senders (if any; documented)

### Policy 2: US PII (SSN, Passport, Driver License)

* **Scope:** Exchange, SharePoint, OneDrive, Teams
* **Conditions:** US SSN (threshold 1), US passport number (threshold 1), US driver license (threshold 3 per recipient)
* **Actions:** Policy tip, notify security admin, block external sharing
* **Exceptions:** HR team (with documented business need)

### Policy 3: Protected Health Information (healthcare tenants)

* **Scope:** Exchange, SharePoint, OneDrive, Teams
* **Conditions:** ICD-9/ICD-10 codes combined with patient identifiers, PHI keywords, medical terms
* **Actions:** Block with override for internal sharing, hard block for external sharing, notify privacy officer
* **Applicable to:** HIPAA-subject tenants

### Policy 4: Confidential Business Information

* **Scope:** Exchange, SharePoint, OneDrive, Teams
* **Conditions:** Documents labeled Confidential (once sensitivity labels deployed in Runbook 21), keywords matching known internal project names
* **Actions:** Policy tip, notify user and security admin
* **Tuning:** Requires iteration to match organizational vocabulary

### Policy 5: Outbound Large-Volume Transfer

* **Scope:** Exchange (outbound), OneDrive (download by user)
* **Conditions:** Multiple sensitive data types combined (10+ credit cards OR 5+ SSNs in one message), bulk OneDrive downloads exceeding 100 files or 500 MB in 15 minutes
* **Actions:** Hard block, notify security admin immediately
* **Rationale:** High-fidelity indicator of data exfiltration; even authorized users should not move this volume in this pattern

## Deployment procedure

### Step 1: Verify Purview licensing and prerequisites

```powershell
./20-Verify-DLPLicensing.ps1
```

The script checks for Purview Suite, Defender & Purview Suites, E5 Compliance, or M365 E5 licensing and reports DLP capability level. Plain Business Premium tenants get a reduced policy set; Purview Suite and above get the full policy set.

### Step 2: Inventory current DLP state

```powershell
./20-Inventory-DLPPolicies.ps1 -OutputPath "./dlp-inventory-$(Get-Date -Format 'yyyyMMdd').json"
```

The script enumerates existing DLP policies and their rules. Most tenants have zero or one default policy; the inventory establishes the baseline for rollback.

### Step 3: Deploy the five baseline policies in test mode

```powershell
./20-Deploy-DLPPolicies.ps1 `
    -IncludeHealthcarePolicy $false `
    -NotificationEmail "security-alerts@contoso.com" `
    -Mode "TestWithNotifications"
```

The script creates the five DLP policies in "Test with notifications" mode. Matches produce user policy tips and admin notifications but do not block. The `-IncludeHealthcarePolicy` switch is off by default; enable for HIPAA-subject tenants.

The five policies are created in a specific priority order:
1. Outbound Large-Volume Transfer (priority 0, highest)
2. Protected Health Information (priority 1, if enabled)
3. US Financial Data (priority 2)
4. US PII (priority 3)
5. Confidential Business Information (priority 4)

Priority order matters when multiple policies match the same content; the highest-priority policy's action wins. The large-volume policy is highest because it represents the clearest exfiltration signal.

### Step 4: Monitor for 30 days in test mode

```powershell
./20-Monitor-DLPMatches.ps1 -LookbackDays 30
```

The script produces a report of policy matches, aggregated by:

* Policy and rule
* Match count by day
* Top matching users (potential false positive or true positive indicators)
* Top matched sensitive info types
* External-sharing matches specifically

Review the report weekly during the first month. Common tuning actions:

* **Policy matches on training or test data:** legitimate samples of credit card numbers or SSNs in developer documentation, training materials, or test databases trigger matches. Add specific content exceptions rather than broad user exclusions.
* **HR or finance team hitting PII matches:** expected for the roles. Document the business need, consider whether their activity should still produce audit events even if not blocked.
* **Matches in email signatures or templates:** organizations with regulated data in signatures (legal disclaimers, healthcare notices) produce continuous matches. Add content exceptions for the specific signature patterns.
* **Zero matches on a policy that should match something:** verify the policy is actually active; test with a deliberate test message or file.

### Step 5: Transition policies to enforcement mode

After 30 days of monitoring and tuning, transition policies to enforcement:

```powershell
./20-Transition-DLPEnforcement.ps1 `
    -Policies "USFinancialData","USPII","ConfidentialBusinessInfo" `
    -Mode "BlockWithOverride"

./20-Transition-DLPEnforcement.ps1 `
    -Policies "OutboundLargeVolumeTransfer" `
    -Mode "BlockWithoutOverride"
```

The high-severity policy (Outbound Large-Volume Transfer) transitions to hard block without override. The remaining policies transition to block-with-override, allowing users to override with business justification while producing an audit event.

If the PHI policy is deployed:

```powershell
./20-Transition-DLPEnforcement.ps1 `
    -Policies "ProtectedHealthInfo" `
    -Mode "BlockWithOverride_InternalOnly"
```

PHI transitions to block-with-override for internal matches, hard block for external matches.

### Step 6: Configure incident management

DLP matches produce incidents in Microsoft Purview. Configure incident notifications:

```powershell
./20-Configure-DLPIncidentNotifications.ps1 `
    -IncidentEmail "dlp-incidents@contoso.com" `
    -HighSeverityEmail "security-admin@contoso.com"
```

The script configures notification routing: all DLP incidents to the standard queue, high-severity incidents (Outbound Large-Volume, PHI external) to the security admin direct.

### Step 7: Document the DLP posture

Update the operations runbook:

* Policies deployed and their enforcement mode
* Notification destinations
* User communication sent regarding policy tips
* Business-justified exceptions with review dates
* Metrics: match rate per policy, false positive rate, true positive outcomes

## Automation artifacts

* `automation/powershell/20-Verify-DLPLicensing.ps1` - Checks Purview licensing tier
* `automation/powershell/20-Inventory-DLPPolicies.ps1` - Snapshots current DLP configuration
* `automation/powershell/20-Deploy-DLPPolicies.ps1` - Creates the five baseline policies
* `automation/powershell/20-Monitor-DLPMatches.ps1` - Reports match activity
* `automation/powershell/20-Transition-DLPEnforcement.ps1` - Transitions policies between modes
* `automation/powershell/20-Configure-DLPIncidentNotifications.ps1` - Configures incident routing
* `automation/powershell/20-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/20-Rollback-DLPPolicies.ps1` - Reverts to inventory snapshot

## Verification

### Configuration verification

```powershell
./20-Verify-Deployment.ps1
```

Expected output covers policy existence, enforcement mode per policy, notification destinations, and recent match activity.

### Functional verification

1. **Credit card detection in Exchange.** Send a test email from an internal account to an external recipient containing the text "test 4111 1111 1111 1111 (Visa test card)". Expected: policy tip appears; if in enforcement mode, message is blocked with override option.
2. **SSN detection in SharePoint.** Upload a test document containing five test SSNs to a SharePoint site. Attempt to share externally. Expected: external share is blocked or requires override.
3. **Bulk download detection.** Download 100+ files from a test OneDrive folder in under 15 minutes. Expected: policy matches, admin notification received.
4. **External Teams chat.** Post a test message containing a credit card number in a Teams chat with an external guest. Expected: policy tip appears; block if configured.

## Additional controls (add-on variants)

### Additional controls with Purview Suite or E5 Compliance

Purview Suite adds automatic classification via trainable classifiers, which can identify sensitive content categories not covered by built-in sensitive info types (contracts, resumes, source code). For tenants with custom content categories, train classifiers on labeled examples and reference them in DLP conditions.

### Additional controls with E5 Compliance (not in Purview Suite)

**Administrative Unit scoping.** E5 Compliance allows DLP policies to target specific administrative units (subsets of users). Purview Suite applies policies tenant-wide. For tenants needing progressive rollout or department-specific policies, E5 Compliance is required. The runbook's test mode compensates for this limitation in Purview Suite tenants by producing audit events during the observation period without blocking.

**Endpoint DLP.** E5 Compliance includes endpoint DLP, which monitors and controls sensitive data on Windows and macOS devices: USB device writes, clipboard copying, application-to-application data flow, print operations. Endpoint DLP is configured separately from the service-side DLP covered in this runbook and will be addressed in a dedicated runbook (not yet written) for E5 Compliance or M365 E5 tenants.

### Integration with sensitivity labels

Once sensitivity labels are deployed (Runbook 21), DLP policies can reference labels as match conditions instead of or in addition to content-based conditions. The "Confidential Business Information" policy in this runbook is a placeholder that should be refined to match on the Confidential label once labels exist. The refinement is a single policy update; the deployment script supports the update mode.

## What to watch after deployment

* **False positive rate during first 30 days.** Expect matches per week in the tens to hundreds depending on tenant size. Patterns that consistently produce matches but are legitimate need exceptions; patterns that rarely produce matches but indicate real movement stay as-is.
* **User confusion from policy tips.** Users seeing unfamiliar blocking or warning tips may interpret them as system problems. Send a tenant-wide communication explaining the tips, the override process, and why the policies exist.
* **Override abuse.** Block-with-override policies produce useful audit events when overridden, but users who override continuously may be sending data that the policy correctly identifies as sensitive. Review override patterns monthly; consider tightening to hard-block for specific users or data types if abuse continues.
* **Missed matches due to encryption or file format.** DLP processes accessible content. Password-protected PDFs, encrypted archives, and image-based documents (where data is visual rather than text) may not trigger matches. For tenants with significant volumes of scanned documents, consider OCR integration (E5 Compliance capability).
* **Teams scope nuances.** Teams chat between internal users is covered by DLP differently from Teams channels and from external guest chats. Verify matches in each context during tuning; the interaction between Teams DLP and Teams external access settings affects what gets blocked vs. allowed.
* **Policy match storage costs.** Purview Suite and E5 Compliance include policy match storage with the licensing. Plain Business Premium has limited match storage which may truncate older matches. For extended investigation, export matches to SIEM or archive regularly.

## Rollback

```powershell
./20-Rollback-DLPPolicies.ps1 -InventorySnapshot "./dlp-inventory-<DATE>.json" -Reason "Documented reason"
```

Full rollback removes the policies created by the runbook. Tuning-level adjustments should use the Deploy script with modified parameters rather than full rollback.

Targeted policy rollback (disable one policy while keeping others):

```powershell
./20-Transition-DLPEnforcement.ps1 `
    -Policies "USPII" `
    -Mode "TestWithNotifications" `
    -Reason "Excessive false positives in HR workflows; returning to test mode pending tuning"
```

This is almost always preferable to full rollback; it preserves the policy for continued tuning while removing enforcement impact.

## References

* Microsoft Learn: [Data Loss Prevention overview](https://learn.microsoft.com/en-us/purview/dlp-learn-about-dlp)
* Microsoft Learn: [Create, test, and tune DLP policies](https://learn.microsoft.com/en-us/purview/dlp-create-deploy-policy)
* Microsoft Learn: [Sensitive information types](https://learn.microsoft.com/en-us/purview/sit-learn-about-sensitive-information-types)
* Microsoft Learn: [DLP for Teams](https://learn.microsoft.com/en-us/purview/dlp-microsoft-teams)
* Microsoft Learn: [DLP policy tip reference](https://learn.microsoft.com/en-us/purview/dlp-policy-tips-reference)
* M365 Hardening Playbook: [No DLP policies for financial or regulated data](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/no-dlp-policies.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: DLP recommendations
* NIST CSF 2.0: PR.DS-01, PR.DS-02, PR.DS-05, DE.AE-02
