# 12 - Safe Links and Safe Attachments

**Category:** Defender for Office 365
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [11 - Anti-phishing and Anti-malware Policies](./11-anti-phish-anti-malware.md) completed
**Time to deploy:** 45 minutes active work, plus 7 days observation
**Deployment risk:** Medium. Safe Links rewrites URLs in email, which can produce visible changes to URL text that some users notice; Safe Attachments delays mail delivery for scanning, which can be noticed as latency.

## Purpose

This runbook deploys Safe Links and Safe Attachments: the time-of-click URL protection and dynamic attachment sandboxing features that catch threats the static anti-phishing and anti-malware policies miss. Static policies evaluate mail at the time of delivery; by the time a user clicks a link an hour later, the target URL may have changed (delayed-activation phishing) or the attachment may have been executed in a sandbox that determined it was malicious (but was already delivered).

Safe Links rewrites every URL in inbound email (and optionally Teams messages and Office documents) to route through a Microsoft inspection service. When a user clicks the link, the URL is evaluated against current threat intelligence; known-malicious URLs are blocked even if the URL was unknown at mail delivery time. Safe Attachments opens each attachment in a sandbox environment and observes its behavior; attachments that behave maliciously are blocked regardless of their static signature.

The tenant before this runbook: static anti-phishing and anti-malware policies from Runbook 11 are protecting mail at delivery time. URLs in delivered mail are not re-evaluated when clicked; attachments are scanned only for known-malicious signatures, not for dynamic behavior. Delayed-activation phishing (URLs that become malicious hours after delivery) and zero-day malware (attachments with no existing signature) reach users.

The tenant after: Safe Links rewrites URLs for time-of-click evaluation across email, Teams, and Office apps. Safe Attachments sandboxes attachments before delivery. Users clicking a URL that was clean at delivery time but malicious now see a block page; users opening an attachment that cleared static scanning but has malicious behavior see the attachment removed or replaced.

Both features are Plan 1 capabilities included in every Business Premium variant. The incremental cost is zero; the incremental protection is significant. These are among the highest-value default-off settings in the entire Microsoft 365 stack for SMB tenants.

## Prerequisites

* Anti-phishing and anti-malware policies from Runbook 11 deployed
* List of users or groups to exclude from Safe Links rewriting (usually empty; exclusions undermine the control)
* Decision on Safe Attachments policy action: Dynamic Delivery (default, ships preview while attachment is scanned), Block (holds mail), Replace (removes attachment but delivers mail), Monitor (allows but logs)
* Decision on Safe Links Teams scanning (recommended enabled; some organizations disable for chat-heavy workflows due to latency concerns)

## Target configuration

At completion:

### Safe Links policy

* **Safe Links for Email:** On
* **Track user clicks:** On
* **Let users click through to the original URL:** Off (blocks override attempts)
* **Apply real-time URL scanning for suspicious links:** On
* **Wait for URL scanning to complete before delivering the message:** On
* **Apply Safe Links to messages sent within the organization:** On (catches internal phishing from compromised accounts)
* **Do not track user clicks:** Off (tracking is valuable for incident response)
* **Do not rewrite URLs:** empty list (no exclusions)
* **Safe Links for Teams:** On
* **Safe Links for Office apps:** On (Word, Excel, PowerPoint click protection)
* **Use notification text customization:** Optional; organization may add branding

### Safe Attachments policy

* **Attachment action:** Dynamic Delivery (recommended for most SMBs) or Block
* **Enable redirect:** On (redirects malicious attachments to admin review mailbox)
* **Redirect address:** admin mailbox or distribution list for security team review
* **Apply Safe Attachments to the entire organization:** On
* **Safe Attachments for SharePoint, OneDrive, and Teams:** On (scans files stored in these services)
* **Safe Documents (E5 only):** On if licensed

## Deployment procedure

### Step 1: Deploy Safe Links policy

```powershell
./12-Deploy-SafeLinks.ps1 `
    -PolicyName "SMB Baseline Safe Links" `
    -AssignToAllRecipients
```

The script creates the Safe Links policy with the settings in the target configuration, creates the rule assigning the policy to all recipients, and verifies the policy becomes active.

Safe Links takes effect immediately for new inbound messages. Messages delivered before the policy was active are not retroactively rewritten. Teams and Office app protection may take a few hours to propagate through the tenant's Teams service.

### Step 2: Deploy Safe Attachments policy

```powershell
./12-Deploy-SafeAttachments.ps1 `
    -PolicyName "SMB Baseline Safe Attachments" `
    -AttachmentAction "DynamicDelivery" `
    -RedirectAddress "security-admin@contoso.com" `
    -AssignToAllRecipients
```

The script creates the Safe Attachments policy, configures the redirect address for malicious attachments (required so admins can investigate what was blocked), and assigns to all recipients.

On the attachment action choice:

