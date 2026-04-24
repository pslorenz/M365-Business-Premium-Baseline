# 16 - Alert Rules for High-Signal Events

**Category:** Audit and Alerting
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](./14-ual-verification-retention.md) completed
* [15 - Defender XDR and Sentinel Baseline Ingestion](./15-defender-xdr-sentinel-ingestion.md) completed with one path selected
**Time to deploy:** 90 to 180 minutes active work, plus 14 to 30 days of tuning
**Deployment risk:** Low. Alert rules are additive and can be tuned or disabled if they produce noise.

## Purpose

This runbook deploys the specific alert rules that catch the attack patterns that hit SMB tenants. Generic alerting catches generic threats; the detections here target the patterns that produce actual tenant compromise in the SMB space: privilege escalation through role assignment, mailbox rule creation after account compromise, OAuth consent grants to malicious applications, Conditional Access policy tampering, break glass account activity, service principal credential additions, and sign-in anomalies against privileged accounts.

The tenant before this runbook: signals flow to the platform selected in Runbook 15 (Defender XDR, Sentinel, or built-in alert policies). Microsoft's default alerts catch some of the attack patterns but miss others: Defender XDR does not natively alert on every PIM activation, does not distinguish between legitimate and suspicious mailbox rules, and does not correlate specific patterns like "same user receives phishing and then creates a forwarding rule within an hour."

The tenant after: approximately 20 custom detection rules target the high-signal events. Each rule has a documented threat model (what pattern it catches), a tested query (KQL for Defender XDR and Sentinel; audit search for alert policies), an expected noise rate (zero to low for well-tuned rules), and a runbook entry describing the response procedure when the alert fires.

The detections in this runbook are deliberately conservative in volume. A tenant with 20 well-tuned high-signal alerts that rarely produce false positives is more operationally useful than a tenant with 200 noisy alerts where the real signals get buried. This runbook prioritizes signal-to-noise over comprehensiveness.

## Prerequisites

* Runbook 14 complete: UAL enabled with appropriate retention
* Runbook 15 complete: one ingestion path chosen and configured
* List of named break glass accounts (from Runbook 01)
* List of named tier-0 administrator accounts (from Runbook 03)
* List of named high-value mailboxes (executives, finance, HR) protected by impersonation (from Runbook 11)
* Security admin distribution list or mailbox that receives alerts

## Target configuration

At completion, the tenant has approximately 20 alert rules covering:

**Privileged access (5 rules):**

* Break glass account sign-in (any location, any time)
* Privileged role assigned outside PIM workflow
* Tier-0 role activated outside business hours (P2 only)
* Conditional Access policy modified
* Security default changed or tenant security settings modified

**Identity and sign-in (4 rules):**

* Sign-in from a country not in the allowed countries list (despite CA006)
* Sign-in to break glass account with failed MFA (attempted compromise)
* Sign-in risk detection elevated (P2 Identity Protection)
* User password change by admin (possible compromise preparation)

**Mail flow and compromise (5 rules):**

* Mailbox forwarding or redirect rule created
* Inbox rule with external domain targets
* Bulk message deletion by a single user (possible cleanup after compromise)
* Safe Links block followed by user click-through
* High volume of messages sent in short window by a single user

**Applications and consent (3 rules):**

* OAuth consent grant to a non-verified application
* Service principal credential added
* Application permission scope added or elevated

**Data access (3 rules):**

* Large-volume file download from SharePoint or OneDrive by a single user
* External user granted access to large file set
* eDiscovery search initiated by non-eDiscovery-role user

The specific rule implementation varies by platform (Defender XDR custom detection, Sentinel analytics rule, or Purview alert policy) but the threat model is identical.

## Deployment procedure

### Step 1: Confirm platform selection

```powershell
./16-Confirm-AlertPlatform.ps1
```

The script detects the configured ingestion platform from Runbook 15 and reports which rule deployment path applies:

* Defender XDR: rules deploy as custom detection rules via Graph API
* Sentinel: rules deploy as analytics rules in the configured workspace
* Alert policies: rules deploy as Purview alert policies

Deploy rules in the corresponding path.

### Step 2: Deploy privileged access alerts

