# 15 - Defender XDR and Sentinel Baseline Ingestion

**Category:** Audit and Alerting
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](./14-ual-verification-retention.md) completed
**Time to deploy:** 60 to 120 minutes active work depending on ingestion platform chosen
**Deployment risk:** Low. Ingestion configuration is additive.

## Purpose

This runbook selects and configures the alerting and hunting platform that consumes signals from every runbook deployed so far. A tenant with runbooks 01 through 14 has excellent posture: Conditional Access, PIM, device compliance, anti-phish, Safe Links, email authentication, audit logging. Without an alerting platform consuming those signals, the tenant has no operational visibility into what the controls are catching. An adversary triggering PIM activation outside business hours, creating mailbox forwarding rules, adding credentials to a privileged service principal, or signing in from a previously-unseen location produces signals in UAL and Defender telemetry but no one is looking at them until a weekly or monthly report.

The tenant before this runbook: signals accumulate in UAL and in Defender's built-in alert views. Defender XDR surfaces some alerts automatically through the Microsoft 365 Defender portal for tenants with Defender for Office 365 Plan 1 or Plan 2. Entra ID Identity Protection (where licensed) produces risk alerts. None of this is currently routed to a destination that administrators monitor actively. High-signal events compete with low-priority noise in the Defender portal's default views.

The tenant after: a clear ingestion pipeline is configured with one of three paths:

* **Path A (Defender XDR only):** appropriate for tenants with Defender Suite, E5 Security, or E5 that have Defender for Office 365 Plan 2 and Defender for Endpoint Plan 2. Defender XDR is the single pane; alert tuning, custom detections, and investigation workflows all happen in the Defender portal.
* **Path B (Sentinel as consolidation point):** appropriate for tenants with multi-cloud or multi-tenant visibility requirements, or MSPs managing many tenants from a central console. Sentinel ingests from M365 Defender plus additional sources (Entra ID logs, third-party security tooling, custom sources).
* **Path C (Built-in alert policies only):** appropriate for plain Business Premium tenants without Plan 2 Defender licensing. Uses Microsoft 365 alert policies (free with any Business Premium license) as the primary alerting surface, with recipients configured for the high-priority alerts.

The runbook walks through each path with decision criteria and configuration procedures. Most SMB tenants on Defender Suite or E5 Security choose Path A because it is operationally simple and included in licensing; most plain Business Premium tenants must use Path C; Sentinel (Path B) is primarily selected by MSPs and mid-market organizations with existing SIEM workflows.

## Prerequisites

* UAL verified enabled and retention configured (Runbook 14)
* Licensing tier identified: Plain Business Premium, Defender Suite, E5 Security, or EMS E5
* Global Administrator or Security Administrator role
* Decision on ingestion path: this runbook presents A, B, and C as alternatives; most tenants execute one path

## Target configuration

### Path A: Defender XDR only (Defender Suite, E5 Security, E5)

* Defender for Office 365 integrated alerts enabled (automatic)
* Defender for Endpoint alerts integrated (automatic for Plan 2 tenants)
* Entra ID Identity Protection integrated (for P2 tenants)
* Custom detection rules from Runbook 16 deployed
* Alert notification preferences configured for the monitored destination

### Path B: Sentinel

* Sentinel workspace created or identified
* Microsoft 365 Defender connector enabled
* Microsoft Entra ID connector enabled
* Office 365 connector enabled (covers SharePoint, Exchange, Teams audit)
* Additional connectors as needed (Defender for Endpoint, Defender for Identity if licensed)
* Analytics rules from Runbook 16 deployed
* Workbook for operational dashboards enabled

### Path C: Built-in alert policies only (Plain Business Premium)

* Microsoft 365 alert policies reviewed and enabled for high-priority categories
* Alert recipients configured: security administrator distribution list
* Custom alert policies deployed for tenant-specific patterns (where alert policy framework supports)
* Weekly manual review of alert activity (documented cadence in operations runbook)

## Deployment procedure

### Path A: Defender XDR only

#### Step A1: Verify Defender XDR availability

```powershell
./15-Verify-DefenderXDR.ps1
```

