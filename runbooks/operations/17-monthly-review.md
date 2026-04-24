# 17 - Monthly Review Checklist

**Category:** Operations
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* All baseline runbooks deployed and in steady-state operation
**Time to complete:** 2 to 3 hours
**Cadence:** Monthly, first Monday or a documented standing date

## Purpose

This runbook defines the monthly review cadence that keeps the deployed baseline operational. A tenant that completes the technical runbooks (01 through 16) has excellent point-in-time posture; without a monthly review rhythm, that posture degrades predictably within 6 to 12 months. Exception lists accumulate, alert tuning drifts, new administrators get provisioned without proper tier classification, travel exceptions expire without being removed, admin accounts forget MFA registration, and the baseline slowly becomes a snapshot of what was true once rather than a living configuration.

The monthly review is the shortest of the three cadences (monthly, quarterly, annual) and focuses on the highest-frequency drift: exception cleanup, alert triage, sign-in anomaly review, and recent-change verification. The quarterly and annual reviews cover deeper audits (tier reclassification, access reviews, policy-level verification). The three cadences layered together produce the baseline that remains aligned with reality over time.

This runbook is deliberately short and prescriptive. Monthly reviews that take more than 3 hours do not get done reliably; monthly reviews that are checklist-driven rather than narrative get done even when the administrator on duty changes. Every item in this runbook is a specific action with a documented outcome. If an item takes longer to complete than its allotted time, that item becomes a quarterly or ad-hoc item rather than remaining in the monthly cadence.

## Prerequisites

* All technical runbooks deployed (01 through 16 as applicable to the variant)
* Operations runbook is the reference for where exceptions, administrators, and review outcomes are documented
* Designated reviewer: a named individual with the required roles (Security Administrator or higher) responsible for completing the review
* Previous month's review notes available for comparison

## Monthly checklist

The review is organized into five sections matching the major runbook categories. Each section has 2 to 5 items; each item has a specific action and a verification signal.

### Section 1: Identity and access (approximately 20 minutes)

| Item | Action | Verification |
|---|---|---|
| 1.1 | Review the admin audit (tier group memberships) for any new additions in the past month | `./03-Audit-AdminAssignments.ps1` output compared against operations runbook roster |
| 1.2 | Confirm every tier-0 and tier-1 admin still has phishing-resistant MFA registered | `./06-Check-AdminMFA.ps1` reports zero gaps |
| 1.3 | Review break glass account access: confirm no unplanned sign-ins in the past month | Entra ID sign-in logs filtered to break glass UPNs |
| 1.4 | Review PIM activation logs for tier-0 activations: confirm each had approved justification | Entra PIM audit; investigate any activation without corresponding change ticket |
| 1.5 | Review new user provisioning: confirm each new user assigned to appropriate Conditional Access scope (not excluded incorrectly) | Manual review of new accounts in past month |

### Section 2: Conditional Access (approximately 15 minutes)

| Item | Action | Verification |
|---|---|---|
| 2.1 | Confirm CA policy state: every policy from Runbook 02 is enabled (not report-only, not disabled) | `./02e-Verify-CABaseline.ps1` output |
| 2.2 | Review travel exception group: expire any entries past their end date | `./05-Review-TravelExceptions.ps1` |
| 2.3 | Review CA policy modifications in the past month: verify each change was planned | Entra audit log filtered to CA policy operations; cross-reference to change tickets |
| 2.4 | Confirm named location country list matches current operations | `./05-Review-AllowedCountries.ps1` output; compare against any new offices or remote-employee locations |

### Section 3: Device compliance (approximately 15 minutes)

| Item | Action | Verification |
|---|---|---|
| 3.1 | Review Windows compliance rate; investigate drop below 90% | `./08-Monitor-WindowsCompliance.ps1` |
| 3.2 | Review mobile compliance rate; investigate drop below 85% | `./09-Monitor-MobileCompliance.ps1` |
| 3.3 | Confirm Autopilot profile provisioned new devices successfully in the past month | Intune admin center: new device enrollment success rate |
| 3.4 | Confirm no devices have been non-compliant for more than 30 days without remediation ticket | Intune non-compliant device report |

### Section 4: Email protection (approximately 20 minutes)

| Item | Action | Verification |
|---|---|---|
| 4.1 | Review quarantine release requests from the past month: investigate any pattern suggesting false positives or social engineering | Purview quarantine activity report |
| 4.2 | Review impersonation protection events: confirm protected users/domains list still matches current personnel and partners | `./11-Update-ImpersonationList.ps1` as needed |
| 4.3 | Check APNs certificate expiration: alert if under 60 days remaining | `./09-Verify-MobileInfrastructure.ps1` |
| 4.4 | Review Safe Attachments redirect mailbox: triage any malicious attachments accumulated; extract threat intelligence for submission | Manual mailbox review |
| 4.5 | Review DMARC aggregate report summary: confirm pass rates remain high; investigate new sending infrastructures | DMARC analyzer or `./13-Analyze-DMARCReports.ps1` |