```powershell
./16-Deploy-PrivilegedAccessAlerts.ps1 `
    -Platform "DefenderXDR" `
    -BreakGlassUPNs @("breakglass01@contoso.onmicrosoft.com", "breakglass02@contoso.onmicrosoft.com") `
    -NotificationEmail "security-alerts@contoso.com"
```

The script deploys the five privileged access detection rules. Each rule includes:

* Display name with the detection identifier (PA-001 through PA-005)
* Query or filter definition specific to the platform
* Severity assignment (High for all privileged access alerts)
* Notification target (the specified email)
* Response guidance embedded in the rule description

Example rule: **Break glass account sign-in (PA-001)**

Query (Defender XDR KQL):
```kql
IdentityLogonEvents
| where Timestamp > ago(5m)
| where AccountUpn in ("breakglass01@contoso.onmicrosoft.com", "breakglass02@contoso.onmicrosoft.com")
| where ActionType == "LogonSuccess"
| project Timestamp, AccountUpn, IPAddress, DeviceName, LogonType, ISP, Country
```

Severity: High. Every break glass sign-in produces an alert regardless of context; the correct response is to confirm the sign-in was planned and approved, then investigate as an incident if not.

### Step 3: Deploy identity and sign-in alerts

```powershell
./16-Deploy-IdentitySignInAlerts.ps1 `
    -Platform "DefenderXDR" `
    -NotificationEmail "security-alerts@contoso.com"
```

The script deploys the four identity and sign-in detection rules (IS-001 through IS-004).

Example rule: **Sign-in from country not in allowed list (IS-001)**

This rule catches sign-ins from countries not in the allowed-countries list even if CA006 is correctly enforcing. The detection fires when CA006 was bypassed (travel exception, legacy auth evasion) or when an administrator inadvertently expanded the allowed list. The alert is informational severity by default; tenants with strict travel patterns may raise to Medium.

Query pattern:
```kql
SigninLogs
| where TimeGenerated > ago(5m)
| where Location !in ("US", "CA", "GB", "MX")   // Adjust to tenant's allowed list
| where ResultType == 0   // Successful sign-in
| where AppDisplayName in ("Office 365", "Microsoft Teams", "SharePoint Online")
| project TimeGenerated, UserPrincipalName, Location, IPAddress, AppDisplayName
```

### Step 4: Deploy mail flow and compromise alerts

```powershell
./16-Deploy-MailCompromiseAlerts.ps1 `
    -Platform "DefenderXDR" `
    -NotificationEmail "security-alerts@contoso.com"
```

The script deploys the five mail flow and compromise detection rules (MC-001 through MC-005).

The most operationally valuable rule in this category is **Mailbox forwarding or redirect rule created (MC-001)**. This is the highest-fidelity indicator of account compromise in M365: attackers who compromise a mailbox almost always create a forwarding or redirect rule to exfiltrate mail. Microsoft's built-in alert catches some cases but has specific gaps (rules that forward to addresses within approved domains, rules with obscured recipient strings); this custom detection catches the broader pattern.

Query pattern:
```kql
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType in ("New-InboxRule", "Set-InboxRule", "New-TransportRule")
| where RawEventData has_any ("ForwardTo", "RedirectTo", "ForwardAsAttachmentTo")
| extend TargetAddresses = tostring(RawEventData.Parameters)
| project Timestamp, AccountUpn, ActionType, TargetAddresses, ObjectName
```

### Step 5: Deploy applications and consent alerts

```powershell
./16-Deploy-AppConsentAlerts.ps1 `
    -Platform "DefenderXDR" `
    -NotificationEmail "security-alerts@contoso.com"
```

The script deploys the three applications and consent detection rules (AP-001 through AP-003).

Example rule: **OAuth consent grant to a non-verified application (AP-001)**

Query pattern:
```kql
CloudAppEvents
| where Timestamp > ago(15m)
| where ActionType == "Consent to application."
| where RawEventData.IsMSAApp != "true"
| where RawEventData.PublisherVerificationInfo == ""
| project Timestamp, AccountUpn, ObjectName, ApplicationId, RawEventData
```

This rule catches the consent-grant portion of the illicit consent grant attack pattern, where an attacker-controlled application requests delegated permissions from users. Verified publisher status is not a guarantee of benignity but unverified publisher status combined with consent grants from multiple users in a short window is a strong indicator.

### Step 6: Deploy data access alerts

```powershell
./16-Deploy-DataAccessAlerts.ps1 `
    -Platform "DefenderXDR" `
    -NotificationEmail "security-alerts@contoso.com"