* **Dynamic Delivery** delivers mail immediately with a placeholder showing "This attachment is being scanned." The body of the email is immediately readable; only the attachment is held during scanning. Once scanning completes (typically under 1 minute), the attachment replaces the placeholder. If found malicious, the attachment is removed and the user sees a replacement notice. **Recommended default for most SMBs.**
* **Block** holds the entire message until attachment scanning completes. More protective but produces noticeable mail latency. Appropriate for high-security contexts.
* **Replace** delivers mail with attachments removed; once scanning completes the attachment is either added back (clean) or replaced with a notice (malicious). Less common choice.
* **Monitor** allows messages through and logs detections but does not block. Appropriate only for initial pilot observation, not for production.

### Step 3: Enable Safe Attachments for SharePoint, OneDrive, and Teams

```powershell
./12-Enable-SafeAttachmentsForFiles.ps1
```

This enables scanning of files uploaded to SharePoint, OneDrive, and Teams. Files detected as malicious are blocked from access and flagged for administrator review. This is a tenant-wide setting, not a per-policy configuration.

### Step 4: Configure admin notifications

Safe Attachments detections and Safe Links blocks should generate admin notifications:

```powershell
./12-Configure-DefenderOfficeNotifications.ps1 `
    -SecurityAdminEmail "security-admin@contoso.com"
```

The script configures notification destinations for:
* Safe Attachments malware detection events
* Safe Links block events
* Zero-hour auto purge (ZAP) events for links (URLs detected malicious after delivery)

### Step 5: Monitor during the first 7 days

```powershell
./12-Monitor-SafeLinksAndAttachments.ps1 -LookbackDays 7
```

Report includes:
* Safe Links clicks evaluated and blocked
* Safe Attachments detections by attachment name and hash
* URL categories of blocked clicks (phishing, malware, suspicious)
* Top users hitting blocked links (training opportunities, not blame)
* False positive candidates: legitimate URLs or attachments that were blocked

Review the output weekly. Common tuning based on observed false positives:

* **Legitimate business URLs blocked:** if a partner's URL is consistently blocked but is legitimate, report through Microsoft's admin submission feature rather than allow-listing. The global Microsoft threat intelligence improves for all customers when false positives are reported back.
* **Internal application URLs blocked:** if the tenant has internal web applications at domains that Safe Links treats as suspicious, consider adding those specific URLs to the "Do not rewrite" list. Document the exception with a review date.
* **Partner attachments blocked:** specific partner patterns that consistently produce false positives. Investigate whether the partner is sending actually-questionable content or whether the file type is triggering pattern matching that needs adjustment.

### Step 6: Update operations runbook

Document:
* Safe Links policy name and scope
* Safe Attachments policy name, action mode, and redirect address
* SharePoint/OneDrive/Teams scanning enabled
* Admin notification destinations
* Process for reviewing redirected malicious attachments
* Process for submitting false positives to Microsoft
* Monthly report review cadence

## Automation artifacts

* `automation/powershell/12-Deploy-SafeLinks.ps1` - Creates the Safe Links policy
* `automation/powershell/12-Deploy-SafeAttachments.ps1` - Creates the Safe Attachments policy
* `automation/powershell/12-Enable-SafeAttachmentsForFiles.ps1` - Enables file scanning in SharePoint/OneDrive/Teams
* `automation/powershell/12-Configure-DefenderOfficeNotifications.ps1` - Routes detection notifications
* `automation/powershell/12-Monitor-SafeLinksAndAttachments.ps1` - Reports detection activity
* `automation/powershell/12-Verify-Deployment.ps1` - Confirms the runbook's target state
* `automation/powershell/12-Rollback-SafeLinksAndAttachments.ps1` - Disables the deployed policies

## Verification

### Configuration verification

```powershell
./12-Verify-Deployment.ps1
```

Expected output covers Safe Links policy existence and settings, Safe Attachments policy existence and settings, file scanning enabled flag, and a spot-check of recent enforcement activity.

### Functional verification

1. **Safe Links rewrites inbound URLs.** Send a test message with a plain URL (for example, `https://example.com`) to an enrolled recipient. Open the received message. Expected: the URL displays as the original text but the underlying link is a Microsoft wrapper URL.
2. **Safe Links blocks known-malicious URL.** Send a test message with a URL on Microsoft's test-malicious-URL list (https://msfttest.com/test). Click the link. Expected: Safe Links block page appears.
3. **Safe Attachments sandboxes attachments.** Send a test message with a benign Office document to a recipient. Observe the attachment rendering: initial placeholder, then the actual attachment appearing after scan completion (if Dynamic Delivery is configured).
4. **Safe Attachments catches malicious attachment.** Using the EICAR test file or a sanctioned malware test archive, send the attachment. Expected: attachment is removed and replaced with notification; admin receives notification at the configured address.
5. **SharePoint file scanning detects malicious upload.** Upload the EICAR test file to a test SharePoint library. Expected: file is quarantined and user sees blocked-access indicator.

