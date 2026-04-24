# 14 - Unified Audit Log Verification and Retention

**Category:** Audit and Alerting
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [01 - Tenant Initial Configuration and Break Glass Accounts](../identity-and-access/01-tenant-initial-and-break-glass.md) completed
**Time to deploy:** 45 minutes active work, plus ongoing retention policy review
**Deployment risk:** Low. Audit log configuration is additive; no existing functionality is affected.

## Purpose

This runbook verifies that Unified Audit Log (UAL) is enabled and configures retention appropriate to the tenant's licensing tier. UAL is the single most important foundation for every detection, alerting, investigation, and forensic workflow in Microsoft 365. Without UAL enabled and retained, a tenant cannot answer the question "what happened" after a security incident: who signed in from where, what mailbox rules were created, which files were accessed, which administrative actions ran. Every alert rule deployed in Runbook 16 depends on UAL; every investigation pulls from UAL; every compliance and forensic retention requirement is served by UAL.

The tenant before this runbook: UAL may be enabled or disabled depending on tenant age and administrator history. Newer tenants (2021 and later) have UAL enabled by default; older tenants require manual enablement. Retention defaults to 180 days for most events, 365 days for sign-in events, and can extend to 10 years with appropriate licensing and retention policies. Most SMB tenants run on defaults without conscious retention planning.

The tenant after: UAL is verified enabled with explicit documentation of the verification date. Retention is set appropriate to the licensing tier: 180 days for plain Business Premium (Microsoft default), 365 days for tenants with E5 Compliance or equivalent, 10 years where required by regulatory context. Administrative actions specifically (role assignments, policy changes, privileged operations) are retained longer through targeted retention policies. The Audit Log Search feature is confirmed accessible through the Microsoft Purview portal and through PowerShell.

UAL is not the same as Entra ID sign-in logs (which have their own retention governed by Entra ID licensing) and is not the same as Defender XDR advanced hunting data (which has its own retention). This runbook covers UAL specifically; the Defender XDR ingestion runbook (Runbook 15) addresses the separate Defender telemetry pipeline.

## Prerequisites

* Global Administrator or Compliance Administrator role for initial verification and retention configuration
* Understanding of the tenant's regulatory context: organizations subject to specific compliance regimes (SOX, HIPAA, FINRA, GDPR) may have retention requirements beyond the defaults
* Documented position on the retention trade-off: longer retention produces forensic value but consumes licensing; shorter retention reduces licensing cost but limits investigation capability

## Target configuration

At completion:

* **Unified Audit Log** enabled tenant-wide
* **Default retention** verified at the tenant's licensing-appropriate level:
    * Plain Business Premium: 180 days for standard events, 180 days for Entra ID sign-in events
    * Defender Suite, E5 Security: 180 days standard (Defender Suite does not include the E5 Compliance audit extension)
    * E5: 365 days standard; 10 years available with Audit Premium add-on
* **Audit retention policy** for administrative and privileged operations configured where extended retention is available
* **Audit log search** confirmed functional through both Purview portal and PowerShell
* **Documentation** of retention posture in the operations runbook with annual review cadence

## Deployment procedure

### Step 1: Verify UAL is enabled

```powershell
./14-Verify-UALEnabled.ps1
```

The script checks the tenant's audit log state and reports whether UAL is active. Expected output:

```
Unified Audit Log:
  UnifiedAuditLogIngestionEnabled: True
  Audit log search enabled:        True
  Last verification:               [timestamp]
```

If UAL is disabled, the script enables it:

```powershell
./14-Enable-UAL.ps1
```

Enabling UAL takes effect immediately for new events; it does not retroactively populate historical data. Tenants discovering UAL was disabled for an extended period have a gap in their audit coverage that cannot be recovered.

### Step 2: Verify current retention settings

```powershell
./14-Report-AuditRetention.ps1
```

The script queries the current retention policy set and reports:

* Default retention for each audit record type (ExchangeItem, SharePointFileOperation, AzureActiveDirectory, etc.)
* Custom retention policies currently applied
* Licensing-determined retention ceiling (what the tenant is entitled to vs. what is configured)

Review the output. The report identifies any gap between entitlement and configuration. For a typical Business Premium tenant the entitlement is 180 days and the configuration is 180 days; for E5 tenants the entitlement is 365 days but default configuration may still be 180 days until a policy explicitly applies the longer retention.

### Step 3: Configure targeted retention policies for administrative events

Administrative events (role assignments, PIM activations, policy modifications, sensitive operations) warrant longer retention than routine user activity. Create a targeted retention policy:

```powershell
./14-Deploy-AdminAuditRetention.ps1 `
    -PolicyName "Administrative Events Extended Retention" `
    -RetentionDays 365
```

The script creates an audit retention policy targeting specific administrative operations:

