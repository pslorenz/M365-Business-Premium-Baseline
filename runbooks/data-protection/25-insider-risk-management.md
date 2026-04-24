# 25 - Insider Risk Management

**Category:** Data Protection
**Applies to:**
* **Plain Business Premium:** Not available.
* **+ Defender Suite:** Not available. Insider Risk Management is a Purview capability.
* **+ Purview Suite:** Full Insider Risk Management including Adaptive Protection (dynamic DLP based on user risk).
* **+ Defender & Purview Suites:** Full IRM with richer signal from Defender telemetry.
* **+ EMS E5:** Not available.
* **M365 E5:** Full IRM with Administrative Unit scoping.

**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed
* [20 - Microsoft Purview Data Loss Prevention Baseline](./20-dlp-baseline.md) completed (required for Adaptive Protection)
* [21 - Sensitivity Labels Baseline](./21-sensitivity-labels-baseline.md) recommended

**Time to deploy:** 4 to 6 hours active work, plus 60 to 90 days observation before enforcement actions
**Deployment risk:** Medium-to-high from a privacy and HR perspective, low from a technical perspective. IRM monitors user behavior patterns; deployment requires coordination with HR and legal, privacy-reviewed policies, and clear escalation procedures. The technical deployment itself is well-bounded.

## Purpose

This runbook deploys Insider Risk Management, which monitors user behavior for patterns indicative of insider threats: data theft by departing employees, accidental data leaks, deliberate exfiltration by compromised or malicious insiders. IRM addresses a different threat category than DLP or DSPM for AI: DLP catches specific content patterns moving through specific channels; IRM catches behavioral patterns across multiple signals that indicate a risky user regardless of the specific content. An employee who downloads 500 files from OneDrive in the week before their resignation, emails 20 confidential documents to a personal address, and accesses HR records they rarely look at is producing signal across three channels that any individual channel might miss. IRM aggregates the signal and produces a risk score, with graduated response options from observation to investigation to active prevention.

The tenant before this runbook: insider threat detection is reactive. A departing employee exfiltrates customer data; it is discovered when the customer asks why a competitor has their contract. A compromised account moves files for weeks before someone notices. Disgruntled insiders have long windows of access because the behavior patterns are invisible until something triggers investigation. The audit log contains the evidence but nobody is looking at it proactively.

The tenant after: IRM continuously evaluates user behavior against configured policies. Three baseline policies cover the common insider threat categories: data theft by departing users (triggered by HR connector indicating termination or resignation), general data leaks (unusual download volumes, unusual external sharing), and priority user protection (stricter monitoring for users with access to highly sensitive content). Users with elevated risk scores receive graduated responses: observation in the policy (gather more signal), investigation case (security team review), and Adaptive Protection (automatic tightening of DLP enforcement for elevated-risk users).

Adaptive Protection is the significant capability that justifies IRM for most SMBs. Without Adaptive Protection, DLP is static: the same policies apply to everyone regardless of their risk profile. With Adaptive Protection, DLP enforcement automatically tightens for users whose risk score indicates concerning behavior. A user at minor risk sees warnings on sensitive data sharing; a user at moderate risk sees block-with-override; a user at elevated risk sees hard block on all sensitive content movement. The tightening reverts automatically when the risk score returns to normal. The effect is that IRM and DLP become a system that responds to user behavior rather than treating all users identically.

## Prerequisites

* Purview Suite or M365 E5 licensing
* Compliance Administrator or equivalent role
* **HR coordination.** IRM monitoring requires documented organizational policy and user notification. Involve HR and legal before deployment.
* **Privacy review.** IRM captures sensitive user behavior signals. Privacy impact assessment and user notification are typically required; specific requirements depend on jurisdiction (GDPR requires more formal process than US-only tenants).
* HR connector data source (optional but recommended): Azure AD attributes, CSV upload, or third-party HR system integration for employment status signals
* DLP baseline deployed (required for Adaptive Protection to function)
* Sensitivity labels deployed (strongly recommended; labels are signal in IRM scoring)
* Priority user list: employees with access to most sensitive data who warrant stricter monitoring (executives, HR leaders, legal team, IT administrators)

## Target configuration

At completion, the tenant has:

### Three baseline IRM policies

**Policy 1: Data Theft by Departing Users**