## Additional controls (add-on variants)

### Additional controls with Defender Suite, E5 Security, or EMS E5 (Defender for Office 365 Plan 2)

Plan 2 adds Safe Documents (available at E5 only, not included in Defender Suite unless explicitly licensed). Safe Documents extends Safe Attachments to files opened in Protected View in Office applications, providing sandbox scanning at time-of-open rather than only at time-of-receipt.

```powershell
./12-Enable-SafeDocuments.ps1
```

The script verifies E5 licensing and enables Safe Documents if licensed. For Defender Suite tenants (which include Plan 2 Safe Links and Safe Attachments but not Safe Documents), this script logs that the capability is not licensed and exits cleanly.

Additional Plan 2 capabilities available after this runbook:
* **Real-time detection reports:** richer telemetry than Plan 1's basic reports
* **Campaign views:** groups related threats into campaign context
* **Threat trackers:** follow specific threat indicators over time
* **Automated Investigation and Response playbooks** triggered by Safe Links and Safe Attachments detections (configured in audit runbook)

For plain Business Premium (Plan 1 only), the features in this runbook are the full Safe Links and Safe Attachments capability; Plan 2 extensions are unavailable.

## What to watch after deployment

* **Mail delivery latency.** Dynamic Delivery typically adds 1 to 30 seconds of attachment scanning time, visible to users as the attachment placeholder-then-resolve pattern. Block mode adds up to 5 minutes of full-message latency. If users report mail delays beyond normal, verify the policy action is not Block when it should be Dynamic Delivery.
* **Teams message scanning latency.** Safe Links for Teams adds small latency to message delivery in high-volume chat contexts. Teams users may notice the delay during bursty conversations; usually acceptable for the protection benefit.
* **URL rewrite visibility.** Some users notice that URLs in their inbox display differently and become confused. One-time user communication explaining why URLs look rewritten is often enough; the technical explanation (click-time evaluation) resonates with most users.
* **Self-service click-through requests.** Users blocked by Safe Links have a click-through option if enabled (default is disabled in this runbook's deployment). If enabled and used, track the rate; high click-through rates suggest either legitimate false positives or users who are being socially engineered through the block page.
* **Attachment redirect mailbox growth.** The redirect address for Safe Attachments accumulates every malicious attachment detected. Configure retention and automated processing (review queue, hash extraction for threat intelligence); the mailbox otherwise grows unbounded.
* **Internal phishing.** Safe Links applies to intra-org messages only if that setting was enabled (recommended). A compromised internal account sending phish to colleagues gets the same Safe Links treatment as external mail. If this setting was disabled during deployment, internal phish bypasses Safe Links entirely.

## Rollback

```powershell
./12-Rollback-SafeLinksAndAttachments.ps1 -InventorySnapshot "./email-policy-inventory-<DATE>.json"
```

The rollback disables both policies, returning to the pre-deployment state. Messages delivered before rollback retain their Safe Links URL rewrites (that is a characteristic of the specific message, not the current policy state).

Targeted rollback for specific users or specific scenarios (exclude a group of users from Safe Links while keeping everyone else protected) is usually a better alternative than full rollback:

```powershell
./12-Deploy-SafeLinks.ps1 -PolicyName "SMB Baseline Safe Links" -ExcludedGroups @("Legacy Partner Email")
```

The exclusion approach preserves protection for the bulk of the user population while accommodating specific documented edge cases.

## References

* Microsoft Learn: [Safe Links in Microsoft Defender for Office 365](https://learn.microsoft.com/en-us/defender-office-365/safe-links-about)
* Microsoft Learn: [Set up Safe Links policies](https://learn.microsoft.com/en-us/defender-office-365/safe-links-policies-configure)
* Microsoft Learn: [Safe Attachments in Microsoft Defender for Office 365](https://learn.microsoft.com/en-us/defender-office-365/safe-attachments-about)
* Microsoft Learn: [Set up Safe Attachments policies](https://learn.microsoft.com/en-us/defender-office-365/safe-attachments-policies-configure)
* Microsoft Learn: [Safe Attachments for SharePoint, OneDrive, and Teams](https://learn.microsoft.com/en-us/defender-office-365/safe-attachments-for-spo-odfb-teams-about)
* Microsoft Learn: [Submit messages to Microsoft for analysis](https://learn.microsoft.com/en-us/defender-office-365/submissions-admin)
* M365 Hardening Playbook: [Safe Links and Safe Attachments not configured](https://github.com/pslorenz/m365-hardening-playbook/blob/main/defender-for-office/safe-links-safe-attachments.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Safe Links and Safe Attachments recommendations
* NIST CSF 2.0: PR.DS-02, DE.CM-04