* **Entra ID role assignments and PIM activations**
* **Conditional Access policy modifications**
* **Applications and consent grants**
* **Break glass account sign-ins**
* **Mailbox audit entries for administrator actions**

For tenants with E5 or Audit Premium, extend further:

```powershell
./14-Deploy-AdminAuditRetention.ps1 `
    -PolicyName "Administrative Events - 10 Year Retention" `
    -RetentionDays 3650 `
    -RequireAuditPremium
```

Audit Premium is a separate licensing add-on to E5; tenants without it fall back to 365 days as the maximum.

### Step 4: Configure mailbox audit for all mailboxes

Mailbox audit logs are distinct from the UAL ingestion pipeline; they capture mailbox-specific operations (Send, Move, Delete, HardDelete, UpdateFolderPermissions, MailboxLogin) at the mailbox level. For any tenant concerned about business email compromise, mailbox audit should be enabled on every mailbox with default audit settings.

```powershell
./14-Enable-MailboxAuditing.ps1 -Scope AllMailboxes
```

The script enables mailbox auditing on every user mailbox and shared mailbox in the tenant, with default audit actions for Owner, Delegate, and Admin identities. Mailbox audit is enabled by default at the organization level in most tenants, but per-mailbox settings sometimes drift; the script enforces the tenant-wide state.

Specific operations captured include:

* **Owner auditing:** MailItemsAccessed (granular access logging), SendAs, SendOnBehalf, UpdateInboxRules, HardDelete
* **Delegate auditing:** same categories plus Create, FolderBind, SendAs
* **Admin auditing:** MailItemsAccessed, MessageBind, SendAs, SendOnBehalf, UpdateInboxRules, HardDelete, Update

The MailItemsAccessed operation specifically is the single most valuable mailbox audit event for BEC investigations; it logs when mail is read by the mailbox owner or a delegate, which is the data needed to determine whether an attacker with session access actually read specific messages. This operation requires E5 or the Defender for Office Plan 2 licensing (included with Defender Suite) for full capture; Plan 1 tenants get reduced mailbox audit coverage.

### Step 5: Test audit log search end-to-end

```powershell
./14-Test-AuditSearch.ps1
```

The script performs a test audit log search using known-reliable event types (sign-in activity in the last 24 hours) and confirms results return. Expected output:

```
Audit search test:
  Query:       UserLoggedIn events, last 24 hours
  Submitted:   [timestamp]
  Results:     [count] records returned
  Search time: [duration]
  Status:      PASS
```

A failed or zero-result search when events are expected indicates UAL is not ingesting correctly. Escalate to Microsoft Support; this is rare but occurs in specific tenant-state edge cases.

### Step 6: Document retention posture and review cadence

Update the operations runbook:

* UAL verification date and result
* Current default retention: [days]
* Administrative events retention policy: [days]
* Mailbox auditing scope and enabled operations
* Licensing tier governing retention ceiling
* Annual review cadence to confirm retention remains aligned with business and regulatory requirements
* Escalation path for retention extension (if business or regulatory context changes)

## Automation artifacts

* `automation/powershell/14-Verify-UALEnabled.ps1` - Confirms UAL state
* `automation/powershell/14-Enable-UAL.ps1` - Enables UAL if disabled
* `automation/powershell/14-Report-AuditRetention.ps1` - Reports current retention configuration
* `automation/powershell/14-Deploy-AdminAuditRetention.ps1` - Creates extended-retention policy for administrative events
* `automation/powershell/14-Enable-MailboxAuditing.ps1` - Enables mailbox audit on all mailboxes with baseline operations
* `automation/powershell/14-Test-AuditSearch.ps1` - End-to-end audit search validation
* `automation/powershell/14-Verify-Deployment.ps1` - Confirms the runbook's target state

## Verification

### Configuration verification

```powershell
./14-Verify-Deployment.ps1
```

Expected output:

```
Unified Audit Log:
  Enabled: Yes
  Audit search accessible: Yes

Retention:
  Default retention: 180 days (or higher per licensing)
  Administrative events policy: present, retention [N] days

Mailbox auditing:
  Enabled organization-wide: Yes
  All user mailboxes enrolled: Yes
  Baseline operations configured: Yes
  MailItemsAccessed available: [Yes if Plan 2; No if Plan 1]

Audit search test:
  Functional: Yes
  Last 24h returns results: Yes
