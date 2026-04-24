# 28 - Endpoint Detection and Response Tuning

**Category:** Endpoint and Attack Surface
**Applies to:**
* **Plain Business Premium:** Defender for Business (Plan 1) is deployed by default; advanced EDR tuning covered here requires Plan 2.
* **+ Defender Suite:** Full EDR capabilities via Defender for Endpoint Plan 2 (advanced hunting, custom detections, automated investigation and response, threat analytics).
* **+ Purview Suite:** Same as Plain BP; Purview Suite adds no EDR capability.
* **+ Defender & Purview Suites:** Full EDR via Plan 2.
* **+ E5 Security (legacy):** Full EDR via Plan 2 under the legacy SKU.
* **+ EMS E5:** Same as Plain BP; no EDR enhancement.
* **M365 E5:** Full EDR via Plan 2.

**Prerequisites:**
* [08 - Windows Device Compliance Policy](../device-compliance/08-windows-compliance-policy.md) completed
* [15 - Defender XDR and Sentinel Baseline Ingestion](../audit-and-alerting/15-defender-xdr-sentinel-ingestion.md) completed
* [27 - Attack Surface Reduction Rules](./27-asr-rules.md) completed
* Windows devices onboarded to Defender for Endpoint Plan 2

**Time to deploy:** 3 to 4 hours for baseline tuning, plus 30 to 60 days of alert review and iteration
**Deployment risk:** Low. EDR tuning adjusts detection sensitivity, automated response scope, and device grouping; individual changes are easily reversed and do not cause user-visible impact like ASR rules can.

## Purpose

This runbook tunes the Defender for Endpoint Plan 2 capabilities beyond the default-enabled configuration. Where ASR rules block specific attack behaviors at the endpoint, EDR produces the detection and investigation layer: alerts when attack patterns are observed, device and user timelines showing what happened, automated investigation that collects evidence and remediates when appropriate, and the hunting interface that lets security responders query the endpoint telemetry directly. Most tenants deploy Plan 2 licensing and leave it in default configuration; Defender ships with reasonable defaults, but production use benefits from tuning: device grouping that matches organizational structure, indicators of compromise for tenant-specific threats, custom detections for tenant-specific patterns, and automated investigation scoped to match risk tolerance.

The tenant before this runbook: Defender for Endpoint Plan 2 is deployed and onboarded. Default alert policies fire; automated investigation runs in semi-automatic mode (evidence collection is automatic, remediation requires approval); device groups do not exist or contain all devices in a single default group. The security admin reviews alerts through the Defender portal but has no tenant-specific customization. Alerts are what Microsoft's telemetry and machine learning produce; alerts for tenant-specific threats (known-bad domains in this tenant's phishing attempts, indicators from prior incidents) are not detected because the tenant has not added them.

The tenant after: device groups organize endpoints by function (servers, administration workstations, standard endpoints, kiosks). Each group has appropriate automated investigation scope (administration workstations allow only evidence collection; standard endpoints allow remediation; servers are isolated from automated remediation pending manual review). Indicators of compromise from tenant-specific intelligence feed custom detection. Ten custom detection rules cover tenant-specific patterns beyond what Microsoft's built-in detections catch. Alert triage follows a documented process with clear escalation paths. The EDR capability produces actionable security signal rather than queue noise.

EDR tuning is iterative. Initial deployment establishes the configuration; the first 60 days produce telemetry and alerts that inform further tuning. The runbook covers the initial setup and the ongoing tuning cadence (monthly alert review, quarterly detection review, annual device grouping review).

## Prerequisites

* Defender for Endpoint Plan 2 licensing (Defender Suite or equivalent)
* Devices onboarded to Defender for Endpoint
* Security admin or Security Operations Center role
* Inventory of device classes in the organization (servers, administration workstations, standard endpoints, specialized devices)
* Known indicators of compromise for the tenant (domains, IPs, file hashes from prior incidents, phishing campaigns, etc.)
* Incident response contact list (security admin, legal, HR, executive sponsors)

## Target configuration

### Device groups

Three to six device groups organize endpoints by function and automated response tolerance:

