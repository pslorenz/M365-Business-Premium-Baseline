# 18 - Quarterly Review Checklist

**Category:** Operations
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* Three consecutive monthly reviews (Runbook 17) completed before the first quarterly review
**Time to complete:** 1 full day (6 to 8 hours)
**Cadence:** Quarterly, scheduled as a standing calendar block

## Purpose

The quarterly review is the deeper audit layer that catches drift the monthly review misses. Monthly reviews focus on operational cleanup (exception expiration, alert triage, recent changes); quarterly reviews verify that the baseline's structural assumptions still hold. Administrators who moved roles, personnel who left the organization, new sending infrastructure that was added to SPF, compliance policies that need tightening because the fleet aged through a Windows OS end-of-life. These are the signals the quarterly review catches.

The quarterly review produces deliverables beyond internal documentation: a tier audit report for leadership, an access review decision log for tier-0 roles, a posture report for the customer or executive sponsor. Organizations that subject their M365 environment to annual audit (SOC 2, ISO 27001, HIPAA) use the quarterly review output as the evidence trail showing continuous compliance monitoring.

This runbook takes a full working day. The scope is broader than monthly but narrower than the annual review (Runbook 19). Compressing to half a day produces incomplete coverage; expanding to multiple days suggests the quarterly reviews have been accumulating unresolved items and an ad-hoc remediation sprint is needed before the next quarterly review.

## Prerequisites

* Three consecutive monthly reviews completed with documented outcomes
* Tier group rosters and operations runbook are current
* Designated quarterly reviewer: a senior administrator or MSP lead with authority to make tier reclassification and access review decisions
* Previous quarterly review report available for comparison

## Quarterly checklist

The review is organized into six sections. Each section has specific deliverables.

### Section 1: Tier model audit (approximately 90 minutes)

**Purpose:** Verify the admin tier model from Runbook 03 still reflects actual privilege requirements.

| Item | Action |
|---|---|
| 1.1 | Pull full admin assignment audit: every directory role holder, tier classification, active vs. eligible |
| 1.2 | For each tier-0 administrator: confirm the individual still requires tier-0 access. Remove eligibility for those who no longer need it. |
| 1.3 | For each tier-1 administrator: same review; promote to tier-0 if responsibilities expanded, demote to tier-2 or remove if shrunk |
| 1.4 | Identify administrators who have not activated any PIM role in the past 90 days: candidates for removal (unused access is still access) |
| 1.5 | Review Application Administrator and Cloud Application Administrator assignments specifically; these roles warrant extra scrutiny |
| 1.6 | Document tier reclassification decisions with justification |

Deliverable: Tier audit report with current roster, changes this quarter, and rationale.

### Section 2: Access reviews (approximately 60 minutes)

**Purpose:** Complete Entra ID Access Reviews for tier-0 (quarterly cadence) and process results.

| Item | Action |
|---|---|
| 2.1 | For tenants with Access Reviews licensed: confirm the quarterly tier-0 review launched on schedule |
| 2.2 | Review the access review results; confirm each reviewer completed their assignment |
| 2.3 | Apply access review decisions: remove eligibility for principals the reviewer denied |
| 2.4 | For tenants without Access Reviews licensing: perform the manual quarterly tier-0 review using the tier audit from Section 1 |
| 2.5 | Document access review outcomes in the operations runbook |

Deliverable: Access review decision log with approvals, removals, and reviewer signatures.

### Section 3: Conditional Access and identity review (approximately 60 minutes)

| Item | Action |
|---|---|
| 3.1 | Review every CA policy's exclusion list: every exclusion has documented justification and a review date |
| 3.2 | Review CA policy assignments: no user or group is accidentally excluded from baseline coverage |
| 3.3 | Review named locations: allowed countries list, IP ranges if any, still match current operations |
| 3.4 | Review Identity Protection risk policies (P2 tenants): recent risk detections, user and sign-in risk states, any dismissed risks |
| 3.5 | Review authentication methods policy: MFA method availability, any legacy method still enabled that should be removed |

Deliverable: CA exception report with every exclusion documented.

### Section 4: Device compliance and fleet review (approximately 90 minutes)

| Item | Action |
|---|---|
| 4.1 | Pull device inventory: Windows, macOS, iOS, Android counts and compliance rates |
| 4.2 | Identify devices with compliance exceptions lasting more than 90 days: either remediate or retire |
| 4.3 | Review BitLocker escrow rate: investigate any drop below 90% of enrolled Windows devices |
| 4.4 | Review VBS and Credential Guard deployment rate: target is above 90% of capable devices |
| 4.5 | Review Windows OS version distribution: identify devices approaching or past support end-of-life |
| 4.6 | Review Autopilot and Apple Business Manager token status: APNs expiration, ABM token expiration, Android Enterprise binding |
| 4.7 | Review enrollment restrictions: still aligned with BYOD policy and current workforce patterns |

