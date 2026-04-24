# 19 - Annual Review Checklist

**Category:** Operations
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* Four consecutive quarterly reviews (Runbook 18) completed
* At least one full year of baseline operation
**Time to complete:** 2 to 3 working days, often scheduled across a full week
**Cadence:** Annually, tied to the fiscal year or tenant anniversary

## Purpose

The annual review is the deepest audit in the operational cadence and produces the outputs that organizations use for board reporting, insurance renewal, auditor review, and licensing planning. Where the monthly review catches operational drift and the quarterly review catches structural drift, the annual review catches strategic drift: controls that made sense a year ago but no longer match the threat landscape, licensing investments that have not produced corresponding value, regulatory changes that require baseline adjustments.

The annual review also completes specific one-year-cycle operations that cannot be run quarterly: DKIM key rotation (if not done sooner), DMARC policy progression verification, APNs certificate renewal, Apple Business Manager token renewal, full policy-level re-verification against current Microsoft product capabilities, and major version upgrades for components that changed substantially over the year.

This runbook is the longest of the three operational reviews. The scope spans the entire baseline and produces the most documentation. Organizations should treat the annual review as a scheduled project rather than routine operations, with dedicated calendar time and a specific deliverable package.

## Prerequisites

* Four consecutive quarterly reviews completed with documented outputs
* Operations runbook with one full year of review history
* Designated annual reviewer: security lead, MSP principal, or CISO-equivalent role with authority to make baseline-level decisions
* Leadership sponsor (executive or tenant owner) who receives the final deliverable
* Budget owner for any licensing adjustments the review may recommend

## Annual checklist

The review is organized into eight sections. Each section produces specific deliverables; together they form the annual posture package.

### Section 1: Baseline coverage re-verification (approximately 8 hours)

**Purpose:** Run every technical runbook's Verify-Deployment script and confirm each control remains in its target state.

| Item | Action |
|---|---|
| 1.1 | Execute every Verify-Deployment script in sequence (runbooks 01 through 16) |
| 1.2 | For each failing verification, investigate root cause and remediate |
| 1.3 | Produce a baseline coverage matrix: runbook, variant applicability, current state, any deviations |
| 1.4 | For each deviation from target state, document rationale or remediation plan |

Deliverable: Baseline coverage matrix with every control's current state.

### Section 2: Licensing review (approximately 4 hours)

**Purpose:** Confirm licensing matches deployed baseline and identify optimization opportunities.

| Item | Action |
|---|---|
| 2.1 | Pull current license inventory: every SKU, assigned count, unassigned count |
| 2.2 | Review Business Premium + add-on licensing (Defender Suite, E5 Security, EMS E5) against controls deployed |
| 2.3 | Identify controls that would benefit from add-on upgrade (for example, plain Business Premium tenant that would gain PIM by adding Defender Suite) |
| 2.4 | Identify over-licensing: users with E5 who only use Business Premium features |
| 2.5 | Compare annual licensing cost against deployed value; report ROI by control category |
| 2.6 | Plan licensing adjustments for the next fiscal year |

Deliverable: Licensing review report with recommended adjustments.

### Section 3: DKIM rotation and email authentication progression (approximately 2 hours)

| Item | Action |
|---|---|
| 3.1 | Rotate DKIM keys for every sending domain if not rotated within the past 12 months |
| 3.2 | Review DMARC policy progression across all domains: tenants that were in p=quarantine should be at p=reject by year-end |
| 3.3 | Review DMARC aggregate report trends: identify any new senders or changes in spoofing volume |
| 3.4 | Review SPF records: flatten includes if approaching 10-lookup limit, retire stale senders |
| 3.5 | Verify APNs and ABM renewal occurred on schedule; if not, renew immediately |

Deliverable: Email authentication posture with evidence of annual rotation.

### Section 4: Threat landscape and control effectiveness (approximately 6 hours)

**Purpose:** Review the year's security events and determine whether the baseline caught what it needed to catch.

| Item | Action |
|---|---|
| 4.1 | Pull the year's Defender XDR incident history |
| 4.2 | For each incident, document: what was the threat, which control caught it, how long until detection, how long until remediation |
| 4.3 | Identify incidents that were not caught by baseline alerts but were discovered through other means (user report, external notification): gap in detection coverage |
| 4.4 | Identify incidents where remediation took longer than target SLA: gap in response process |
| 4.5 | Review industry and adversary trends for the year: new techniques, new toolkits, new campaigns targeting SMBs |
| 4.6 | Identify baseline controls that would address newly-prevalent threats |

Deliverable: Threat effectiveness report with coverage gaps and tuning recommendations.

### Section 5: Policy version and product capability review (approximately 4 hours)

**Purpose:** Microsoft changes product capabilities continuously. Verify the baseline still uses current mechanisms, not deprecated ones.

| Item | Action |
|---|---|
| 5.1 | Review each technical runbook's policy definitions against current Microsoft documentation |
| 5.2 | Identify any control using a deprecated mechanism (for example, per-user MFA if it has not already been migrated) |
| 5.3 | Identify new Microsoft capabilities released in the past year that would strengthen the baseline |
| 5.4 | For each identified gap or opportunity, produce a change proposal for the next baseline update |
| 5.5 | Review the Conditional Access policy stack for any new policy templates Microsoft has published since baseline deployment |

