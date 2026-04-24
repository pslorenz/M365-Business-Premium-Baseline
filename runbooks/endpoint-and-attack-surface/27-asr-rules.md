# 27 - Attack Surface Reduction Rules

**Category:** Endpoint and Attack Surface
**Applies to:**
* **Plain Business Premium:** Basic ASR rules available through Defender for Business Plan 1 (6 rules). Advanced rules require Plan 2.
* **+ Defender Suite:** Full ASR rule set through Defender for Endpoint Plan 2 (16 rules).
* **+ Purview Suite:** Same as Plain BP (ASR is endpoint-focused; Purview adds no ASR capability).
* **+ Defender & Purview Suites:** Full ASR rule set.
* **+ E5 Security (legacy):** Full ASR rule set through legacy Defender Plan 2 licensing.
* **+ EMS E5:** Basic ASR only (EMS E5 does not include Defender for Endpoint Plan 2).
* **M365 E5:** Full ASR rule set.

**Prerequisites:**
* [07 - Intune Enrollment Strategy](../device-compliance/07-intune-enrollment-strategy.md) completed
* [08 - Windows Device Compliance Policy](../device-compliance/08-windows-compliance-policy.md) completed
* Windows 10/11 devices enrolled in Intune and onboarded to Defender for Endpoint (Business or P2)

**Time to deploy:** 2 to 3 hours active work for baseline deployment, plus 30 days in audit mode before enforcement
**Deployment risk:** Medium. Some ASR rules have well-documented compatibility issues with specific business applications. The runbook defaults to audit mode for the first 30 days and uses block mode only for rules with established low false positive rates.

## Purpose

This runbook deploys the Defender for Endpoint Attack Surface Reduction rule set, which prevents common attacker techniques at the operating system level. Where Conditional Access prevents unauthorized authentication and Defender for Office prevents malicious email delivery, ASR rules prevent specific attacker behaviors on a device that is already authenticated, already delivered malicious payload, or already compromised: the script block executing from Word, the Outlook launching child processes, the macro invoking Win32 APIs, the USB drive running unsigned code. ASR rules are reactive to Microsoft's threat intelligence; each rule exists because a specific attack pattern was observed in the wild and the behavior could be blocked without breaking the underlying legitimate functionality. Windows threat actors have been adapting to ASR for years; deploying ASR closes attack paths that were routinely exploited before 2018 and remain exploited today in tenants that have not deployed it.

The tenant before this runbook: Windows endpoints have default behavior for the scenarios ASR addresses. Word macros can spawn child processes. Outlook can create executable content. Scripts can execute from email attachments. USB drives run whatever they contain. Adobe Reader can invoke child processes to launch secondary malware. Standard attack chains (user opens document, document runs macro, macro downloads payload, payload establishes persistence) have no friction at any step. The endpoint depends entirely on Defender detecting known malware at the specific step where it appears; novel or obfuscated malware has a clear path from delivery to persistence.