Deliverable: Device posture report with fleet counts, compliance rates, and end-of-life projection.

### Section 5: Email protection review (approximately 60 minutes)

| Item | Action |
|---|---|
| 5.1 | Review anti-phish policy false positive rate based on quarantine release patterns |
| 5.2 | Review anti-phish impersonation user list against current personnel: add new executives, remove departed |
| 5.3 | Review anti-phish impersonation domain list against current partners |
| 5.4 | Review SPF records: confirm no legitimate sender is failing, confirm no stale senders remain |
| 5.5 | If DKIM keys have not rotated in 9+ months, schedule rotation within the month |
| 5.6 | Review DMARC policy state: tenants in p=none should be progressing toward p=quarantine; tenants in p=quarantine should be progressing toward p=reject |
| 5.7 | Review Safe Links and Safe Attachments block activity for false positive patterns |

Deliverable: Email protection posture report with tuning recommendations.

### Section 6: Alerting and audit review (approximately 90 minutes)

| Item | Action |
|---|---|
| 6.1 | Review the past quarter's alert activity: total volume, high-severity count, true positive rate |
| 6.2 | Identify alert rules with zero firings: verify the underlying query still matches known events |
| 6.3 | Identify alert rules with excessive firings: tune or suppress |
| 6.4 | Review alert response times: SLA for high-severity alerts should be under 30 minutes |
| 6.5 | Review UAL retention: confirm current retention matches licensing entitlement |
| 6.6 | Review Defender XDR or Sentinel connector health: confirm no ingestion gaps |
| 6.7 | Review any closed security incidents from the past quarter: lessons learned, rule tuning candidates |

Deliverable: Alert catalog report with per-rule metrics and tuning decisions.

## Automation artifacts

* `automation/powershell/18-Run-QuarterlyReview.ps1` - Executes automated portions of the quarterly checklist and produces a consolidated report
* `automation/powershell/18-Export-TierAudit.ps1` - Produces the tier audit report for Section 1
* `automation/powershell/18-Export-CAExceptionReport.ps1` - Produces the CA exception report for Section 3
* `automation/powershell/18-Export-DevicePostureReport.ps1` - Produces the device posture report for Section 4
* `automation/powershell/18-Export-EmailProtectionReport.ps1` - Produces the email protection report for Section 5
* `automation/powershell/18-Export-AlertCatalogReport.ps1` - Produces the alert catalog report for Section 6

## Report deliverables

The quarterly review produces five specific reports that together constitute the continuous-compliance evidence trail:

1. **Tier audit report** (Section 1) - current administrator roster by tier, changes this quarter, rationale
2. **Access review decision log** (Section 2) - tier-0 access review outcomes with approvals and removals
3. **CA exception report** (Section 3) - every Conditional Access exclusion with justification and review date
4. **Device posture report** (Section 4) - fleet composition, compliance rates, end-of-life projection
5. **Alert catalog report** (Section 6) - rule inventory, per-rule metrics, tuning decisions

Store reports in a dedicated operations archive with clear naming (`YYYY-Q#-tier-audit.pdf`, `YYYY-Q#-ca-exceptions.pdf`, etc.). Retain indefinitely; audit evidence trails accumulate value over time.

## What to watch

* **Quarterly reviews scheduled but not completed:** indicates either the reviewer is overloaded or the scope is too broad. Adjust one or the other; do not let quarterly reviews skip more than one quarter.
* **Deliverables not produced:** if the quarterly review is done but the reports are not written, the evidence trail has gaps. Treat report production as part of the review, not as optional documentation.
* **Recurring issues quarter over quarter:** the same tier-0 administrator who "just needs access for one more quarter" three quarters in a row is a permanent tier-0 administrator; reclassify. The same alert rule "might need tuning next quarter" three quarters in a row should be tuned now.
* **Quarterly work that should be monthly:** items that appear in every quarterly review but not in monthly reviews indicate the monthly checklist is missing something. Update Runbook 17.

## References

* Microsoft Learn: [Access reviews in Microsoft Entra](https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview)
* SOC 2 Trust Services Criteria: Continuous monitoring requirements
* ISO 27001:2022: Annex A.5.15 (Access control review)
* NIST CSF 2.0: ID.GV-04, GV.OC-03, PR.AA-05
