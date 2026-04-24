# 22 - SharePoint and OneDrive External Sharing Controls

**Category:** Data Protection
**Applies to:** All variants (Plain Business Premium, Defender Suite, Purview Suite, Defender & Purview, EMS E5, M365 E5)
**Prerequisites:**
* [14 - Unified Audit Log Verification and Retention](../audit-and-alerting/14-ual-verification-retention.md) completed

**Time to deploy:** 90 minutes active work, plus 7 days observation for external sharing activity
**Deployment risk:** Medium. Changes to external sharing defaults can break existing collaboration relationships. The runbook includes explicit pre-deployment discovery of current external sharing scope.

## Purpose

This runbook configures SharePoint and OneDrive external sharing to balance legitimate collaboration against data exfiltration through oversharing. SharePoint and OneDrive are the most common data movement channels in Microsoft 365: every email attachment over 25 MB routes through OneDrive, every Teams file lives in SharePoint, every collaborative document is a SharePoint or OneDrive artifact. The default external sharing settings are permissive because Microsoft optimizes for collaboration out of the box; production tenants almost always need tighter controls.

The tenant before this runbook: SharePoint tenant-level sharing is at default (often "Anyone" with anonymous links enabled). OneDrive sharing is at default (same). Guest users can access files through anonymous links that do not require authentication, expire only if the creator sets an expiration, and leave no trail when the link is shared further. Any user can share any file with anyone. The result is frictionless collaboration and a significant data exfiltration surface.

The tenant after: tenant-level external sharing is set to the appropriate tier for the organization (typically "New and existing guests" with authentication required). Anonymous link expiration is enforced. Guest access requires Entra B2B invitation rather than direct anonymous sharing. Site-level sharing settings align with or tighten against the tenant level. OneDrive personal site sharing matches the tenant posture. External sharing activity is logged and reviewable; bulk external sharing patterns are alertable through Runbook 16's data access detections.

Three external sharing scenarios need to be distinguished and handled separately:

* **Internal collaboration:** within the tenant. Governed by site permissions and Conditional Access. Not addressed by external sharing settings.
* **Authenticated external collaboration:** guests invited through Entra B2B, appearing in the directory as guest users. Governed by guest-user settings in Entra and by SharePoint's external sharing tier. This is the right pattern for recurring external relationships (vendors, partners, clients).
* **Anonymous link sharing:** file or folder shared with "Anyone with the link." No authentication required; the link holder has access. Appropriate for narrow, time-bounded, low-sensitivity sharing; dangerous when used as the default pattern.

This runbook configures each scenario explicitly rather than leaving defaults.

## Prerequisites

* Global Administrator or SharePoint Administrator role
* List of current SharePoint sites and their external sharing state
* Identification of sites with business-critical external collaboration (partner portals, customer document exchange)
* Decision on tenant-level sharing tier: "Only people in your organization," "Existing guests only," "New and existing guests," or "Anyone"
* Default link type decision: "People with existing access," "Specific people," "People in your organization," or "Anyone"

## Target configuration

### Tenant-level SharePoint sharing

* **External sharing:** "New and existing guests" (authenticated external collaboration; no anonymous links by default)
* **Default link type:** "Specific people" (most restrictive default; users must deliberately broaden)
* **Anonymous link expiration:** 30 days maximum
* **Anonymous link permissions:** View only by default (not Edit)
* **Guest reauthentication:** required every 30 days
* **Allow guests to share items they don't own:** Off
* **Limit external sharing by domain:** On, with allow list of approved domains (if the organization has specific partner domains) or block list of known-problematic domains

### Tenant-level OneDrive sharing

* **External sharing:** Inherits from SharePoint tenant setting unless tightened
* **Default link type:** "People in your organization" (OneDrive is personal storage; external sharing should be intentional)
* **Anonymous link expiration:** 30 days maximum
* **Notify users of shared items:** On (so users see when their content is shared)

### Site-level sharing defaults for new sites

