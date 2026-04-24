# 23 - Retention Policies and Records Management

**Category:** Data Protection
**Applies to:**
* **Plain Business Premium:** Basic retention policies (Exchange, SharePoint, OneDrive, Teams). No records management, no retention labels with review/disposition.
* **+ Defender Suite:** Same as Plain BP; retention is not part of Defender Suite.
* **+ Purview Suite:** Full retention, retention labels, records management, disposition review, file plan.
* **+ Defender & Purview Suites:** Full retention as Purview Suite.
* **+ EMS E5:** Basic retention.
* **M365 E5:** Full retention with Administrative Unit scoping (not in Purview Suite).

**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed
* [21 - Sensitivity Labels Baseline](./21-sensitivity-labels-baseline.md) recommended for label-integrated retention

**Time to deploy:** 3 to 5 hours active work for baseline policies; records management adds 6 to 12 hours depending on file plan complexity
**Deployment risk:** Medium. Retention policies can preserve data users expected to be deleted; deletion policies can remove data users expected to keep. The runbook defaults to preservation-first and uses retention labels for any deletion to make intent explicit.

## Purpose

This runbook deploys retention policies that govern how long Microsoft 365 content is kept and what happens to it at end of life. Where DLP (runbook 20) controls data movement and sensitivity labels (runbook 21) control access, retention controls time: content that should be preserved for regulatory or business reasons stays available; content past its useful life is removed on a defined schedule rather than accumulating indefinitely. Retention produces three benefits that compound over a tenant's lifetime: regulatory compliance (tax records preserved, contract terms preserved), discovery scope containment (old content that is no longer relevant to legal discovery is gone), and storage cost management (large tenants stop paying to store content no one has looked at in a decade).

The tenant before this runbook: retention is default. Exchange mail keeps whatever users keep; deleted items recover for 14 days; there is no organizational retention floor or ceiling. SharePoint libraries retain versions indefinitely (limited by site quota). OneDrive retains whatever the user does not delete. Teams chat retains by default indefinitely. A departing employee's content remains in the tenant until someone remembers to clean up. A regulatory audit requests seven years of email; the organization has email from six months ago through the acquisition date, and nothing before the acquisition because the predecessor tenant was migrated without preserving mail.

The tenant after: three baseline retention policies cover the primary workloads with explicit retention periods (email 7 years, SharePoint/OneDrive 7 years, Teams chat 3 years). Retention labels provide classification-specific retention for records that need longer or shorter handling (tax records 10 years, contracts contract-term-plus-seven, personnel records post-separation-seven). Records management (Purview Suite or E5) adds disposition review for labeled records reaching end of life: a records manager reviews each item and either dispositions it (deletion) or extends the retention period. The file plan is documented separately and maintained by the organization's records manager or compliance owner.

Retention defaults to preservation. A retention policy that preserves content for 7 years will keep content that users delete; users cannot permanently delete content covered by an active retention policy (they see the content disappear from their view, but it exists in a retained copy). Deletion is explicit: retention labels configured with "retain then delete" or "delete only" actively remove content past the retention period. The distinction matters because mistaken preservation (keeping too much) produces discovery burden and storage cost; mistaken deletion produces regulatory exposure and potentially-lost business-critical content. The runbook defaults each policy to preservation-only and requires explicit configuration for deletion.

## Prerequisites

* Global Administrator or Compliance Administrator role
* Decision on tenant-wide retention period: 7 years is common for SMBs; regulated industries may have specific requirements (HIPAA 6 years, financial services 7 years, tax law 3-7 years depending on jurisdiction)
* Decision on Teams chat retention: 3 years is typical; some organizations retain indefinitely for institutional knowledge, others delete after 30 days for privacy reasons
* List of content categories requiring records management (for Purview Suite and above): contracts, tax records, personnel files, board minutes, intellectual property documents, regulatory correspondence
* Identification of the records manager or compliance owner responsible for disposition review (for Purview Suite and above)
* Legal review of the retention policy before deployment (strongly recommended for regulated industries)

## Target configuration

At completion, the tenant has:

### Baseline retention policies (all variants)

**Policy 1: Business Communications Retention (7 years)**

* **Scope:** Exchange mailboxes (all users)
* **Period:** 7 years from creation
* **Action:** Retain (preserve); do not delete
* **Rationale:** Regulatory floor for most SMB compliance regimes; contract and legal correspondence preservation

