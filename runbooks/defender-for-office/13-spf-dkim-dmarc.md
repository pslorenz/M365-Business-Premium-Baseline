# 13 - SPF, DKIM, and DMARC Email Authentication

**Category:** Defender for Office 365
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [11 - Anti-phishing and Anti-malware Policies](./11-anti-phish-anti-malware.md) deployed (spoof intelligence relies on proper domain authentication)
* DNS administrative access for each sending domain (or the ability to submit DNS change requests with appropriate SLA)
**Time to deploy:** 2 hours active work for initial deployment, then 3 to 6 months of DMARC policy progression from p=none to p=reject
**Deployment risk:** Medium. Misconfigured SPF or DKIM blocks legitimate mail; aggressive DMARC enforcement without observation blocks legitimate third-party senders. This runbook uses a progressive-rollout approach to catch misconfiguration before enforcement.

## Purpose

This runbook deploys the three email authentication mechanisms that establish the tenant's sending domains as legitimate senders: SPF (Sender Policy Framework) declares authorized sending infrastructure, DKIM (DomainKeys Identified Mail) cryptographically signs outbound messages, and DMARC (Domain-based Message Authentication, Reporting, and Conformance) tells receiving mail systems what to do when SPF or DKIM fails. Together, they prevent the tenant's domain from being spoofed in attacks against the tenant's own users, against partners, or against the broader internet.