* **External sharing tier:** Inherits from tenant
* **Default link type:** Specific people
* **Link expiration:** 30 days

### Sharing policy for existing sites

* **Highly Confidential sites:** set external sharing to "Only people in your organization"
* **Confidential sites:** set external sharing to "Existing guests only"
* **Internal/General sites:** tenant default

This requires mapping existing sites to a sensitivity level, which depends on whether sensitivity labels (Runbook 21) have been applied to sites. The deployment script supports both label-based and manual site categorization.

## Deployment procedure

### Step 1: Inventory current external sharing state

```powershell
./22-Inventory-ExternalSharing.ps1 -OutputPath "./external-sharing-inventory-$(Get-Date -Format 'yyyyMMdd').json"
```

The script captures:

* Tenant-level SharePoint external sharing settings
* Tenant-level OneDrive settings
* Per-site external sharing tiers (sample of top 50 most-active sites)
* Current guest user count
* Recent external sharing activity (last 30 days)

Review the output before making changes. Large guest user counts, high external sharing activity, or sites with "Anyone" sharing need stakeholder discussion before deploying tighter settings.

### Step 2: Audit external sharing activity for business criticality

```powershell
./22-Audit-ExternalSharingActivity.ps1 -LookbackDays 90
```

The script queries UAL for external sharing events in the past 90 days:

* Which users shared externally and how often
* Which sites had the most external sharing
* Which external domains received the most shares
* Anonymous link creation activity

Review the output and identify any business-critical external collaboration that depends on current (permissive) settings. These are the scenarios that need explicit accommodation in the tightened configuration.

### Step 3: Communicate the upcoming change

Before deploying, send a tenant-wide communication covering:

* The new tenant-level default (new external shares require authentication)
* What happens to existing anonymous links (they continue to work until expiration)
* The process for legitimate external sharing under the new settings (guest invitation through Entra B2B)
* The helpdesk process for "I need to share something with an external party"

The communication should be sent 5 to 10 days before deployment. Use the operations runbook template for this communication.

### Step 4: Deploy tenant-level settings

```powershell
./22-Deploy-TenantSharingSettings.ps1 `
    -SharingCapability "ExternalUserSharingOnly" `
    -DefaultLinkType "Direct" `
    -AnonymousLinkExpirationDays 30 `
    -AnonymousLinkPermission "View" `
    -RequireGuestReauth $true `
    -AllowedDomains @("trusted-partner.com","accounting-firm.com")
```

Parameters explained:

* **SharingCapability:** `ExternalUserSharingOnly` equals "New and existing guests" (authenticated external; no anonymous). Alternatives: `ExistingExternalUserSharingOnly` (existing guests only), `Disabled` (no external sharing), `ExternalUserAndGuestSharing` (allows anonymous links).
* **DefaultLinkType:** `Direct` equals "Specific people" (most restrictive).
* **AllowedDomains:** external domains with which sharing is permitted. Leave empty for no domain restriction; specify for tighter control. Mutually exclusive with `BlockedDomains`.

### Step 5: Deploy OneDrive-specific settings

```powershell
./22-Deploy-OneDriveSharingSettings.ps1 `
    -DefaultLinkType "Internal" `
    -NotifyOwners $true
```

OneDrive defaults to tighter than SharePoint because personal storage should not default to external sharing.

### Step 6: Deploy site-level settings for high-sensitivity sites

If sensitivity labels are deployed (Runbook 21), use label-based site categorization:

```powershell
./22-Apply-LabelBasedSiteSettings.ps1
```

The script iterates sites with applied sensitivity labels and sets external sharing appropriate to the label. Sites labeled Highly Confidential get "Only people in your organization"; Confidential sites get "Existing guests only."

If labels are not deployed, use a manual site list:

```powershell
./22-Apply-SiteSharingSettings.ps1 `
    -SitesListPath "./high-sensitivity-sites.csv"