The script checks tenant licensing for Defender for Office 365 Plan 2 or Plan 1, Defender for Endpoint Plan 1 or Plan 2, Entra ID Identity Protection (P2), and reports which integrations are available.

Expected output:

```
Defender XDR integration status:
  Defender for Office 365: Plan 2
  Defender for Endpoint: Plan 2
  Entra ID Identity Protection: Available (P2)
  Defender for Identity: [Licensed/Not licensed]
  Defender for Cloud Apps: [Licensed/Not licensed]

Integration in Defender XDR portal: verify at https://security.microsoft.com
```

#### Step A2: Configure alert notification preferences

```powershell
./15-Configure-DefenderAlertNotifications.ps1 `
    -SecurityAdminEmail "security-alerts@contoso.com" `
    -SeverityThreshold "Medium"
```

The script configures email notification for alerts at or above the specified severity threshold. Medium threshold catches meaningful alerts without flooding the destination; High-only misses signals that warrant investigation but aren't critical; Low threshold produces noise.

#### Step A3: Enable Microsoft 365 alert policies integration

Microsoft 365 alert policies (the same framework used in Path C) integrate with Defender XDR for tenants with Plan 2. Review the default policies and confirm they are enabled:

```powershell
./15-Review-DefenderAlertPolicies.ps1
```

The script enumerates current alert policies and flags any that are disabled or not producing alerts to the configured destination. Common default policies that should remain enabled:

* Elevation of Exchange admin privilege
* Suspicious email sending patterns detected
* Potential nation-state activity
* Unusual volume of file deletion
* Unusual volume of external user file activity
* Potentially malicious URL click
* User requested to release a quarantined message

#### Step A4: Plan for custom detection rules

Custom detection rules (Runbook 16) are deployed in Defender XDR directly. Confirm the tenant has custom detection quota available: Defender for Office 365 Plan 2 permits up to 50 custom detection rules; E5 up to 100. Document the allocation plan before deploying.

### Path B: Sentinel

#### Step B1: Create or identify the Sentinel workspace

Sentinel deployment requires an Azure subscription and a Log Analytics workspace. For MSP scenarios, the workspace may be in the MSP's subscription with Azure Lighthouse delegation to the customer tenant; for customer-owned deployments, the workspace sits in the customer's Azure subscription.

```powershell
./15-Verify-SentinelWorkspace.ps1 -WorkspaceName "sentinel-contoso-prod"
```

The script verifies the workspace exists, is Sentinel-enabled, and has appropriate permissions for ingestion from Microsoft 365.

Sentinel workspace creation is outside the scope of this script because it is an Azure resource deployment with subscription-level implications (cost, location, retention). Use Azure portal or Azure CLI for workspace creation; this runbook's scripts operate against an existing workspace.

#### Step B2: Enable the Microsoft 365 Defender connector

```powershell
./15-Enable-SentinelM365DefenderConnector.ps1 `
    -WorkspaceName "sentinel-contoso-prod" `
    -IncludeAlerts `
    -IncludeIncidents `
    -IncludeRawLogs
```

The connector ingests alerts, incidents, and raw event logs from Defender XDR into the Sentinel workspace. The raw log ingestion is the expensive option (produces higher storage cost) but enables Sentinel-side advanced hunting without relying on Defender XDR's query quota.

Recommended settings for most SMB tenants:
* Include alerts: Yes
* Include incidents: Yes
* Include raw logs: No initially; enable selectively for specific log types if needed

#### Step B3: Enable the Microsoft Entra ID connector

```powershell
./15-Enable-SentinelEntraConnector.ps1 -WorkspaceName "sentinel-contoso-prod"
```

The connector ingests Entra ID sign-in logs, audit logs, and risk events. Requires Entra ID P1 or P2 licensing for full coverage.

#### Step B4: Enable the Office 365 connector

```powershell
./15-Enable-SentinelO365Connector.ps1 -WorkspaceName "sentinel-contoso-prod"
```

The connector ingests SharePoint, Exchange, and Teams audit events (the same UAL data, delivered to Sentinel for query). Some overlap with the Microsoft 365 Defender connector raw logs setting; enable one or the other based on ingestion cost.

#### Step B5: Plan for analytics rules and workbooks