* **Scope:** Users flagged by HR connector as departing, terminated, or with submitted resignation
* **Trigger:** Employment status change
* **Monitored indicators:** Unusual file downloads, external sharing, unusual email with attachments, USB device usage, cloud storage synchronization to personal accounts
* **Observation window:** 30 days before departure date through 7 days after (accounts for pre-announcement activity and post-termination access attempts)
* **Risk score calculation:** Weighted indicators produce a risk score 0-100
* **Alert threshold:** Score >40 creates an IRM alert for investigation

**Policy 2: Data Leaks (General)**

* **Scope:** All users
* **Trigger:** No specific trigger; continuous evaluation
* **Monitored indicators:** External sharing anomalies, large-volume email activity, printing anomalies, USB activity, access to content outside normal pattern
* **Risk score calculation:** Baseline established per user from 30-day history; deviations produce score
* **Alert threshold:** Score >50 creates an IRM alert

**Policy 3: Priority User Protection**

* **Scope:** Users on the priority user list
* **Trigger:** Continuous evaluation with lower thresholds
* **Monitored indicators:** All indicators from Policy 2 plus access to Highly Confidential labeled content
* **Risk score calculation:** Same as Policy 2, with lower alert threshold
* **Alert threshold:** Score >30 creates an IRM alert
* **Rationale:** Users with access to the most sensitive data warrant closer monitoring; a priority user at moderate risk warrants investigation sooner than a non-priority user at the same score

### Adaptive Protection

* **Enabled:** Yes
* **Risk levels:** Minor (score 30-50), Moderate (50-70), Elevated (70+)
* **DLP policy actions per risk level:**
  * Minor: policy tips only
  * Moderate: block with override
  * Elevated: block without override
* **Scope:** All users covered by the baseline DLP policies from runbook 20

### HR connector

* **Data source:** Azure AD employee attributes or CSV upload
* **Required attributes:** Employee ID, employment status (active/departing/terminated), termination date, manager, department
* **Update cadence:** Daily (Azure AD sync) or weekly (CSV upload)

### Alert and investigation routing

* **IRM alerts:** Route to security admin and HR compliance contact
* **High-severity alerts (priority users, elevated risk):** Additionally route to legal counsel
* **Investigation cases:** Security admin creates and owns; HR partners on any action with employment implications

## Deployment procedure

### Step 1: Coordinate organizational readiness

This step has no PowerShell artifact. Before technical deployment:

* Review IRM with HR and legal for policy and notification requirements
* Update employee handbook with insider risk monitoring language
* Plan user communication regarding monitoring scope
* Identify HR compliance contact for investigation partnering
* Identify legal contact for high-severity case escalation

### Step 2: Verify licensing and enable IRM

```powershell
./25-Verify-IRMLicensing.ps1
./25-Enable-IRM.ps1
```

The Enable script turns on IRM in the Purview compliance portal and configures baseline settings: anonymization (user names displayed as pseudonyms until an investigation is opened), retention of analytics data, default administrative scope.

### Step 3: Configure HR connector

```powershell
./25-Configure-HRConnector.ps1 `
    -ConnectorType "AzureAD" `
    -Attributes @("EmployeeId","EmployeeStatus","TerminationDate","Manager","Department")
```

For tenants without synchronized HR attributes in Azure AD, the CSV upload path:

```powershell
./25-Configure-HRConnector.ps1 `
    -ConnectorType "CSV" `
    -CSVPath "./hr-data-template.csv"
```

The CSV template ships with the script; fields are Employee ID, Employee Status (active/terminated/resigned), Effective Date, Manager ID, Department.

### Step 4: Deploy the three baseline policies

```powershell
./25-Deploy-IRMPolicies.ps1 `
    -NotificationEmail "insider-risk@contoso.com" `
    -LegalEscalationEmail "legal@contoso.com" `
    -PriorityUserGroup "Priority Users"
```

The script creates Data Theft by Departing Users, Data Leaks, and Priority User Protection policies with the target configuration. Policies start in monitoring mode with observation thresholds configured; alert generation is enabled from day one.

### Step 5: Enable Adaptive Protection

```powershell
./25-Enable-AdaptiveProtection.ps1
```

The script enables Adaptive Protection and configures the risk level actions. Adaptive Protection modifies DLP enforcement on a per-user basis based on current risk score; the DLP policies from runbook 20 acquire per-user behavior driven by IRM scoring.

### Step 6: Configure priority users

```powershell
./25-Set-PriorityUsers.ps1 `
    -GroupName "Priority Users" `
    -Members @("ceo@contoso.com","cfo@contoso.com","hr-director@contoso.com","legal-counsel@contoso.com","it-admin@contoso.com")