| Group | Scope | Automation Level |
|---|---|---|
| Tier Zero Workstations | Administration workstations, Global Admin devices | Semi-automatic (remediation requires approval) |
| Standard Endpoints | General employee Windows and macOS devices | Full automation (remediation auto-applied) |
| Servers | Windows Server and Linux server onboarded devices | No automation (alert only; manual remediation) |
| Kiosk and Specialized | POS, industrial control, specialized hardware | Alert only; custom exclusions likely |
| Shared Workstations | Multi-user terminals | Full automation |

Larger tenants add finer-grained groups (finance workstations, HR workstations, engineering workstations) for per-group policy.

### Automated investigation and response (AIR)

* **Enabled:** Yes, for all groups
* **Semi-automatic on Tier Zero:** Evidence collection automatic; remediation requires approval
* **Automatic on Standard Endpoints and Shared:** Evidence collection and remediation automatic for verdicts of Malicious or Suspicious above confidence threshold
* **Alert-only on Servers and Kiosk:** AIR generates investigation but takes no action

### Indicators of compromise

Tenant-specific indicators are added to Defender:

* **Domain indicators:** known-bad domains from phishing campaigns or prior incidents
* **IP indicators:** known-bad IPs, attacker infrastructure
* **File hash indicators:** SHA256 of known-bad files from prior incidents
* **Certificate indicators:** certificates used by known-bad actors

Each indicator has a severity (Informational, Low, Medium, High) and an action (Allow, Warn, Block, Audit). Most indicators deploy as Block at Medium or High severity.

### Custom detection rules

Ten baseline custom detection rules beyond Microsoft's built-in detections:

1. **Mass credential access attempt.** User with many failed sign-ins followed by successful sign-in from new location.
2. **Privilege escalation via scheduled task creation.** Scheduled task created that runs with SYSTEM privilege from a non-standard path.
3. **PowerShell download cradle.** PowerShell executing DownloadString, Invoke-WebRequest, or Invoke-Expression on a URL.
4. **Living-off-the-land binary abuse.** Specific LOLBins invoked in sequences matching attack patterns (certutil + rundll32, mshta + bitsadmin).
5. **Uncommon parent-child process pairs.** Processes spawning from unexpected parents (cmd.exe from svchost.exe, rundll32 from winword.exe).
6. **USB drive execution.** Process execution from USB drive paths.
7. **Clear event log.** Security event log clearing attempts.
8. **Registry persistence.** Additions to autoruns keys, service configuration, or startup folder.
9. **Remote access tool installation.** Installation of known remote access tools (TeamViewer, AnyDesk, ConnectWise) outside approved deployment.
10. **Credential harvesting tool execution.** Execution of known credential harvesting tools (mimikatz variants, LaZagne, ProcDump with lsass argument).

Rules are deployed in alert mode initially; transition to alert-plus-AIR after 30 days of tuning.

### Alert triage process

* **High-severity alerts:** Security admin reviews within 2 hours of generation (business hours); 4 hours after hours
* **Medium-severity alerts:** Review within 24 hours
* **Low and Informational:** Review in daily queue

Triage outcomes:

* Close as false positive (feedback to Microsoft improves future detection)
* Close as benign (legitimate activity that resembles the detected pattern)
* Suppress (repeated alert on known-benign activity; create suppression rule)
* Investigate (escalate to investigation case)
* Execute response (contain device, block IOC, reset credentials)

## Deployment procedure

### Step 1: Verify Plan 2 licensing and device state

```powershell
./28-Verify-Plan2Licensing.ps1
```

The script verifies Defender for Endpoint Plan 2 licensing, onboarded device count, and device operating system distribution.

### Step 2: Configure device groups

```powershell
./28-Deploy-DeviceGroups.ps1 `
    -TierZeroDeviceTag "TierZeroWorkstation" `
    -ServerDeviceTag "Server" `
    -KioskDeviceTag "Kiosk"
```

The script creates device groups in Defender based on device tags applied through Intune or manually. Tagging:

* Tier Zero: apply through Intune policy targeting the tier-zero device group
* Server: automatic based on OS type
* Kiosk: apply through Intune policy targeting specialized device groups
* Default: all other onboarded devices

### Step 3: Configure automated investigation and response

```powershell
./28-Configure-AIR.ps1 `
    -TierZeroAutomation "Semi" `
    -StandardAutomation "Full" `
    -ServerAutomation "NoAutomation" `
    -KioskAutomation "NoAutomation"