**Policy 2: Collaboration Content Retention (7 years)**

* **Scope:** SharePoint sites, OneDrive accounts
* **Period:** 7 years from last modification
* **Action:** Retain; do not delete
* **Rationale:** Matches email retention; captures documents shared or worked on during the retention window

**Policy 3: Teams Chat Retention (3 years)**

* **Scope:** Teams chat messages (1:1 chat, group chat, channel messages)
* **Period:** 3 years from creation
* **Action:** Retain, then delete
* **Rationale:** Chat accumulates quickly and has lower regulatory value than email; deletion prevents indefinite growth while preserving recent history

### Retention labels (Purview Suite and above)

Retention labels are applied to specific content to override the baseline retention policy with a label-specific behavior:

| Label | Retention period | Action | Review required |
|---|---|---|---|
| Tax Records | 10 years after creation | Retain, review, then delete | Yes |
| Contract (Active) | Retain until contract end + 7 years | Event-based retention | Yes |
| Personnel Records | Retain until separation + 7 years | Event-based retention | Yes |
| Financial Records | 7 years after fiscal year | Retain, review, then delete | Yes |
| Board Materials | Retain permanently (no deletion) | Retain only | No |
| Intellectual Property | Retain permanently | Retain only | No |

Each label can mark the item as a "record" (locking it against modification or deletion by users) or as a "regulatory record" (locking permanently, requires compliance admin to override).

### Records management (Purview Suite and above)

* File plan documents the organizational record categories, associated retention labels, and disposition procedures
* Auto-apply retention labels based on content (sensitive info types, trainable classifiers, keyword matches)
* Disposition review workflow routes records reaching end of life to the records manager
* Disposition review produces audit trail of each disposition decision (delete, extend retention, re-classify)

## Deployment procedure

### Step 1: Verify licensing and inventory

```powershell
./23-Verify-RetentionLicensing.ps1
./23-Inventory-Retention.ps1 -OutputPath "./retention-inventory-$(Get-Date -Format 'yyyyMMdd').json"
```

The Verify script reports which capabilities are available (basic retention, retention labels, records management). The Inventory script captures current retention policies, labels, and file plan state for rollback reference.

### Step 2: Deploy baseline retention policies

```powershell
./23-Deploy-BaselineRetention.ps1 `
    -EmailRetentionYears 7 `
    -CollaborationRetentionYears 7 `
    -TeamsChatRetentionYears 3 `
    -TeamsChatAction "RetainThenDelete" `
    -EmailAction "Retain" `
    -CollaborationAction "Retain"
```

The script creates the three baseline policies with the configured periods and actions. Default actions preserve content (Retain); the Teams chat policy defaults to Retain-Then-Delete because chat accumulates quickly.

### Step 3: Deploy retention labels (Purview Suite and above)

```powershell
./23-Deploy-RetentionLabels.ps1
```

The script creates the six baseline retention labels: Tax Records, Contract (Active), Personnel Records, Financial Records, Board Materials, Intellectual Property. Each label has the retention period and action from the target configuration table.

For tenants without Purview Suite, the script exits with a message indicating that labels are available only in higher-tier licensing.

### Step 4: Publish retention labels

```powershell
./23-Publish-RetentionLabels.ps1 `
    -PolicyName "Baseline Retention Labels" `
    -ScopeAllUsers $true
```

Users see the retention labels as a separate label selector alongside sensitivity labels (or as a subcategory in Office applications that support both).

### Step 5: Configure auto-apply rules (Purview Suite and above)

```powershell
./23-Deploy-AutoRetentionRules.ps1
```

The script creates auto-apply rules for common content patterns:

* Files in a "Contracts" SharePoint library → Contract (Active) label
* Files in a "Tax Documents" library → Tax Records label
* Files matching financial statement keywords → Financial Records label
* Files in HR-owned sites → Personnel Records label

Rules start in a recommendation mode (user sees suggestion); transition to automatic after 30 days of observation.

### Step 6: Configure disposition review (Purview Suite and above)

```powershell
./23-Configure-DispositionReview.ps1 `
    -RecordsManager "records-manager@contoso.com" `
    -Stages @(
        @{ Stage = 1; Reviewer = "department-owner@contoso.com" }
        @{ Stage = 2; Reviewer = "records-manager@contoso.com" }
    )
```