```

The script populates the priority user group that drives the Priority User Protection policy. Review the list quarterly (runbook 18) to add or remove users as organizational roles change.

### Step 7: Observe for 60 to 90 days

```powershell
./25-Monitor-IRMActivity.ps1 -LookbackDays 30
```

IRM requires a longer observation period than DLP because the risk score calculation depends on establishing baseline user behavior over weeks. The first 30 to 60 days produce calibration data; alerts during this period may reflect baseline variation rather than actual risk. Review alerts with HR compliance for pattern understanding; tune policies as needed.

Common tuning:

* **Normal behavior flagged as risky.** Some users routinely perform actions (bulk downloads for legitimate backup, external sharing with customers for contracted service delivery) that IRM initially flags. Create policy exceptions for documented business patterns.
* **Departing user alerts without HR context.** If the HR connector is not configured or is stale, the Data Theft by Departing Users policy has no trigger. Verify HR data is flowing.
* **Score thresholds producing too many alerts.** Lower the alert threshold temporarily during tuning; observe which indicators are driving alerts; raise threshold once normal activity is understood.

### Step 8: Transition Adaptive Protection to active enforcement

After 60 to 90 days, the Adaptive Protection actions (policy tip, block with override, block without override) take effect based on user risk scores. No explicit transition step; Adaptive Protection is active from enablement, but its impact is minimal until risk scores accumulate signal over time.

### Step 9: Establish investigation process

IRM alerts become investigation cases; cases become actions. Document the process:

* Alert review SLA (24 hours for priority user alerts, 72 hours for standard)
* Investigation case ownership (security admin leads, HR partners)
* Evidence preservation procedures (preserve mailbox, OneDrive, SharePoint activity)
* Action options (monitor, interview, discipline, termination, legal referral)
* Communication with the investigated user (typically not disclosed during investigation; disclosure follows HR process)

### Step 10: Document the IRM posture

Update the operations runbook:

* Policies deployed and their thresholds
* HR connector source and update cadence
* Priority user list (maintained separately; referenced here)
* Adaptive Protection actions
* Alert routing and investigation SLAs
* Quarterly review cadence for tuning and priority user list updates

## Automation artifacts

* `automation/powershell/25-Verify-IRMLicensing.ps1` - License verification
* `automation/powershell/25-Enable-IRM.ps1` - Enables IRM feature and baseline settings
* `automation/powershell/25-Configure-HRConnector.ps1` - HR data source configuration
* `automation/powershell/25-Deploy-IRMPolicies.ps1` - Creates the three baseline policies
* `automation/powershell/25-Enable-AdaptiveProtection.ps1` - Configures Adaptive Protection
* `automation/powershell/25-Set-PriorityUsers.ps1` - Priority user group management
* `automation/powershell/25-Monitor-IRMActivity.ps1` - Alert and case reporting
* `automation/powershell/25-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/25-Rollback-IRM.ps1` - Disables IRM and removes policies

## Verification

### Configuration verification

```powershell
./25-Verify-Deployment.ps1
```

Expected output covers IRM feature state, policy existence, Adaptive Protection configuration, HR connector health, and priority user group membership.

### Functional verification

Functional testing for IRM is inherently slow because the capability depends on accumulated behavioral signal. Near-term functional checks:

1. **Policies active.** All three baseline policies appear as Active in the Purview portal.
2. **HR connector healthy.** The connector reports successful data import within the past 24 hours (Azure AD) or 7 days (CSV).
3. **Priority user group populated.** The priority user group contains the expected members.
4. **Adaptive Protection enabled.** The Adaptive Protection page in Purview shows active configuration.
5. **Alert generation active.** Any baseline alerts from the initial observation period are visible (this may take days to weeks after enablement).

Longer-term verification:

* Simulate a departing user scenario (test account, flagged as departing in HR data, performs high-volume download) to verify Data Theft policy triggers. This is a controlled test and should be coordinated with HR compliance.
* Simulate a data leak scenario (test account performs external sharing in excess of typical pattern) to verify Data Leaks policy triggers.

## Additional controls (add-on variants)

### Additional controls with Defender Suite integration

Defender for Cloud Apps, Defender for Identity, and Defender for Endpoint (all part of Defender Suite) provide additional signal to IRM scoring:

* **Cloud Apps:** OAuth app consents, SaaS activity anomalies
* **Identity:** Lateral movement attempts, Kerberoasting, on-prem AD anomalies
* **Endpoint:** Suspicious process execution, unusual file system activity, USB device writes

IRM with Defender Suite signal produces higher-fidelity scoring than IRM alone. For tenants with both suites, IRM is measurably more effective.

### Additional controls with E5 Compliance (not in Purview Suite)

**Administrative Unit scoping.** IRM policies in E5 Compliance can target specific AUs (e.g., stricter monitoring for finance, relaxed for marketing). Purview Suite applies policies tenant-wide.

**Advanced investigation capabilities.** E5 Compliance adds richer case management, content search within cases, and integration with advanced eDiscovery. Purview Suite has case management; E5 Compliance has more mature case workflow.

### Regulatory and legal considerations

IRM is a monitoring capability that collects behavioral signals including content access patterns, email sending patterns, file operations, and device activity. Deployment touches privacy law and employment law:

* **GDPR jurisdictions.** Require documented purpose, lawful basis, user notification, and data subject rights procedures. Legitimate interest is the typical lawful basis but requires a balancing test.
* **US employment law.** Varies by state. Electronic monitoring disclosure is required in some states (Connecticut, Delaware, New York, others). Employee handbook language typically covers the requirement.
* **Union-represented workforce.** Collective bargaining agreements may constrain monitoring scope and data use. Legal review required before deployment in union environments.
* **Cross-border operations.** Data flows from employees in one jurisdiction to administrators in another create transfer concerns. Standard contractual clauses or equivalent transfer mechanism typically required.

These are not technical barriers; they are organizational prerequisites. Technical deployment proceeds when the organizational readiness is complete.

## What to watch after deployment

* **Alert volume in the first 90 days.** Alerts accumulate quickly as risk scores calibrate. Most early alerts reflect baseline variation rather than actual risk. Resist the impulse to tune aggressively in the first 30 days; wait for the calibration period to complete before making policy changes.
* **Priority user list drift.** Executive changes, role changes, and organizational restructuring make the priority user list stale. Review quarterly at minimum.
* **HR connector staleness.** CSV-based HR connectors rely on manual upload; these fall behind during transitions, holidays, and staffing changes. Azure AD-based connectors stay current but depend on the underlying data quality in Azure AD. Monitor connector health.
* **Investigation workload.** IRM produces investigation cases that require human review. Organizations without investigation capacity accumulate unreviewed cases, defeating the purpose. Budget investigation time when deploying IRM.
* **Employee relations impact.** Users who learn of IRM monitoring may react negatively if the communication was not clear. Proactive, organization-wide communication about monitoring scope (what is monitored, what is not, why, who has access) reduces surprise reactions.
* **Adaptive Protection user experience.** A user with moderate or elevated risk score experiences DLP that feels stricter than their colleagues. Without context, this feels like system malfunction. The user's helpdesk calls can reveal IRM scoring indirectly. Consider whether and how to communicate Adaptive Protection to users.
* **False positive consequences.** An IRM false positive can affect an employee's relationship with the organization. Investigation procedures should require corroborating evidence beyond the IRM score before actions with employment consequences.

## Rollback

```powershell
./25-Rollback-IRM.ps1 -Reason "Documented reason"
```

Rollback considerations:

* **IRM data is retained in the Purview compliance system.** Disabling IRM does not delete historical alerts, cases, or analytics data. Data retention follows the tenant's Purview retention settings.
* **Adaptive Protection reverts DLP to static behavior.** Users at elevated risk return to standard DLP enforcement immediately on Adaptive Protection disablement.
* **HR connector data remains.** HR data imported during IRM operation remains in the tenant until explicitly purged.

Rollback is rarely appropriate given the deployment investment and organizational involvement. Common alternative: narrow policy scope, lower thresholds, or temporary observation-only mode during tuning.

## References

* Microsoft Learn: [Learn about insider risk management](https://learn.microsoft.com/en-us/purview/insider-risk-management)
* Microsoft Learn: [Configure insider risk management policies](https://learn.microsoft.com/en-us/purview/insider-risk-management-configure)
* Microsoft Learn: [Adaptive Protection in Microsoft Purview](https://learn.microsoft.com/en-us/purview/insider-risk-management-adaptive-protection)
* Microsoft Learn: [HR connector for insider risk management](https://learn.microsoft.com/en-us/purview/import-hr-data)
* M365 Hardening Playbook: [No insider risk monitoring](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/no-insider-risk.md) (pending)
* CIS Microsoft 365 Foundations Benchmark v4.0: Insider risk recommendations
* NIST CSF 2.0: DE.AE-02, DE.CM-03, RS.AN-01