```

### Functional verification

1. **UAL captures recent events.** Perform a tracked action (for example, sign in as a test admin account, create a test user) and search for the event in Microsoft Purview audit log search within 15 to 30 minutes. Expected: event appears in results.
2. **Mailbox audit captures delegate access.** Grant a test user delegate access to a test mailbox, have the delegate perform a MailItemsAccessed-triggering action, search UAL for the event. Expected: event appears with the delegate's UPN.
3. **Administrative event retention applied.** Confirm the retention policy targets the intended record types by inspecting the policy through the portal or PowerShell.

## Additional controls (add-on variants)

### Additional controls with Defender Suite, E5 Security, or EMS E5

Plan 2 Defender for Office licensing (included in Defender Suite and E5 Security) enables MailItemsAccessed auditing at full granularity for every mailbox. Plain Business Premium (Plan 1) gets MailItemsAccessed only at coarse granularity with throttling after high-volume events. For tenants concerned about BEC investigations, Plan 2 is the difference between being able to prove which specific messages an attacker read vs. knowing only that access occurred.

### Additional controls with E5 (Audit Premium)

E5 (and E5 Compliance standalone) includes Audit Premium, which extends default retention to 365 days and makes 10-year retention available through audit retention policies. Plain Business Premium tenants cannot extend beyond 180 days regardless of retention policy configuration; the licensing tier is the hard ceiling.

The retention policy script (`14-Deploy-AdminAuditRetention.ps1`) supports the `-RequireAuditPremium` switch that verifies the licensing before applying extended retention. Without the switch, the script applies the highest retention allowed by current licensing and notes the limitation.

### Microsoft 365 Backup (separate add-on)

Microsoft 365 Backup is a separate SKU from UAL retention. Backup protects against data loss scenarios (accidental deletion, ransomware encryption of OneDrive files, mailbox corruption) and has its own retention model. UAL retention governs audit record retention; Backup governs data retention. Both are relevant to incident response but address different scenarios. This runbook does not configure Backup; tenants with Backup licensing should deploy it through its own configuration path.

## What to watch after deployment

* **Audit search performance.** High-volume tenants experience search times that grow with date range and event type count. Searches spanning 30 days returning over 50,000 events can take several minutes. For routine queries, use Defender XDR advanced hunting (faster, richer query language) rather than Purview audit search; reserve audit search for specific forensic queries.
* **Retention consumption vs. licensing entitlement.** Extended retention for administrative events consumes a portion of the tenant's audit storage allocation. For E5 tenants with Audit Premium the allocation is generous; for Business Premium tenants with default entitlement the allocation is limited. Monitor retention storage through Microsoft 365 admin center service reports.
* **Events that appear in one audit surface but not another.** UAL ingestion is the primary pipeline but Defender XDR has its own ingestion path; the Entra ID sign-in log has its own storage. The same event may appear in UAL with one identity signature and in Defender advanced hunting with a different signature. For cross-surface queries, use Defender advanced hunting as the richer query environment.
* **Audit log gaps during Microsoft service incidents.** UAL ingestion is subject to service-level availability. Microsoft publishes ingestion delays during incidents; check the service health dashboard when an investigation returns fewer events than expected. Gaps are usually short (hours, not days) and Microsoft typically back-fills once service is restored.
* **Regulatory retention requirements.** Organizations subject to SEC, FINRA, HIPAA, or similar regimes have specific retention requirements that may exceed the baseline defaults. The E5 retention ceiling (365 days default, 10 years with Audit Premium) covers most regimes. Organizations with requirements beyond 10 years need a specialized archiving strategy outside Microsoft 365.

## Rollback

Rollback of UAL itself is not meaningful; disabling UAL removes the foundational telemetry that every other alerting and investigation capability depends on. Do not disable UAL as a rollback for any other deployment issue.

Rollback of retention policies:

```powershell
./14-Remove-AdminAuditRetention.ps1 -PolicyName "Administrative Events Extended Retention"
```

Removes the extended-retention policy, returning administrative events to the tenant's default retention. Rarely appropriate; removing retention creates forensic gaps that cannot be recovered if an incident occurs after the rollback.

For mailbox auditing, do not roll back. Organization-wide mailbox auditing is a foundational control; the specific operations audited can be tuned if volume is a concern, but disabling mailbox auditing leaves a gap that BEC investigations cannot work around.

## References

* Microsoft Learn: [Turn auditing on or off](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable)
* Microsoft Learn: [Search the audit log](https://learn.microsoft.com/en-us/purview/audit-log-search)
* Microsoft Learn: [Manage audit log retention policies](https://learn.microsoft.com/en-us/purview/audit-log-retention-policies)
* Microsoft Learn: [Microsoft Purview Audit (Premium)](https://learn.microsoft.com/en-us/purview/audit-premium)
* Microsoft Learn: [Manage mailbox auditing](https://learn.microsoft.com/en-us/purview/audit-mailboxes)
* Microsoft Learn: [MailItemsAccessed mailbox auditing action](https://learn.microsoft.com/en-us/purview/audit-log-investigate-accounts)
* M365 Hardening Playbook: [Unified Audit Log disabled or retention too short](https://github.com/pslorenz/m365-hardening-playbook/blob/main/logging-and-monitoring/ual-disabled-or-short-retention.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Audit log recommendations
* NIST CSF 2.0: DE.CM-01, DE.CM-03, DE.CM-09, RS.AN-01