Analytics rules (Sentinel-side detections) deploy in Runbook 16 against the workspace. Workbooks (dashboards) are deployed from the Sentinel workbook templates; Microsoft publishes several for M365 tenants that are appropriate for SMB deployment.

### Path C: Built-in alert policies only (Plain Business Premium)

#### Step C1: Review default alert policies

```powershell
./15-Review-AlertPolicies.ps1
```

The script enumerates Microsoft 365 alert policies and reports which are enabled, which are disabled, and their notification destinations. Review the output against the recommended baseline:

Default policies that should be enabled:

* Elevation of Exchange admin privilege
* Creation of forwarding/redirect rule
* Admin triggered user compromise investigation
* Email reported by user as malware or phish
* Malware campaign detected and blocked
* Phish delivered due to an ETR override
* Suspicious email sending patterns detected
* Tenant restricted from sending unprovisioned email
* User restricted from sending email

#### Step C2: Configure notification destinations

```powershell
./15-Configure-AlertPolicyNotifications.ps1 `
    -SecurityAdminEmail "security-alerts@contoso.com" `
    -EnableAllHighSeverity
```

The script adds the security admin email to every enabled high-severity alert policy notification list.

#### Step C3: Deploy custom alert policies for SMB-specific patterns

For patterns that the built-in alert policies do not cover, create custom policies through the Purview portal or the alert policy PowerShell:

```powershell
./15-Deploy-CustomAlertPolicies.ps1 -SecurityAdminEmail "security-alerts@contoso.com"
```

The script creates a set of SMB-relevant alert policies:

* Break glass account sign-in detection
* High-volume mailbox rule creation by a single user
* OAuth consent grant to a non-verified application
* Service principal credential addition
* Conditional Access policy modification

The full set of detections is defined in Runbook 16; Path C implements them using the alert policy framework since custom detection rules (the Defender XDR feature) are not available for plain Business Premium.

#### Step C4: Document the weekly review cadence

Path C does not have an always-on SIEM consuming alerts. The compensating control is a documented weekly review cadence: a named individual reviews the alert summary email or the Purview alert dashboard weekly, triages new alerts, and escalates as needed. Document this in the operations runbook.

## Automation artifacts

* `automation/powershell/15-Verify-DefenderXDR.ps1` - Reports Defender XDR integration status
* `automation/powershell/15-Configure-DefenderAlertNotifications.ps1` - Configures Defender XDR alert email notifications
* `automation/powershell/15-Review-DefenderAlertPolicies.ps1` - Reviews Defender alert policy state
* `automation/powershell/15-Verify-SentinelWorkspace.ps1` - Verifies Sentinel workspace readiness
* `automation/powershell/15-Enable-SentinelM365DefenderConnector.ps1` - Enables Defender connector
* `automation/powershell/15-Enable-SentinelEntraConnector.ps1` - Enables Entra ID connector
* `automation/powershell/15-Enable-SentinelO365Connector.ps1` - Enables Office 365 connector
* `automation/powershell/15-Review-AlertPolicies.ps1` - Reviews Microsoft 365 alert policies
* `automation/powershell/15-Configure-AlertPolicyNotifications.ps1` - Configures alert policy notification recipients
* `automation/powershell/15-Deploy-CustomAlertPolicies.ps1` - Deploys SMB-specific custom alert policies
* `automation/powershell/15-Verify-Deployment.ps1` - Confirms the selected path's target state

## Verification

### Configuration verification

```powershell
./15-Verify-Deployment.ps1 -Path "A"   # or B or C
```

For Path A, expected output covers Defender XDR integration status, notification preferences, and alert policy state.
For Path B, expected output covers connector state for Defender, Entra ID, and Office 365.
For Path C, expected output covers enabled alert policies and notification destinations.

### Functional verification

1. **Test alert fires and reaches destination.** Trigger a known alert pattern (for example, sign in as a break glass account if that alert is configured, or perform a test operation that triggers a known Defender alert). Expected: alert appears in the configured destination (Defender XDR portal, Sentinel, or email) within the expected SLA (seconds to minutes for real-time alerts, up to 15 minutes for batched ones).
2. **Search-based alerting confirms ingestion.** For Path A, search Defender XDR advanced hunting for events from the last hour. For Path B, run a KQL query in Sentinel against the same time range. Expected: results return.
3. **Notification destination receives messages.** Confirm the security admin email has received at least one notification since deployment. If zero notifications have arrived and the tenant has been active, the notification configuration is incorrect.