Disposition review routes records reaching end of life to reviewers. Multi-stage reviews allow a departmental review (stage 1) followed by records manager review (stage 2). Reviewers can dispose (delete), extend retention (for an additional defined period), or re-classify (apply a different retention label).

### Step 7: Document the file plan

The file plan is an organizational document, not a Microsoft 365 artifact. Document:

* Record categories and their retention labels
* Retention period justification (regulatory citation or business rationale)
* Event triggers for event-based retention (contract end, employee separation)
* Disposition review ownership and cadence
* Override authority (who can modify retention on specific items)

The file plan should be reviewed annually (runbook 19) and updated when regulatory requirements change.

### Step 8: Configure litigation hold workflow

Litigation holds preserve content beyond the retention policy when legal matters are active:

```powershell
./23-Configure-LitigationHold-Workflow.ps1 `
    -LegalContact "legal@contoso.com" `
    -DefaultHoldDurationDays $null
```

The script configures the workflow for placing litigation holds on specific mailboxes, SharePoint sites, or OneDrive accounts when a legal matter requires preservation. Litigation holds override retention policies (content cannot be deleted while the hold is active) but do not apply automatically; the legal team places holds per matter.

### Step 9: Verify deployment

```powershell
./23-Verify-Deployment.ps1
```

## Automation artifacts

* `automation/powershell/23-Verify-RetentionLicensing.ps1` - Reports retention capability by licensing
* `automation/powershell/23-Inventory-Retention.ps1` - Snapshots current retention configuration
* `automation/powershell/23-Deploy-BaselineRetention.ps1` - Creates the three baseline policies
* `automation/powershell/23-Deploy-RetentionLabels.ps1` - Creates the six baseline retention labels
* `automation/powershell/23-Publish-RetentionLabels.ps1` - Publishes labels to users
* `automation/powershell/23-Deploy-AutoRetentionRules.ps1` - Creates auto-apply rules
* `automation/powershell/23-Configure-DispositionReview.ps1` - Configures disposition review workflow
* `automation/powershell/23-Configure-LitigationHold-Workflow.ps1` - Litigation hold workflow setup
* `automation/powershell/23-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/23-Rollback-Retention.ps1` - Reverts to snapshot

## Verification

### Configuration verification

```powershell
./23-Verify-Deployment.ps1
```

Expected output covers baseline policy existence and coverage, retention label existence, auto-apply rule configuration, disposition review workflow, and recent activity.

### Functional verification

1. **Retention preserves deleted email.** Delete a test email from Inbox; wait 14 days; verify content is still recoverable through eDiscovery or Content Search.
2. **Retention label locks content as record.** Apply the "Contract (Active)" label to a test document; attempt to delete the document through the SharePoint UI. Expected: deletion blocked with record protection message.
3. **Disposition review triggers at end of retention.** Apply "Financial Records" label to a test document with a backdated creation time (requires admin action); wait for disposition review to trigger; verify the records manager receives a review task.
4. **Litigation hold preserves content.** Place a test mailbox under litigation hold; delete items from the mailbox; verify items are preserved and accessible through eDiscovery.

## Additional controls (add-on variants)

### Additional controls with Purview Suite or E5 Compliance

**Records management automation.** Auto-apply retention labels based on trainable classifiers produces records-aware retention without user action. The classifier is trained on labeled examples (contracts, resumes, financial statements); content matching the trained pattern gets the appropriate retention label automatically.

**Multi-stage disposition review.** Purview Suite supports multi-stage disposition workflows (stage 1: department owner; stage 2: records manager). Appropriate for organizations with departmental records ownership and centralized compliance oversight.

**File plan import.** Purview file plans can be imported from CSV, allowing organizations with complex file plans (hundreds of record categories) to manage the plan outside Purview and import on change.

### Additional controls with E5 Compliance (not in Purview Suite)

**Administrative Unit scoping.** Retention policies in E5 Compliance can target specific Administrative Units. Purview Suite applies policies tenant-wide. For tenants needing department-specific retention (HR mailboxes 7 years, Finance mailboxes 10 years, others 3 years), E5 Compliance is required. Workaround in Purview Suite: use retention labels for the longer-retention categories, leaving the tenant-wide policy at the shorter period.

**Regulatory record type.** E5 Compliance supports "regulatory records" that cannot be unlocked by any user including compliance admins once applied. Appropriate for strict regulatory regimes (SEC 17a-4). Purview Suite supports "records" that can be unlocked by compliance admins with appropriate justification.