Deliverable: Baseline-vs-current-capability gap report with proposed updates.

### Section 6: Incident response and business continuity review (approximately 4 hours)

| Item | Action |
|---|---|
| 6.1 | Review incident response procedures: are they current with baseline capabilities? |
| 6.2 | Run a break glass drill: planned sign-in of a break glass account, measure response time of the alert, investigate workflow |
| 6.3 | Rotate break glass passwords (annual rotation minimum, earlier if any suspicion of compromise) |
| 6.4 | Review backup and recovery posture: mailbox backup, OneDrive retention, SharePoint version history |
| 6.5 | Review the operations runbook: is it current, is it accessible, does the on-call administrator know where it is |
| 6.6 | Identify any single point of failure in operational knowledge: documentation gaps that would slow incident response |

Deliverable: IR/BC readiness report with drill outcomes and operational gap identification.

### Section 7: Governance and regulatory alignment (approximately 3 hours)

**Purpose:** Map baseline controls to current regulatory obligations.

| Item | Action |
|---|---|
| 7.1 | Identify applicable regulations for the organization: SOC 2, ISO 27001, HIPAA, PCI, GDPR, specific industry regimes |
| 7.2 | For each applicable regulation, produce a control mapping: which baseline controls satisfy which regulatory requirement |
| 7.3 | Identify regulatory requirements not covered by the baseline: gap analysis |
| 7.4 | Review upcoming regulatory changes: new regimes, amendments to existing regimes |
| 7.5 | Plan regulatory-driven baseline additions for the next year |

Deliverable: Regulatory control mapping with current coverage and planned additions.

### Section 8: Leadership presentation and baseline publication (approximately 4 hours)

**Purpose:** Present annual review findings to leadership and publish the updated baseline.

| Item | Action |
|---|---|
| 8.1 | Assemble the annual posture package: deliverables from Sections 1 through 7 |
| 8.2 | Produce an executive summary: baseline state, year's security events, trends, recommended investments |
| 8.3 | Present to leadership sponsor and any required audience (board, customer executive, MSP principal) |
| 8.4 | Capture leadership decisions on recommended investments |
| 8.5 | Publish updated baseline version with accepted changes incorporated |
| 8.6 | Archive the annual package with the previous year's archive |

Deliverable: Annual posture package; leadership decisions; updated baseline version.

## Automation artifacts

* `automation/powershell/19-Run-AnnualReview.ps1` - Executes automated portions and produces a consolidated input package for the reviewer
* `automation/powershell/19-Rotate-AllDKIM.ps1` - Bulk DKIM rotation for every sending domain
* `automation/powershell/19-Export-BaselineCoverage.ps1` - Produces the baseline coverage matrix for Section 1
* `automation/powershell/19-Export-LicensingReport.ps1` - Produces the licensing review report for Section 2

Manual sections (Section 4 threat review, Section 6 incident response, Section 7 regulatory, Section 8 leadership) cannot be automated; the scripts produce the data inputs and the reviewer interprets.

## Annual posture package contents

The final deliverable is a labeled archive containing:

```
[tenant]-annual-review-[YYYY].zip
├── 00-executive-summary.pdf           (Section 8)
├── 01-baseline-coverage-matrix.pdf    (Section 1)
├── 02-licensing-review.pdf            (Section 2)
├── 03-email-auth-posture.pdf          (Section 3)
├── 04-threat-effectiveness.pdf        (Section 4)
├── 05-capability-gap-report.pdf       (Section 5)
├── 06-ir-bc-readiness.pdf             (Section 6)
├── 07-regulatory-mapping.pdf          (Section 7)
├── 08-leadership-decisions.pdf        (Section 8)
└── raw-data/
    ├── verify-deployment-logs-*.txt
    ├── alert-activity-full-year.csv
    ├── device-inventory-snapshot.csv
    └── [other raw data exports]
```

Retain indefinitely. The archive is the year's evidence trail and the input to the next year's review.

## What to watch

* **Annual reviews that skip:** a year without an annual review is a year without strategic visibility. If the annual review is delayed more than one fiscal quarter, treat the delay itself as a finding and address it before continuing.
* **Annual review findings that become annual review findings again:** if the same gap appears in the annual review three years running without resolution, the baseline has accumulated technical debt that needs dedicated remediation project, not continued review.
* **Scope creep during the review:** items discovered during the annual review sometimes grow into remediation projects of their own. Resist rolling those projects into the review timeline; document the finding, scope the remediation separately, and complete the review on schedule.
* **Leadership decisions not captured:** the investment conversations that happen at the Section 8 presentation need documented outcomes. "We discussed upgrading to Defender Suite" is not a decision. "Leadership approved Defender Suite addition effective Q3 with $X budget" is a decision. Capture the distinction.
* **Baseline version drift between reviews:** the baseline should be updated continuously through the year, not only at the annual review. If the baseline at annual review time is significantly different from what is actually deployed, the maintenance cadence between reviews is broken.

## References

* Microsoft Learn: [Security baselines in Microsoft 365](https://learn.microsoft.com/en-us/security/privileged-access-workstations/overview)
* NIST Cybersecurity Framework 2.0 - ID, PR, DE, RS, RC function categories
* ISO 27001:2022 Annex A control review requirements
* SOC 2 continuous monitoring criteria
* CIS Controls v8 Implementation Group assessment