## Additional controls (add-on variants)

### Additional controls with Defender Suite

Defender Suite tenants get Defender XDR as the natural alerting platform (Path A). Sentinel (Path B) is available if the organization has Azure investment patterns but is rarely the primary choice for Defender Suite tenants; the Defender XDR experience is richer for Microsoft 365 threats specifically.

### Additional controls with E5

E5 tenants have access to Defender for Identity and Defender for Cloud Apps, adding identity-focused and SaaS-focused detection to the Defender XDR platform. These deploy separately from this runbook (Defender for Identity requires on-premises domain controller agents; Defender for Cloud Apps requires integration with SaaS applications).

### MSP multi-tenant considerations

MSPs managing many tenants often centralize alerting into a single Sentinel instance using Azure Lighthouse delegation. The MSP sees alerts from every customer tenant in one Sentinel workspace; customer-side administrators see alerts from their own tenant in Defender XDR. This hybrid model (per-tenant Defender XDR plus central MSP Sentinel) is common; the per-tenant Defender XDR is Path A deployment in each tenant, and the MSP's central Sentinel is a separate Path B deployment.

## What to watch after deployment

* **Alert volume and noise rate.** First two weeks typically produce higher-than-steady-state alert volume as baselines establish. Review weekly and tune: alerts that consistently produce low-value information should be suppressed or adjusted; alerts that consistently precede real incidents should be prioritized.
* **Alert destination inbox management.** The destination email or distribution list for alerts becomes a high-signal inbox. Treat it as a security-tier workspace: restrict access, avoid conflating with general IT support mail, review regularly.
* **Missed alerts from misconfigured severity thresholds.** Starting at Medium threshold catches more; starting at High threshold misses signals that warrant investigation. For the first month, keep Medium; tune upward only after confirming the threshold captures the right patterns.
* **Connector health for Path B.** Sentinel connectors occasionally fall behind or fail during Azure service incidents. Monitor connector state in the Sentinel portal; failures for extended periods produce gaps in alerting coverage.
* **Licensing changes.** Tenant adds Defender Suite partway through Path C deployment; the tenant can pivot to Path A without reverting Path C. Tenant drops from Defender Suite back to plain Business Premium; Path A alerts cease functioning and the tenant needs to pivot back to Path C.

## Rollback

Rollback of alert and ingestion configuration is operationally simple but produces visibility loss that is rarely the correct outcome. Specific rollback scripts:

```powershell
./15-Rollback-AlertConfiguration.ps1 -Path "A" -Reason "Documented reason"
```

More common pattern: adjust configuration rather than roll back. If alert volume is overwhelming, tune thresholds or suppress specific noisy alerts. If ingestion costs are problematic (Path B), reduce raw log ingestion while keeping alert/incident ingestion enabled.

## References

* Microsoft Learn: [Microsoft 365 Defender portal](https://learn.microsoft.com/en-us/defender-xdr/microsoft-365-defender-portal)
* Microsoft Learn: [Alert policies in Microsoft Purview](https://learn.microsoft.com/en-us/purview/alert-policies)
* Microsoft Learn: [Microsoft Sentinel overview](https://learn.microsoft.com/en-us/azure/sentinel/overview)
* Microsoft Learn: [Connect Microsoft 365 Defender data to Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/connect-microsoft-365-defender)
* Microsoft Learn: [Connect Microsoft Entra ID data to Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/connect-azure-active-directory)
* Microsoft Learn: [Connect Office 365 data to Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/connect-office-365)
* M365 Hardening Playbook: [No alerting on privileged role changes](https://github.com/pslorenz/m365-hardening-playbook/blob/main/logging-and-monitoring/no-alerting-on-privileged-changes.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Monitoring and alerting recommendations
* NIST CSF 2.0: DE.CM-01, DE.DP-04, RS.AN-01