```

The CSV format: one column `SiteUrl`, one column `SharingTier` with values `None`, `ExistingGuests`, `ExternalUser`, or `Anyone`.

### Step 7: Monitor for 7 days

```powershell
./22-Monitor-SharingActivity.ps1 -LookbackDays 7
```

Report covers:

* Anonymous link creation attempts (should be zero after Step 4)
* Guest user invitations (expected activity under the new settings)
* External share failures (users hitting the tightened settings)
* Helpdesk tickets related to sharing changes

Review weekly for the first month. Common tuning:

* **Legitimate business patterns blocked:** specific partner domain that should be in the allowed list but was missed, specific site that needs looser settings than tenant default.
* **User-reported friction:** training gap on how to invite guests properly, unclear guidance on which link type to use.
* **Anonymous link expiration producing broken links:** existing anonymous links expire and need to be reissued. This is expected behavior; the communication plan should have set expectations.

### Step 8: Deploy external sharing reports

Schedule periodic external sharing reports to the security admin:

```powershell
./22-Schedule-SharingReports.ps1 `
    -RecipientEmail "security-admin@contoso.com" `
    -Frequency "Weekly"
```

The scheduled report includes: new guest invitations, new external shares by site, bulk sharing events (potential exfiltration), and anomalous sharing patterns.

### Step 9: Document the posture

Update the operations runbook:

* Tenant-level sharing tier and default link type
* Anonymous link expiration policy
* OneDrive sharing defaults
* Site-level exceptions and their justification
* Guest user review cadence (quarterly review of guest user list; stale guests removed)
* Report subscription and review cadence

## Automation artifacts

* `automation/powershell/22-Inventory-ExternalSharing.ps1` - Captures current sharing state
* `automation/powershell/22-Audit-ExternalSharingActivity.ps1` - Reports 90-day sharing activity
* `automation/powershell/22-Deploy-TenantSharingSettings.ps1` - Configures tenant-level SharePoint
* `automation/powershell/22-Deploy-OneDriveSharingSettings.ps1` - Configures OneDrive
* `automation/powershell/22-Apply-LabelBasedSiteSettings.ps1` - Label-driven site configuration
* `automation/powershell/22-Apply-SiteSharingSettings.ps1` - Manual site configuration from CSV
* `automation/powershell/22-Monitor-SharingActivity.ps1` - Activity reporting
* `automation/powershell/22-Schedule-SharingReports.ps1` - Periodic report subscription
* `automation/powershell/22-Review-GuestUsers.ps1` - Quarterly guest user review
* `automation/powershell/22-Verify-Deployment.ps1` - End-to-end verification
* `automation/powershell/22-Rollback-SharingSettings.ps1` - Reverts to inventory snapshot

## Verification

### Configuration verification

```powershell
./22-Verify-Deployment.ps1
```

Expected output covers tenant-level settings, OneDrive settings, high-sensitivity site settings, and recent activity patterns.

### Functional verification

1. **Anonymous link creation blocked.** As a test user, attempt to share a SharePoint file with "Anyone with the link." Expected: the option is removed from the share dialog, or selecting it produces a permission error.
2. **Guest invitation works.** Invite a test external user through the SharePoint share dialog. Expected: the guest receives an invitation email, accepts, and can access the shared file.
3. **Domain restriction enforced.** Attempt to share with an email address on a non-allowed domain (if allowed list is configured). Expected: share is blocked with appropriate message.
4. **Anonymous link expiration applied.** If any existing anonymous links exist before deployment, verify they have expiration dates set to 30 days or less after deployment.
5. **Site-level settings applied.** Verify a Highly Confidential labeled site has external sharing set to "Only people in your organization."

## Additional controls (add-on variants)

### Additional controls with Defender Suite (Defender for Cloud Apps)

Defender for Cloud Apps (included in Defender Suite) adds session-level monitoring of SharePoint and OneDrive activity. Policies can enforce specific actions in real time: block downloads of sensitive content to unmanaged devices, require step-up authentication for bulk downloads, tag unusual access patterns. This is a session-control capability separate from the SharePoint-native settings in this runbook; they complement each other.

### Additional controls with Purview Suite or M365 E5 (DLP integration)

DLP policies (Runbook 20) interact with external sharing: a DLP policy can block sharing of specific content types regardless of the SharePoint tenant setting. The combination (tight SharePoint settings + DLP content rules) produces layered protection. Without DLP, the SharePoint settings enforce on the "who" of sharing; with DLP, the "what" is also enforced.

### Guest user lifecycle (Entra ID Governance)

Defender Suite includes Entra ID Governance capabilities including access reviews for guest users. For tenants with large guest populations, schedule quarterly access reviews to identify stale guests who no longer need access. Without Governance, the quarterly review in Runbook 18 includes a manual guest review step.

## What to watch after deployment

* **Broken collaboration links during the first 30 days.** Existing anonymous links that are older than the new expiration window expire immediately, breaking legitimate workflows. The communication plan and helpdesk preparation are the difference between managed impact and user backlash.
* **Helpdesk ticket volume.** External sharing changes produce ticket spikes: "how do I share with a client," "why can't I create a sharing link," "the old link expired." Allocate helpdesk capacity for the first 30 days.
* **Guest user growth.** Moving from anonymous links to guest invitations produces guest user accumulation. Without the quarterly review, stale guests accumulate indefinitely.
* **Bulk sharing events.** The Monitor script surfaces these; they can indicate either legitimate project launches or data exfiltration preparation. Investigate patterns.
* **External users uploading content.** External users in SharePoint can upload content, not just read. Uploaded content does not inherit the sharing settings of the original library; a guest who uploads a file has contributed it to the library and it is subject to the library's permissions. Unexpected upload activity warrants investigation.
* **Teams external access alignment.** Teams has its own external access settings, which govern external users in channels and chats. Misaligned Teams external access (loose) and SharePoint external sharing (tight) produces confusing user experiences. Align the two; the interaction is not covered by this runbook but should be verified through the Verify script.

## Rollback

```powershell
./22-Rollback-SharingSettings.ps1 -InventorySnapshot "./external-sharing-inventory-<DATE>.json" -Reason "Documented reason"
```

Full rollback reverts to the pre-deployment sharing state. Rarely appropriate because it reopens the external sharing surface; targeted adjustments are almost always preferable.

Common targeted adjustments:

* **Allow anonymous links for specific sites:** `22-Apply-SiteSharingSettings.ps1` with a CSV specifying the site and desired sharing tier
* **Add a partner domain to the allowed list:** `22-Update-AllowedDomains.ps1` (not separately listed above; invoked through Deploy-TenantSharingSettings with updated parameter)
* **Temporarily loosen during a specific project:** use site-level sharing rather than tenant-level changes

## References

* Microsoft Learn: [Manage sharing settings for SharePoint and OneDrive](https://learn.microsoft.com/en-us/sharepoint/turn-external-sharing-on-or-off)
* Microsoft Learn: [External sharing overview](https://learn.microsoft.com/en-us/sharepoint/external-sharing-overview)
* Microsoft Learn: [Site-level external sharing](https://learn.microsoft.com/en-us/sharepoint/change-external-sharing-site)
* Microsoft Learn: [Guest sharing in OneDrive](https://learn.microsoft.com/en-us/sharepoint/user-external-sharing-status)
* Microsoft Learn: [Restrict sharing to specific domains](https://learn.microsoft.com/en-us/sharepoint/restricted-domains-sharing)
* M365 Hardening Playbook: [SharePoint anonymous link sharing permitted](https://github.com/pslorenz/m365-hardening-playbook/blob/main/data-protection/sharepoint-anonymous-sharing.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: SharePoint external sharing recommendations
* NIST CSF 2.0: PR.AC-03, PR.DS-05, DE.AE-02