```

The script deploys the three data access detection rules (DA-001 through DA-003).

Example rule: **Large-volume file download from SharePoint or OneDrive (DA-001)**

Query pattern:
```kql
CloudAppEvents
| where Timestamp > ago(1h)
| where ActionType in ("FileDownloaded", "FileSyncDownloadedFull", "FileSyncDownloadedPartial")
| summarize DownloadCount=count(), UniqueFiles=dcount(ObjectName) by AccountUpn, bin(Timestamp, 15m)
| where DownloadCount > 200 or UniqueFiles > 100
| project Timestamp, AccountUpn, DownloadCount, UniqueFiles
```

The 200-download / 100-unique-file threshold is deliberately conservative. Legitimate bulk operations (backup, migration, repository export) produce these patterns and will false-positive initially; tune after observation to a threshold that catches anomalous patterns without catching routine operations. Document the tuning in the operations runbook.

### Step 7: Configure response playbooks

Each alert rule includes a response guidance section, but the response workflow itself should be documented. For each alert category, document:

* Who receives the alert (named individual or role)
* Response SLA (how quickly is the alert triaged)
* Initial triage steps (what information to gather before escalating)
* Escalation path (when does the alert become an incident)
* Resolution documentation (where is the outcome recorded)

For tenants with Defender XDR Plan 2 and the full Defender suite, Automated Investigation and Response can execute the initial triage automatically for specific alert patterns. For tenants with simpler licensing, manual triage from the notification email is the baseline response.

### Step 8: Observe and tune for 14 to 30 days

```powershell
./16-Review-AlertActivity.ps1 -LookbackDays 14
```

The script reports alert firing patterns for each deployed rule:

* Total alerts fired
* False positive rate (based on documented triage outcomes)
* True positive rate
* Rules that fired zero times (candidates for review; may be correctly suppressing noise, or may be broken)

Tune based on observations:

* Rules firing many times with low true-positive rate: tighten the query conditions, raise volume thresholds, or add exclusions for known-benign patterns
* Rules firing zero times: verify the query against known-triggering events to confirm the rule is functional; if the pattern simply does not occur in this tenant, the rule is working correctly
* Rules with moderate volume and moderate true-positive rate: this is the right balance; leave in place

### Step 9: Document the alert catalog

Update the operations runbook with the deployed rule catalog:

* Rule identifier (PA-001, IS-001, MC-001, etc.)
* Threat model (what pattern it catches)
* Query definition
* Severity and notification destination
* Response procedure
* Last tuning date and current tuning parameters

The catalog is the reference for everyone involved in alert response. Without the catalog, new administrators receive alerts they do not understand and cannot triage effectively.

## Automation artifacts

* `automation/powershell/16-Confirm-AlertPlatform.ps1` - Detects the configured alert platform
* `automation/powershell/16-Deploy-PrivilegedAccessAlerts.ps1` - Deploys privileged access detection rules
* `automation/powershell/16-Deploy-IdentitySignInAlerts.ps1` - Deploys identity and sign-in detection rules
* `automation/powershell/16-Deploy-MailCompromiseAlerts.ps1` - Deploys mail flow and compromise detection rules
* `automation/powershell/16-Deploy-AppConsentAlerts.ps1` - Deploys applications and consent detection rules
* `automation/powershell/16-Deploy-DataAccessAlerts.ps1` - Deploys data access detection rules
* `automation/powershell/16-Review-AlertActivity.ps1` - Reports alert firing and tuning candidates
* `automation/powershell/16-Verify-Deployment.ps1` - Confirms rule deployment across categories
* `automation/powershell/16-Disable-AlertRule.ps1` - Disables a specific rule (tuning or rollback)

## Verification

### Configuration verification

```powershell
./16-Verify-Deployment.ps1
```

Expected output: rule count by category, each rule's enabled/disabled state, notification destinations, last trigger time per rule.

### Functional verification

1. **Break glass sign-in triggers alert.** Sign in as a break glass account (planned test), confirm alert fires within 5 minutes and reaches the configured destination.
2. **Test inbox rule triggers alert.** Create a test inbox rule with an external forwarding target (using a test account), confirm MC-001 fires within 15 minutes.
3. **Test OAuth consent grant triggers alert.** In a test scenario, grant consent to a non-verified application, confirm AP-001 fires.
4. **Alert destination receives messages.** Confirm the configured destination has received alert notifications since deployment. If the tenant has been active for 14 days with zero alerts in the destination, the configuration is wrong.

## Additional controls (add-on variants)

### Additional controls with Defender Suite, E5 Security, or E5 (Defender XDR Custom Detection Rules)

Plan 2 Defender licensing enables custom detection rules in Defender XDR with full query capability against advanced hunting tables. The rules deployed in this runbook use this capability directly. Plain Business Premium tenants without Plan 2 deploy the detections via Purview alert policies, which offer less expressive detection logic but catch most of the same patterns.

### Additional controls with Identity Protection (P2)

Entra ID P2 adds sign-in risk and user risk detections that feed into Defender XDR. For tenants with P2 licensing, the Identity Protection risk events automatically produce alerts through Defender XDR without requiring custom detection rules. The rules in this runbook complement Identity Protection rather than duplicating it.

### Additional controls with Sentinel

Sentinel-based deployments can use Fusion rules (multi-source correlation) and UEBA (user and entity behavior analytics) in addition to the discrete rules in this runbook. These are Sentinel-specific capabilities and are configured through the Sentinel portal; this runbook focuses on discrete detection rules that work across platforms.

## What to watch after deployment

* **Alert fatigue after 30 days.** If the destination inbox is producing more alerts than can be reviewed, triage workload is exceeding capacity. Either add reviewers, tighten rule queries, or adjust severity to reduce notification frequency. Do not simply stop reviewing; the control depends on someone actually looking at the alerts.
* **New tenant activity patterns that break tuning.** New project launches, seasonal business patterns, office reopenings, merger or acquisition activity produce changes in baseline behavior. Quarterly review of the alert rules against current baseline catches when tuning has drifted out of alignment.
* **Defender XDR quota for custom detection rules.** Defender for Office Plan 2 permits 50 custom detection rules; E5 permits 100. Approaching the quota may require consolidating rules or prioritizing high-value detections.
* **Query failures due to schema changes.** Microsoft occasionally changes advanced hunting table schemas; rules using deprecated column names fail silently. Review rule health in the Defender portal or via the Verify script monthly.
* **Response time from alert to action.** The most important metric is time from alert fire to first triage. For high-severity alerts (break glass sign-in, privileged role assignment, OAuth consent to unverified app) the target should be under 30 minutes. For medium severity, under 4 hours. Measure and track.

## Rollback

Per-rule rollback:

```powershell
./16-Disable-AlertRule.ps1 -RuleId "PA-001" -Reason "Documented reason"
```

The script disables the specific rule but keeps the definition in place; re-enable is a single command. Use disable rather than delete when the rule is temporarily producing noise and may be re-enabled after upstream tuning.

Full rollback of the runbook:

```powershell
./16-Rollback-AllAlertRules.ps1 -Reason "Documented reason for full rollback"
```

The script disables all rules deployed by the runbook. Rarely appropriate; the correct response to alerting issues is per-rule tuning, not wholesale rollback.

## References

* Microsoft Learn: [Create and manage custom detection rules](https://learn.microsoft.com/en-us/defender-xdr/custom-detection-rules)
* Microsoft Learn: [Advanced hunting schema reference](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-schema-tables)
* Microsoft Learn: [Create analytics rules in Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/detect-threats-custom)
* Microsoft Learn: [KQL quick reference](https://learn.microsoft.com/en-us/kusto/query/kql-quick-reference)
* MITRE ATT&CK: [Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)
* M365 Hardening Playbook: [No alerting on inbox forwarding rule creation](https://github.com/pslorenz/m365-hardening-playbook/blob/main/logging-and-monitoring/no-forwarding-rule-alerts.md)
* M365 Hardening Playbook: [No alerting on service principal credential additions](https://github.com/pslorenz/m365-hardening-playbook/blob/main/applications-and-consent/no-sp-credential-add-alert.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Security monitoring recommendations
* NIST CSF 2.0: DE.CM-01, DE.AE-02, DE.AE-03, RS.AN-01