The tenant after: fifteen ASR rules produce defense-in-depth against common attack patterns. The baseline rules are deployed in audit mode for the first 30 days so that any compatibility issues surface before enforcement. Rules with established low false positive rates (credential theft from LSASS, Office applications creating executable content, persistence through WMI subscription) transition to block mode after audit. Rules with known false positive potential (block Win32 API calls from Office macros, block executable content from email client) also transition to block mode because the false positive cost is typically lower than the attack surface cost, but with user communication about the transition. Rules with high false positive potential in specific business contexts (block executables that don't meet age/prevalence criteria; block PSExec and WMI commands) remain in audit mode or are deployed with exclusions for documented legitimate use.

ASR rules operate at the kernel level through Defender's script block logging and AMSI integration. A rule cannot be bypassed by running a different script engine or compiling the attack differently; the rule watches the behavior at the Win32 API layer. The limitation is that rules are specific; each rule addresses one attack pattern. ASR is not an anomaly detector; it is a pattern-block for known-bad behaviors.

## Prerequisites

* Intune-enrolled Windows 10 or Windows 11 devices
* Defender for Endpoint onboarded (automatic with Defender for Business or Plan 2)
* Test device or small pilot group for initial rule deployment and compatibility validation
* Inventory of line-of-business applications that may interact with ASR rules (especially applications using VBA macros, Outlook integration, or PSExec-style remote execution)
* User communication plan for any rule that may produce visible impact (blocked script, blocked macro, blocked child process)

## Target configuration

### The baseline 15 ASR rules

The baseline deploys 15 rules selected from Microsoft's ASR rule catalog. Each rule has a GUID; Microsoft's documentation covers full details. Summary table:

| Rule | Deployment | Mode |
|---|---|---|
| Block abuse of exploited vulnerable signed drivers | All variants | Block |
| Block Adobe Reader from creating child processes | All variants | Block |
| Block all Office applications from creating child processes | All variants | Block |
| Block credential stealing from LSASS | All variants | Block |
| Block executable content from email and webmail clients | All variants | Block |
| Block execution of potentially obfuscated scripts | All variants | Block |
| Block JavaScript or VBScript from launching downloaded executable content | All variants | Block |
| Block Office applications from creating executable content | All variants | Block |
| Block Office applications from injecting code into other processes | All variants | Block |
| Block Office communication application from creating child processes (Outlook) | All variants | Block |
| Block persistence through WMI event subscription | All variants | Block |
| Block untrusted and unsigned processes that run from USB | All variants | Block |
| Block Win32 API calls from Office macros | All variants | Block |
| Use advanced protection against ransomware | Plan 2 variants | Block |
| Block executables that do not meet a prevalence, age, or trusted list criterion | Plan 2 variants | Audit |
| Block process creations originating from PSExec and WMI commands | Plan 2 variants | Audit (MSP caveat) |

**The "audit mode" rules deserve explanation.** The last two rules above remain in audit rather than block because of documented false positive patterns in SMB environments. The prevalence/age rule blocks new or unusual executables that have not yet acquired Microsoft-observed prevalence; this can block legitimate custom-built business applications and installers. The PSExec/WMI rule blocks remote administration tools that MSPs routinely use for remote support. Tenants that do not use PSExec/WMI in administration can transition the latter to block after audit; tenants managed by MSPs should leave it in audit or deploy explicit exclusions for the MSP's administration hosts.

### Exclusions

Each ASR rule supports per-rule exclusions for paths or processes that should be exempt. The baseline deploys no initial exclusions; exclusions are added during the 30-day audit period based on observed false positives.

### Assignment scope

The baseline policy applies to all Windows devices in the tenant (Intune device group "All Windows Devices" or equivalent). Tenants with specialized device classes (point-of-sale, kiosk, industrial control) should scope separately; these devices often have application compatibility constraints that require tighter exclusions.

## Deployment procedure

### Step 1: Verify licensing and device state

```powershell
./27-Verify-ASRLicensing.ps1
```

The script reports ASR rule availability based on licensing and confirms Intune enrollment and Defender for Endpoint onboarding state.

### Step 2: Deploy the baseline rule set in audit mode

```powershell
./27-Deploy-ASRRules.ps1 -Mode "Audit"
```

The script creates an Intune device configuration profile assigning the 15 baseline rules in audit mode. Audit mode produces Defender event logs at the rule match level without blocking; this is the observation window for compatibility validation.

### Step 3: Monitor audit events for 30 days

```powershell
./27-Monitor-ASRAudit.ps1 -LookbackDays 30
```

The script queries the Defender advanced hunting for ASR audit events. Report includes:

* Event volume by rule
* Top processes triggering audit events
* Top devices by audit event count
* Potential false positive patterns requiring investigation or exclusion

Review weekly for the first month. Common patterns:

* **Legitimate application triggering a rule.** A specific line-of-business application uses a blocked behavior. Document and create a path or process exclusion.
* **Script execution in IT contexts.** IT administration scripts may trigger script execution rules. Scope the IT administration workstation group separately or add process exclusions.
* **USB device execution on shared computers.** Expected if USB is used for legitimate software distribution; uncommon in most SMB contexts. Scope exclusions narrowly.

### Step 4: Transition rules to block mode

After 30 days, transition rules with low observed false positive rates to block mode:

```powershell
./27-Transition-ASREnforcement.ps1 `
    -Rules "HighConfidenceSet" `
    -Mode "Block"
```

The HighConfidenceSet corresponds to 13 of the 15 baseline rules. The two rules that remain in audit (prevalence check, PSExec/WMI) can be transitioned individually after tenant-specific validation:

```powershell
./27-Transition-ASREnforcement.ps1 `
    -Rules "PSExecWMI" `
    -Mode "Block" `
    -Exclusions @("\\admin-host-01","\\admin-host-02")
```

### Step 5: Configure warnings (for variable-outcome rules)

Some rules support warn mode, in which the block happens but the user sees a prompt with an option to allow in specific cases. Warn mode is appropriate for rules where user context sometimes indicates legitimate intent:

```powershell
./27-Configure-ASRWarnMode.ps1 `
    -Rules "PrevalenceCheck" `
    -Mode "Warn"
```

The prevalence check rule in Warn mode asks the user whether to run an unusual executable; the user's response is logged and the executable runs or is blocked based on the user's choice.

### Step 6: Document exclusions

Any exclusion added during the tuning period needs documentation:

* What application or process required the exclusion
* Which rule or rules are affected
* Business justification
* Date added and review date (quarterly re-evaluation)

### Step 7: Verify deployment

```powershell
./27-Verify-Deployment.ps1
```

## Automation artifacts

* `automation/powershell/27-Verify-ASRLicensing.ps1` - License and device state verification
* `automation/powershell/27-Inventory-ASRRules.ps1` - Snapshot current ASR configuration
* `automation/powershell/27-Deploy-ASRRules.ps1` - Deploy baseline rule set
* `automation/powershell/27-Monitor-ASRAudit.ps1` - Audit event reporting
* `automation/powershell/27-Transition-ASREnforcement.ps1` - Mode transitions
* `automation/powershell/27-Configure-ASRWarnMode.ps1` - Warn mode configuration
* `automation/powershell/27-Deploy-ASRExclusions.ps1` - Apply documented exclusions
* `automation/powershell/27-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/27-Rollback-ASRRules.ps1` - Reverts to inventory snapshot

## Verification

### Configuration verification

```powershell
./27-Verify-Deployment.ps1
```

Output covers rule count deployed, mode per rule, assignment scope, exclusion count.

### Functional verification

Functional testing is performed with Microsoft's published ASR test tool or with curated test scenarios. Examples:

1. **Office child process block.** Open a test Word document that attempts to launch cmd.exe via VBA. Expected: block event in Defender.
2. **Credential theft block.** Attempt to run a known LSASS dumping technique (mimikatz-style test). Expected: block.
3. **Email client executable block.** Click a test executable attachment in Outlook. Expected: Outlook cannot launch the executable.
4. **USB unsigned execution block.** Place an unsigned executable on a USB drive; attempt to execute from USB. Expected: block.

Microsoft provides a curated demo at `https://demo.wd.microsoft.com/Page/ASR2` with specific test scenarios for each rule.

## Additional controls (add-on variants)

### Additional controls with Plan 2 (Defender Suite, E5 Security, E5)

Plan 2 adds additional rules beyond the baseline:

* **Use advanced protection against ransomware.** Heuristic analysis that detects ransomware-like file encryption patterns. Plan 1 includes basic anti-ransomware; Plan 2 adds advanced detection.
* **Block executables that do not meet a prevalence, age, or trusted list criterion.** Available on Plan 1 but Plan 2 provides better reporting and exclusion management.
* **Block process creations originating from PSExec and WMI commands.** Plan 2 only.

Plan 2 also adds:

* **ASR event surfaced in Defender XDR.** Rule matches appear in the XDR incident correlation; Plan 1 events appear in Defender security portal but do not participate in incident correlation.
* **Automated investigation of ASR events.** Plan 2 triggers AIR investigation on some rule matches; Plan 1 does not.
* **Advanced hunting of ASR events.** Plan 2 tenants can query ASR events in Advanced Hunting with specific schema tables; Plan 1 is limited to portal-based search.

### Additional controls with E5 Compliance or M365 E5

No direct ASR enhancement from E5 Compliance. The Adaptive Protection from Insider Risk Management (runbook 25) can interact with ASR indirectly: a user with elevated IRM risk score can trigger tighter DLP, which interacts with ASR on the same endpoint.

### Network Protection and Exploit Protection

Related to ASR but configured separately:

* **Network Protection.** Blocks access to domains with known-bad reputation from any process on the endpoint. Deploy alongside ASR; typically blocks C2 communication and malicious redirectors.
* **Exploit Protection.** OS-level mitigation of exploitation techniques (DEP, ASLR, SEHOP, etc.). Deploy through Intune; not a rule-based system like ASR but a policy of mitigations.

Both are covered in runbook 29 (web content filtering and network protection) and device compliance hardening.

## What to watch after deployment

* **Line-of-business application breakage.** The 30-day audit period catches most compatibility issues. Edge cases (applications used quarterly, seasonal software) may not appear in the audit period; plan for exclusion requests throughout the first year.
* **MSP administration tools.** PSExec, WMI remote invocation, PowerShell remoting, custom deployment tools. Audit the specific tools in use; create narrow exclusions rather than broad ones (specific administration host, specific account context).
* **User-visible blocks.** Most ASR rules block silently; some produce user-visible prompts. Users who see unexpected blocks report them as malfunctions. Prepare helpdesk with ASR context.
* **Update compatibility.** New Windows versions, Office versions, and third-party applications may interact with ASR rules in unexpected ways. Review audit events after major OS or application updates; add exclusions as needed.
* **Rule additions from Microsoft.** Microsoft adds new ASR rules periodically. The baseline covers the 15 rules available at the time of this writing; new rules warrant evaluation and possible inclusion. Review the ASR rule catalog quarterly.
* **False negative awareness.** ASR rules are pattern-specific. Novel attack techniques that do not match existing patterns are not blocked. ASR is not a complete endpoint protection; it is a layer. Antivirus, EDR, and behavioral analytics handle the patterns ASR does not.
* **Ransomware variants and advanced ransomware rule.** The Plan 2 advanced ransomware rule is effective against typical ransomware variants but sophisticated ransomware (living-off-the-land, manual operator techniques) can evade it. Combine with EDR behavioral analytics.
* **Exclusion creep.** Exclusions are added during tuning but rarely reviewed. Quarterly re-evaluation of exclusions (runbook 18) catches exclusions that are no longer needed and potential exclusion abuse.

## Rollback

```powershell
./27-Rollback-ASRRules.ps1 -InventorySnapshot "./asr-inventory-<DATE>.json" -Reason "Documented reason"
```

Rollback options:

* **Full rollback:** Removes the ASR configuration profile. Devices revert to default Windows behavior. Almost always inappropriate; individual rule tuning is preferable.
* **Rule-specific rollback:** Transition specific rules back to audit or disabled while preserving the rest. Use the Transition script with appropriate rule list.
* **Exclusion addition:** Common alternative to rollback. A specific false positive pattern is addressed with a targeted exclusion rather than rule disablement.

## References

* Microsoft Learn: [Attack surface reduction rules overview](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction)
* Microsoft Learn: [Attack surface reduction rules reference](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference)
* Microsoft Learn: [Deploy attack surface reduction rules](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-deployment)
* Microsoft Learn: [Test attack surface reduction rules](https://demo.wd.microsoft.com/Page/ASR2)
* M365 Hardening Playbook: [ASR rules not deployed](https://github.com/pslorenz/m365-hardening-playbook/blob/main/endpoint/no-asr-rules.md) (pending)
* CIS Microsoft 365 Foundations Benchmark v4.0: ASR recommendations
* MITRE ATT&CK: T1204.002 (Malicious File), T1059 (Command and Scripting Interpreter), T1003 (OS Credential Dumping)
* NIST CSF 2.0: PR.PT-04, PR.IP-12, DE.CM-04