### Integration with sensitivity labels

Sensitivity labels (runbook 21) and retention labels can coexist. A document can have both a sensitivity classification (Confidential) and a retention classification (Contract). The combinations produce layered handling: the sensitivity label drives access and encryption; the retention label drives preservation and disposition.

Some organizations consolidate the two into combined labels (a single label that is both "Confidential" for access and applies 10-year retention). The baseline keeps them separate because the categories do not map cleanly: a Public label document may need 7-year retention if it is an announcement; a Confidential document may need no retention beyond user discretion. Keeping sensitivity and retention as independent dimensions avoids forcing unnatural category alignment.

## What to watch after deployment

* **Retention policies apply silently.** Users do not see any indication that their content is subject to retention. The first time retention matters (someone tries to permanently delete content and cannot, or eDiscovery finds content users thought was deleted) can surprise users. Communicate retention clearly during rollout.
* **SharePoint site deletion and retention.** When a SharePoint site is deleted, its content is held under retention if a retention policy applies. The content exists in the tenant but is not easily accessible through normal user interfaces. For eDiscovery, the content is searchable; for user access, it requires admin intervention. Plan for this scenario in site lifecycle processes.
* **Teams chat retention visibility.** When Teams chat retention deletes messages, users see the message simply absent from their chat history. There is no indicator that retention removed it. Some users interpret this as data loss or system malfunction. Communication matters.
* **Auto-apply label volume.** Auto-apply rules can label large volumes of existing content retroactively. For a tenant with a decade of accumulated content, a single auto-apply rule can produce tens of thousands of labeled items. Verify the rule is correctly scoped before enabling; run in recommendation mode first.
* **Event-based retention requires event triggers.** Labels like "Contract (Active)" that retain until a specific event plus seven years need the event to be triggered. Without trigger integration (typically through a connector or manual trigger in the Purview portal), event-based retention never starts its countdown and content is held indefinitely. Plan trigger integration as part of deployment, not as a future activity.
* **Disposition review backlog.** Disposition review accumulates as records reach end of life. Without a records manager actively reviewing, items pile up. For SMB tenants without a dedicated records role, consider assigning the function to an existing role (CFO, COO, or senior legal contact) with a monthly cadence.
* **Litigation hold interaction with retention.** Litigation holds override retention deletion. Content under litigation hold is preserved even if retention would delete it. After the litigation matter closes and the hold is released, the retention policy resumes. This interaction is correct but can be counterintuitive when the retention period has already passed during the hold.

## Rollback

```powershell
./23-Rollback-Retention.ps1 -InventorySnapshot "./retention-inventory-<DATE>.json" -Reason "Documented reason"
```

Rollback considerations specific to retention:

* **Retention policies cannot be trivially removed.** Disabling a retention policy does not delete the content it was retaining; the content remains in the tenant subject to normal user controls. For content under retention that should now be deletable, explicit deletion is required after the policy is removed.
* **Retention labels cannot be removed from content.** Like sensitivity labels, once applied, retention labels cannot be cleanly removed if they have been applied to content. Rollback typically unpublishes the label policy rather than deleting labels.
* **Records cannot be deleted by normal rollback.** Content marked as a record (or regulatory record) cannot be deleted through the retention policy removal; explicit record unlock is required first, and regulatory records require compliance admin override.

Rolling back retention is almost always more work than rolling back any other baseline control. Avoid rollback; use targeted adjustments (shorter retention period, scoped exemption for specific content categories).

## References

* Microsoft Learn: [Learn about retention policies and retention labels](https://learn.microsoft.com/en-us/purview/retention)
* Microsoft Learn: [Create retention labels for records management](https://learn.microsoft.com/en-us/purview/file-plan-manager)
* Microsoft Learn: [Disposition of content](https://learn.microsoft.com/en-us/purview/disposition)
* Microsoft Learn: [Apply a retention label to content automatically](https://learn.microsoft.com/en-us/purview/apply-retention-labels-automatically)
* Microsoft Learn: [Litigation holds](https://learn.microsoft.com/en-us/purview/ediscovery-create-a-litigation-hold)
* M365 Hardening Playbook: [No retention policy configured](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/no-retention-policy.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Retention recommendations
* NIST CSF 2.0: ID.GV-04, PR.IP-06