### Section 5: Audit and alerting (approximately 30 minutes)

| Item | Action | Verification |
|---|---|---|
| 5.1 | Review alert firing activity; identify rules firing excessively (noise) or silently (potentially broken) | `./16-Review-AlertActivity.ps1 -LookbackDays 30` |
| 5.2 | For each alert fired in the past month, confirm triage outcome was documented | Operations runbook alert response log |
| 5.3 | Verify UAL is capturing events (no gap in ingestion) | `./14-Test-AuditSearch.ps1` returns recent results |
| 5.4 | Review any Defender XDR incidents closed as false positive: identify if rule tuning is warranted | Defender portal incident history |
| 5.5 | Confirm security admin distribution list is being actively monitored (at least one person has read recent alerts) | Self-attestation by reviewer |

## Automation artifacts

* `automation/powershell/17-Run-MonthlyReview.ps1` - Executes the automated portions of the checklist and produces a consolidated report

Manual portions of the review cannot be automated meaningfully: decisions about whether an audit event was authorized, whether a new administrator should have their tier, whether an exception is still justified. The script handles the data-collection portion and produces a report that the reviewer uses to guide the human-judgment portion.

## Report format

The review produces a monthly report stored in the operations runbook. The report template:

```
M365 Baseline Monthly Review - [YYYY-MM]
==========================================
Reviewer: [name]
Review date: [date]
Tenant: [tenant identifier]

Section 1: Identity and access
  1.1 Admin audit: [N] changes since last review, [approved/unapproved]
  1.2 Phishing-resistant MFA: [N] admins, [all covered/gaps noted]
  1.3 Break glass sign-ins: [N planned, N unplanned] (investigate if unplanned > 0)
  1.4 Tier-0 PIM activations: [N], all with justification? [Yes/No]
  1.5 New user provisioning: [N new users], all scoped correctly? [Yes/No]

Section 2: Conditional Access
  2.1 CA policy state: all enforcing [Yes/No]
  2.2 Travel exceptions: [N active, N expired this month]
  2.3 CA modifications: [N changes], all planned? [Yes/No]
  2.4 Allowed-countries list: still aligned with operations? [Yes/No]

Section 3: Device compliance
  3.1 Windows compliance rate: [percent]%
  3.2 Mobile compliance rate: [percent]%
  3.3 Autopilot provisioning: [N successful, N failed]
  3.4 Long-term non-compliant devices: [N]

Section 4: Email protection
  4.1 Quarantine release requests: [N], any patterns? [Yes/No]
  4.2 Impersonation list current? [Yes/No]
  4.3 APNs days until expiration: [N]
  4.4 Safe Attachments redirects processed: [N]
  4.5 DMARC pass rate: [percent]%

Section 5: Audit and alerting
  5.1 Alert activity: [N alerts, N noisy rules identified]
  5.2 Alert triage outcomes documented: [Yes/No]
  5.3 UAL ingestion healthy? [Yes/No]
  5.4 Closed-false-positive incidents: [N], tuning warranted? [Yes/No]
  5.5 Alert destination actively monitored? [Yes/No]

Action items this month:
  [List of items requiring follow-up, assigned owner, target date]

Next review: [date]
```

## What to watch

* **Review completion rate:** the monthly review gets done reliably when there is a named reviewer, a fixed calendar slot, and a 3-hour time budget. Review completion rates below 80% per year indicate the cadence is not sustainable; reduce scope or reassign responsibility.
* **Action item aging:** items identified in one month should be closed by the next month. Items that carry over 3 or more months suggest either the item is beyond monthly scope (promote to quarterly) or the ownership is unclear.
* **Metrics trending the wrong direction:** compliance rate dropping steadily, alert volume rising steadily, impersonation list falling behind personnel changes. Monthly reviews catch trends before they become problems; ignoring the trend is worse than missing a single review.
* **Reviewer turnover:** the monthly review is only as good as the reviewer's familiarity with the tenant. When the reviewer changes, allocate extra time for the first 2 reviews and pair with the outgoing reviewer on handoff.

## References

* M365 Hardening Playbook: [Exception list drift detection](https://github.com/pslorenz/m365-hardening-playbook/blob/main/conditional-access/mfa-policy-group-exclusion-drift.md)
* CIS Controls v8: Control 14 (Security Awareness and Skills Training) includes operational review requirements
* NIST CSF 2.0: GV.SC-03, ID.GV-04