The tenant before this runbook: SPF may exist in a default or partial state (Microsoft's `include:spf.protection.outlook.com` but without coverage for third-party senders). DKIM is in default state: 1024-bit keys generated at tenant creation and never rotated, or not enabled at all for custom domains. DMARC is absent entirely or set to `p=none` without monitoring. An attacker can send mail from `ceo@contoso.com` through arbitrary infrastructure and receive neither SPF failure nor DKIM failure nor DMARC enforcement; the mail is delivered to partners and internal users without authentication markers.

The tenant after: SPF correctly enumerates every authorized sender (Microsoft 365, email marketing platform, transactional email provider, CRM, and any other legitimate sender). DKIM uses 2048-bit keys and is enabled for every sending domain with scheduled annual rotation. DMARC is in place with a progression plan: `p=none` with `rua` reporting to catch current legitimate failures, then `p=quarantine` once failures are resolved, then `p=reject` as the final state. Mail from the tenant's domains is authenticated end-to-end; spoofed mail fails authentication and is rejected or quarantined by receiving systems per DMARC policy.

The authentication-layer controls here pair with the content-layer controls from Runbooks 11 and 12. Content analysis catches the majority of commodity threats; authentication catches the spoofing attacks that evade content analysis by looking legitimate in content while being demonstrably inauthentic at the protocol layer. Both layers are necessary; neither alone is sufficient.

## Prerequisites

* Complete inventory of sending domains: all domains from which the organization sends email
* Complete inventory of legitimate senders per domain: Microsoft 365 (always present), email marketing tools, CRM systems, HR/payroll systems, transactional email providers, service desk systems, any other automated sender
* DNS administrative access for each sending domain
* DMARC report aggregation endpoint: either a dedicated tool (DMARC analyzer, Valimail, Dmarcian, etc.) or a mailbox with tooling to parse aggregate reports
* Understanding that DMARC enforcement rollout is a multi-month process; do not plan to reach `p=reject` in week one

## Target configuration

At completion:

* **SPF record** for every sending domain includes:
    * Microsoft 365: `include:spf.protection.outlook.com`
    * Every legitimate third-party sender with appropriate `include:` statement
    * `-all` hard fail at the end (not `~all` softfail; hard fail is the correct SPF position once inventory is confirmed complete)
* **DKIM** enabled for every sending domain:
    * 2048-bit keys (not default 1024-bit)
    * Both CNAME records (selector1 and selector2) published in DNS
    * Rotation scheduled annually
* **DMARC** record for every sending domain:
    * **Initial state:** `v=DMARC1; p=none; rua=mailto:<aggregator>; pct=100`
    * **Month 2 to 3 target:** `v=DMARC1; p=quarantine; rua=mailto:<aggregator>; pct=100`
    * **Month 4 to 6 target:** `v=DMARC1; p=reject; rua=mailto:<aggregator>; pct=100; adkim=s; aspf=s`
* **ARC trust chain** configured for Microsoft 365 (automatic for all tenants; no explicit configuration)

## Deployment procedure

### Step 1: Inventory sending domains and senders

```powershell
./13-Inventory-EmailAuthentication.ps1 -OutputPath "./email-auth-inventory-$(Get-Date -Format 'yyyyMMdd').json"
```

The script enumerates accepted domains in Exchange Online, checks current SPF/DKIM/DMARC state for each, and writes an inventory. Review the output and augment with:

* Non-tenant sending domains (parent company mail, partner mail relays)
* Non-Microsoft 365 senders for each domain (marketing platforms, CRM, etc.)
* Historical senders that may have been used but are no longer in scope

Build a complete list before proceeding to Step 2; incomplete inventory produces either SPF failures for legitimate senders (after `-all` is applied) or DMARC failures that mask other issues.

### Step 2: Deploy or verify SPF records

For each sending domain, publish or update the SPF record in DNS:

```powershell
./13-Generate-SPFRecord.ps1 `
    -Domain "contoso.com" `
    -Includes @("spf.protection.outlook.com", "sendgrid.net", "spf.mailgun.org") `
    -PublishMethod "Output"
```

The script generates the SPF record text and outputs it for manual DNS publication. SPF is a DNS-layer configuration; most tenants manage DNS outside of Microsoft Graph, so the script produces the correct record for the organization's DNS administrator to publish.

The SPF record format:
```
v=spf1 include:spf.protection.outlook.com include:sendgrid.net include:spf.mailgun.org -all
```

Notes on SPF record construction:

* **Use `include:` for cloud senders.** Hard-coded IP addresses break when the provider changes infrastructure.
* **Use `-all` (hard fail), not `~all` (soft fail).** Hard fail is correct for modern email infrastructure. Soft fail is a historical holdover.
* **Respect the 10-lookup limit.** SPF records cannot chain more than 10 DNS lookups (each `include:` counts). If the organization has many senders, use SPF flattening services or consolidate senders.
* **Do not use `+all` or `?all`.** Both defeat the purpose of SPF.

After publishing, verify:

```powershell
./13-Verify-SPFRecord.ps1 -Domain "contoso.com"
```

The script queries the current SPF record via DNS and reports any issues (missing senders, wrong qualifier, too many lookups).

### Step 3: Enable or rotate DKIM with 2048-bit keys

```powershell
./13-Enable-DKIM.ps1 -Domain "contoso.com" -KeyLength 2048
```

The script:

1. Generates new 2048-bit DKIM keys via Exchange Online (Microsoft's default is 1024-bit which is insufficient for modern cryptographic standards)
2. Returns the two CNAME records that need to be published in DNS (selector1 and selector2)
3. After DNS publication is confirmed (manually), enables DKIM signing on the domain

DKIM CNAME records follow the pattern:
```
selector1._domainkey.contoso.com    CNAME    selector1-contoso-com._domainkey.<tenant>.onmicrosoft.com
selector2._domainkey.contoso.com    CNAME    selector2-contoso-com._domainkey.<tenant>.onmicrosoft.com
```

For tenants that already have DKIM enabled with 1024-bit keys, the script supports rotation:

```powershell
./13-Rotate-DKIM.ps1 -Domain "contoso.com"
```

The rotation rotates between `selector1` and `selector2`, upgrading to 2048-bit during the rotation. The process is transparent to mail flow; the old selector remains valid for a grace period while outbound mail signs with the new selector.

Verify DKIM signing is working:

```powershell
./13-Verify-DKIM.ps1 -Domain "contoso.com"
```

The script sends a test message, checks the message header for DKIM signature presence, and verifies the signature validates.

### Step 4: Deploy DMARC record in p=none state

```powershell
./13-Deploy-DMARC.ps1 `
    -Domain "contoso.com" `
    -Policy "none" `
    -AggregateReportAddress "dmarc-reports@contoso.com" `
    -FailureReportAddress "dmarc-failures@contoso.com"
```

The script generates the DMARC record and outputs it for DNS publication. Initial DMARC state:

```
v=DMARC1; p=none; rua=mailto:dmarc-reports@contoso.com; ruf=mailto:dmarc-failures@contoso.com; pct=100
```

Notes:

* **`p=none`** is the initial state. Do not start at `quarantine` or `reject`. A misconfigured DMARC can block all the tenant's mail; `p=none` produces reporting without enforcement.
* **`rua`** (aggregate reports) is essential. Without `rua`, DMARC deployment produces no visibility into what's passing or failing. Use a DMARC analyzer (Dmarcian, Valimail, EasyDMARC) or a dedicated mailbox with tooling.
* **`ruf`** (failure reports) is optional and produces per-message failure data. Useful for tuning but can be high volume. Dedicate a mailbox with filtering.
* **`pct=100`** evaluates 100 percent of mail. Lower percentages are useful only during carefully-staged rollout.

### Step 5: Monitor DMARC aggregate reports for 30 to 60 days

Aggregate reports arrive at the `rua` destination daily from receiving mail systems worldwide (Gmail, Yahoo, Microsoft, ProtonMail, etc.). Each report contains summary data for the previous 24 hours: how many messages claimed the tenant's domain as sender, how many passed SPF, how many passed DKIM, how many passed DMARC alignment.

```powershell
./13-Analyze-DMARCReports.ps1 -ReportMailbox "dmarc-reports@contoso.com"
```

The script (or the third-party analyzer) parses aggregate reports and produces a view of:

* Total mail claiming the tenant's domain: legitimate + spoofed
* Pass rate broken down by sender infrastructure
* Senders with SPF or DKIM failures that are legitimate (tuning targets)
* Senders that are not legitimate (attack indicators)

Review weekly during the monitoring period. Typical findings:

* **Legitimate sender not in SPF:** add the sender to SPF (Step 2 update)
* **Legitimate sender sending without DKIM:** configure the sender's DKIM signing (sender-specific; each SaaS vendor has their own documentation)
* **Spoofed mail at low volume:** expected background attack traffic; DMARC enforcement will block this
* **Spoofed mail from specific sources at high volume:** indicates active phishing campaigns against the organization; combines with threat hunting efforts

### Step 6: Progress to p=quarantine

After 30 to 60 days of monitoring, once SPF and DKIM alignment is solid for legitimate senders, tighten to quarantine:

```powershell
./13-Update-DMARC.ps1 -Domain "contoso.com" -Policy "quarantine"
```

The new record:

```
v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@contoso.com; pct=100
```

Effect: receiving mail systems now quarantine (move to Junk or quarantine folder) mail that fails DMARC. Legitimate senders should continue to deliver. Monitor for 30 days to catch any sender that slipped through initial monitoring.

### Step 7: Progress to p=reject

After another 30 to 60 days at `p=quarantine` with clean aggregate reports, tighten to reject:

```powershell
./13-Update-DMARC.ps1 -Domain "contoso.com" -Policy "reject" -StrictAlignment
```

Final state:

```
v=DMARC1; p=reject; rua=mailto:dmarc-reports@contoso.com; pct=100; adkim=s; aspf=s
```

Effect: receiving mail systems reject mail that fails DMARC. Legitimate senders should all be aligned by this point. Strict alignment (`adkim=s; aspf=s`) adds precision by requiring the `From:` domain to match exactly (not just be a subdomain match) for DMARC pass.

### Step 8: Document and establish rotation cadence

Update the operations runbook:

* Each domain's current SPF, DKIM, and DMARC state
* DMARC aggregate report destination and who monitors it
* DKIM key rotation schedule (annually recommended)
* New-sender addition process: how to add a legitimate new sender to SPF without breaking authentication
* Monthly review of DMARC reports during steady-state operation

## Automation artifacts

* `automation/powershell/13-Inventory-EmailAuthentication.ps1` - Captures current SPF/DKIM/DMARC state per domain
* `automation/powershell/13-Generate-SPFRecord.ps1` - Produces correct SPF record text for DNS publication
* `automation/powershell/13-Verify-SPFRecord.ps1` - Validates published SPF records
* `automation/powershell/13-Enable-DKIM.ps1` - Generates 2048-bit DKIM keys and enables signing
* `automation/powershell/13-Rotate-DKIM.ps1` - Rotates DKIM selector with key upgrade
* `automation/powershell/13-Verify-DKIM.ps1` - Validates DKIM signing on a domain
* `automation/powershell/13-Deploy-DMARC.ps1` - Generates DMARC record for DNS publication
* `automation/powershell/13-Update-DMARC.ps1` - Transitions DMARC policy state
* `automation/powershell/13-Analyze-DMARCReports.ps1` - Parses aggregate reports (optional; most tenants use SaaS)
* `automation/powershell/13-Verify-Deployment.ps1` - End-to-end verification of email authentication

## Verification

### Configuration verification

```powershell
./13-Verify-Deployment.ps1 -Domain "contoso.com"
```

Expected output:

```
Domain: contoso.com

SPF:
  Record present: Yes
  Qualifier: -all (hard fail, correct)
  Lookup count: 5 of 10 allowed
  Known senders present: Microsoft 365, [third-party list]

DKIM:
  Enabled: Yes
  Key length: 2048
  Selector1 CNAME: Valid
  Selector2 CNAME: Valid
  Last rotation: [date]

DMARC:
  Record present: Yes
  Policy: reject (or quarantine or none)
  Percentage: 100
  Aggregate report address: dmarc-reports@contoso.com
  Alignment mode: strict (adkim=s, aspf=s)
```

### Functional verification

1. **SPF passes for legitimate Microsoft 365 mail.** Send a test message from a tenant mailbox to an external address. Check the received message's headers for `spf=pass`.
2. **DKIM signs outbound mail.** Same test as SPF; check headers for `dkim=pass` with the correct selector.
3. **DMARC alignment passes.** Headers should show `dmarc=pass`.
4. **Spoofed mail is rejected at p=reject.** From an external test infrastructure, send a message spoofing the tenant's domain (using a sanctioned test scenario). Expected: message is rejected by receiving infrastructure due to DMARC policy.
5. **Aggregate reports arrive at the destination.** Confirm daily reports are accumulating at the configured `rua` address.

## Additional controls (add-on variants)

### Additional controls with any variant (no add-on gating)

The controls in this runbook work identically across variants. SPF, DKIM, and DMARC are DNS-layer mechanisms independent of Microsoft 365 licensing tier. The Plan 2 features in Runbook 12 and later runbooks consume DMARC signals for enhanced threat analysis, but the authentication mechanisms themselves are variant-independent.

### Authenticated Received Chain (ARC)

ARC trust for Microsoft 365 is automatic; mail passing through Microsoft's infrastructure is automatically ARC-sealed. Tenants do not configure ARC for their own domain; they configure ARC trust for upstream forwarders (mailing lists, email gateways, mail forwarders) that might break SPF or DKIM by modifying messages in transit.

If the tenant has upstream forwarders that cause DMARC failures (legitimate mail being forwarded through a third-party gateway that modifies headers), configure ARC trust:

```powershell
./13-Configure-ARCTrust.ps1 -TrustedSealer "forwarder.example.com"
```

ARC trust instructs Exchange Online to honor the ARC seal from the specified sealer, bypassing DMARC failure that would otherwise occur due to forwarding. Use cautiously; adding untrusted sealers to ARC trust defeats DMARC.

## What to watch after deployment

* **DMARC aggregate report volume.** Typical SMB tenant receives daily reports from 50 to 500 receiving systems. Sudden volume spikes indicate phishing campaigns using the domain; investigate.
* **SPF lookup count approaching the 10-lookup limit.** Adding new senders eventually hits the 10-lookup cap. Symptoms: legitimate mail fails SPF with permerror. Remediate by flattening SPF includes or removing unused senders.
* **DKIM key rotation.** Microsoft does not automatically rotate keys. Annual rotation reduces exposure of key compromise. Track rotation date in operations runbook.
* **New third-party senders being added.** Marketing starts using a new email platform, HR moves to a new payroll vendor, IT deploys a new ticketing system. Each produces mail that fails authentication until added to SPF and DKIM. Establish a process: new sender request includes authentication setup before go-live.
* **Phishing campaign volume against the domain.** DMARC aggregate reports show spoofed mail volume. A consistent baseline of low-volume spoofing (dozens per day per domain) is background; sudden spikes indicate targeted campaigns.

## Rollback

Rollback of DMARC: move back from `p=reject` to `p=quarantine` or `p=none` if enforcement is blocking legitimate mail that was missed during monitoring. Use `13-Update-DMARC.ps1` with the looser policy.

SPF and DKIM rollback is more disruptive because it enables spoofing. Do not roll back SPF or DKIM without deliberate decision; targeted adjustments (adding a missing sender to SPF, disabling DKIM for a specific problematic domain) are almost always better than rollback.

Full rollback of the runbook:

```powershell
./13-Rollback-EmailAuthentication.ps1 -InventorySnapshot "./email-auth-inventory-<DATE>.json"
```

Restores the pre-deployment state. Rarely appropriate; the correct response to email-authentication deployment issues is usually continued tuning rather than reversion.

## References

* Microsoft Learn: [How Microsoft 365 uses Sender Policy Framework (SPF) to help prevent spoofing](https://learn.microsoft.com/en-us/defender-office-365/email-authentication-spf-configure)
* Microsoft Learn: [Use DKIM to validate outbound email sent from your custom domain](https://learn.microsoft.com/en-us/defender-office-365/email-authentication-dkim-configure)
* Microsoft Learn: [Use DMARC to validate email](https://learn.microsoft.com/en-us/defender-office-365/email-authentication-dmarc-configure)
* RFC 7208 (SPF), RFC 6376 (DKIM), RFC 7489 (DMARC), RFC 8617 (ARC)
* M3AAWG: [Sender Best Common Practices](https://www.m3aawg.org/sites/default/files/m3aawg-senders-bcp-ver3-2015-02.pdf)
* M365 Hardening Playbook: [DKIM not using 2048-bit keys or not rotated](https://github.com/pslorenz/m365-hardening-playbook/blob/main/defender-for-office/dkim-weak-or-not-rotated.md)
* M365 Hardening Playbook: [DMARC policy at p=none or missing](https://github.com/pslorenz/m365-hardening-playbook/blob/main/defender-for-office/dmarc-not-enforced.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Email authentication recommendations
* NIST CSF 2.0: PR.DS-02, PR.AC-01