```

### Step 4: Deploy indicators of compromise

```powershell
./28-Deploy-IOCs.ps1 -IOCFilePath "./iocs.csv"
```

IOC file format:

```csv
IndicatorType,Indicator,Severity,Action,Description,ExpireOn
Domain,bad-domain.example.com,High,Block,Known phishing C2,2027-01-01
IP,192.0.2.100,High,Block,Incident 2025-03-15 attacker IP,2027-01-01
FileSHA256,abc123...,High,Block,Incident 2025-03-15 malware,2027-01-01
```

Tenants without existing IOCs start with an empty file; IOCs accumulate from incident response, threat intelligence, and MSP-shared intelligence.

### Step 5: Deploy custom detection rules

```powershell
./28-Deploy-CustomDetections.ps1
```

The script creates the ten baseline custom detection rules through Defender's custom detection interface. Each rule includes the KQL query, alert severity, MITRE ATT&CK technique reference, and automated response action.

### Step 6: Configure alert notifications

```powershell
./28-Configure-AlertNotifications.ps1 `
    -HighSeverityRecipients @("security-admin@contoso.com","soc@contoso.com") `
    -MediumSeverityRecipients @("security-admin@contoso.com")
```

The script creates notification rules that email specified recipients on alert generation. High-severity alerts page the security admin; medium-severity alerts reach the security admin queue.

### Step 7: Document the triage process

Update the operations runbook:

* Alert severity-to-SLA mapping
* Triage outcomes and their criteria
* Escalation paths
* Suppression rule approval process
* Indicator of compromise submission process
* Custom detection rule change management

### Step 8: Verify deployment

```powershell
./28-Verify-Deployment.ps1
```

### Step 9: Establish tuning cadence

* **Weekly (first 60 days):** Review alerts, identify false positive patterns, add suppressions where appropriate
* **Monthly (ongoing):** Review custom detection rule performance, update IOCs, review suppressions
* **Quarterly:** Review device group assignments, AIR automation levels, custom detection rule inventory
* **Annually:** Comprehensive EDR posture review (runbook 19)

## Automation artifacts

* `automation/powershell/28-Verify-Plan2Licensing.ps1` - License and device state verification
* `automation/powershell/28-Deploy-DeviceGroups.ps1` - Device group creation
* `automation/powershell/28-Configure-AIR.ps1` - AIR configuration per group
* `automation/powershell/28-Deploy-IOCs.ps1` - IOC management
* `automation/powershell/28-Deploy-CustomDetections.ps1` - Custom detection rule deployment
* `automation/powershell/28-Configure-AlertNotifications.ps1` - Notification routing
* `automation/powershell/28-Monitor-AlertActivity.ps1` - Alert queue and triage reporting
* `automation/powershell/28-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/28-Rollback-EDRTuning.ps1` - Reverts tuning to defaults

## Verification

### Configuration verification

```powershell
./28-Verify-Deployment.ps1
```

### Functional verification

1. **Device group membership.** Verify tagged devices appear in the correct group.
2. **AIR automation level.** Trigger a test alert on a standard endpoint (via Microsoft's EICAR-style test tool or Defender demo URL) and verify AIR executes at the configured level.
3. **IOC blocking.** Add a test domain IOC (using a test subdomain of contoso.com); attempt to access from a managed device; verify block.
4. **Custom detection triggering.** Execute the pattern that one of the custom detections matches (in a controlled test environment); verify alert generation.
5. **Notification delivery.** Trigger a high-severity alert and verify notification email arrives at the configured recipient within 5 minutes.

## Additional controls (add-on variants)

### Additional controls with Microsoft Sentinel

Defender Suite includes some Sentinel benefit for Defender-sourced data. Tenants with full Sentinel deployment extend EDR capability:

* **Long-term telemetry retention.** Defender retains data for 180 days; Sentinel retention is configurable up to 2 years with archive beyond.
* **Cross-product correlation.** Sentinel correlates Defender alerts with Azure activity logs, firewall logs, third-party log sources.
* **Custom detections with multi-source KQL.** Sentinel analytics rules can query multiple data sources; Defender custom detections are Defender data only.

For tenants with Sentinel, some detections may be better placed in Sentinel; this runbook keeps the ten baseline detections in Defender for simpler management.

### Additional controls with Defender XDR

Defender Suite tenants have access to Defender XDR (unified incident view across Defender for Endpoint, Defender for Office 365, Defender for Identity, Defender for Cloud Apps). EDR alerts appear as parts of XDR incidents when other products correlate.

Advanced Hunting in XDR (versus Defender for Endpoint portal alone) provides:

* Multi-product queries spanning Endpoint, Office 365, Identity, Cloud Apps telemetry
* Faster query performance on aggregated data
* Scheduled custom detections that span products

Consider moving custom detections to XDR-level when they would benefit from multi-product correlation.

### Live Response

Plan 2 includes Live Response, a remote shell to onboarded devices for investigation and response. Used by security admins during active incident response:

* Query device state (running processes, network connections, installed software, event logs)
* Collect files for analysis
* Run PowerShell or command-line scripts on the device
* Isolate the device from the network

Live Response requires explicit role assignment; grant only to security operations personnel.

## What to watch after deployment

* **Alert queue volume.** The first 30 days produce high alert volume as Defender establishes baselines and tenant-specific patterns emerge. Review volume trends; tune aggressive custom detections if the queue becomes unmanageable.
* **False positive patterns.** Specific line-of-business applications consistently trigger custom detections. Suppressions are appropriate; document the suppressed pattern and the application that caused it.
* **Automated remediation impact.** Full automation on standard endpoints can produce user-visible impact (process termination, file quarantine, account session reset). Monitor user-reported issues for cases where AIR acted incorrectly; tune AIR confidence thresholds if needed.
* **IOC lifecycle.** IOCs added during incident response often have limited useful life (attackers rotate infrastructure). Review expiration dates quarterly; remove stale IOCs that no longer match active threats.
* **Custom detection rule drift.** Rules deployed months ago may no longer match the current threat landscape. Review rule performance quarterly; retire rules with zero matches and evolving detection patterns.
* **Tier zero workstation events.** Events on administration workstations warrant immediate review. Administrative accounts have access to significant tenant resources; compromise of an administration workstation is a severity multiplier for any other alert.
* **Defender update timing.** Defender signatures and detection models update automatically on devices with current onboarding and internet connectivity. Devices offline for extended periods (laptops belonging to traveling users, seasonally-used devices) may have stale detection. Verify update timestamps during quarterly review.
* **Licensing mixed state.** The Microsoft guidance on mixing Defender for Business (Plan 1) and Defender for Endpoint Plan 2 in a single tenant: the tenant defaults to Plan 1 capability for all users unless the tenant is explicitly converted. A partial Plan 2 rollout does not produce Plan 2 behavior; contact Microsoft Support to switch tenant-level behavior if deploying Plan 2 add-on to a Plan 1 tenant.

## Rollback

```powershell
./28-Rollback-EDRTuning.ps1 -Scope "<scope>" -Reason "Documented reason"
```

Rollback scopes:

* **CustomDetections:** Removes custom detection rules; Microsoft built-in detections remain.
* **IOCs:** Removes tenant-specific IOCs.
* **DeviceGroups:** Reverts to default single group; AIR reverts to tenant default.
* **Full:** All of the above.

Rollback is rare; tuning is the normal mode. Alert suppression, IOC expiration, and rule retirement are the operational cadence.

## References

* Microsoft Learn: [Microsoft Defender for Endpoint Plan 2](https://learn.microsoft.com/en-us/defender-endpoint/mde-plans)
* Microsoft Learn: [Automated investigation and response](https://learn.microsoft.com/en-us/defender-xdr/m365d-autoir)
* Microsoft Learn: [Device groups in Microsoft Defender for Endpoint](https://learn.microsoft.com/en-us/defender-endpoint/machine-groups)
* Microsoft Learn: [Manage indicators in Defender for Endpoint](https://learn.microsoft.com/en-us/defender-endpoint/manage-indicators)
* Microsoft Learn: [Custom detections overview](https://learn.microsoft.com/en-us/defender-xdr/custom-detections-overview)
* Microsoft Learn: [Live response overview](https://learn.microsoft.com/en-us/defender-endpoint/live-response)
* M365 Hardening Playbook: [EDR not tuned beyond defaults](https://github.com/pslorenz/m365-hardening-playbook/blob/main/endpoint/edr-not-tuned.md) (pending)
* MITRE ATT&CK framework
* NIST CSF 2.0: DE.AE-02, DE.CM-01, DE.CM-07, RS.AN-01, RS.MI-02
