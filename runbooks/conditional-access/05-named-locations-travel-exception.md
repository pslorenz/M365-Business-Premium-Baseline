# 05 - Named Locations and Travel Exception Workflow

**Category:** Conditional Access
**Applies to:** All variants (Plain Business Premium, Defender Suite, E5 Security, EMS E5)
**Prerequisites:**
* [02 - Conditional Access Baseline Policy Stack](./02-ca-baseline-policy-stack.md) completed and enforced
**Time to deploy:** 45 minutes active work, plus recurring review cadence
**Deployment risk:** Low. The baseline's CA006 country-block policy is already in place; this runbook formalizes the maintenance and exception pattern.

## Purpose

Runbook 02 deployed the country-block policy (CA006) with a customizable allowed-country list and a documented travel-exception group. This runbook formalizes the operational pattern around that policy: how the country list is maintained, how travel exceptions are requested and approved, how exception memberships are time-bounded, and how the overall pattern is reviewed. Without a deliberate operational cadence, exception groups drift (covered in the [M365 Hardening Playbook finding on exclusion drift](https://github.com/pslorenz/m365-hardening-playbook/blob/main/conditional-access/mfa-policy-group-exclusion-drift.md)) and the country-block policy gradually becomes permeable.

The tenant before this runbook: CA006 is deployed and enforced. The allowed-country list reflects the organization's operations at the time of CA002 deployment. A travel-exception group exists (`CA-Exclude-Travel-Temporary`) but is empty or holds stale exceptions.

The tenant after: the allowed-country list has an owner and a review cadence. A documented workflow governs travel-exception requests from submission through approval to expiration. Exception group memberships carry implicit expiration through the review cadence; no user remains in the exception group indefinitely. The operations runbook references the workflow so that administrators who inherit the tenant know where the pattern is documented.

This runbook does not change the CA006 policy or the allowed-country list; those were established in Runbook 02. It establishes the ongoing maintenance pattern, which is what converts a deployed control into a durable one.

## Prerequisites

* CA006 (Block sign-ins from unexpected countries) is deployed and enforced
* Named location "Allowed Countries" exists with the organization's operating-footprint country list
* Security group `CA-Exclude-Travel-Temporary` exists (created by Runbook 02 deployment script)
* Operations runbook is accessible for documentation updates
* Leadership approval for the travel-exception approval model (who approves, what justification is required, what the default exception window is)

## Target configuration

At completion:

* **Allowed-countries list** has a documented owner (typically the IT or security lead) and a quarterly review cadence
* **Travel-exception workflow** is documented in the operations runbook with:
    * Request submission path (ticketing system, email distribution, or similar)
    * Approval authority (who approves exceptions; for most SMBs, the IT lead or a delegate)
    * Default exception window (7 days, 14 days, or 30 days; most organizations use 14 days)
    * Maximum exception window without re-approval (typically 30 days)
    * Removal automation that triggers on the end date
* **Exception group membership** is never indefinite; every addition has a scheduled removal date tracked in the operations runbook or a ticket
* **Quarterly audit** of the exception group confirms no stale memberships
* **Annual audit** of the allowed-country list confirms it still matches operations

## Deployment procedure

### Step 1: Document the allowed-countries list and its owner

Review the current country list:

```powershell
./05-Review-AllowedCountries.ps1
```

The script reads the named location from Graph and displays the current country list along with counts of sign-in activity from each allowed country over the last 90 days.

For each country in the list, validate that the organization still has operations there. Remove any country that no longer applies. Confirm the list is complete against current operations (new offices, new remote employees, new partner relationships that involve travel).

Update the named location if changes are needed:

```powershell
./05-Update-AllowedCountries.ps1 `
    -Countries @("US", "CA", "GB", "MX")
```

Document in the operations runbook:

* Current allowed-country list with justification per country (operations, offices, remote employees)
* Owner responsible for maintaining the list
* Quarterly review cadence with review date recorded

### Step 2: Define the travel-exception workflow

Document the exception workflow in the operations runbook. The template:

```
Travel Exception Workflow
=========================

Purpose: Temporary exemption from CA006 country-block policy for approved business travel.

Request format:
  Submit via: [ticketing system / email distribution / Teams channel]
  Required information:
    - User's UPN
    - Destination country/countries
    - Travel start date
    - Travel end date (return date plus 2 days buffer)
    - Business justification
    - Approver name (must be submitter's manager or IT lead)

Approval:
  Approver: [IT lead / security lead / designated delegate]
  Approval SLA: 1 business day
  Approval criteria:
    - Documented business purpose for travel
    - Travel destination is not in a country with known active threats
    - Exception window aligns with actual travel dates

Exception implementation:
  Implemented by: [IT admin]
  Script: 05-Add-TravelException.ps1
  Maximum window: 30 days without re-approval

Exception expiration:
  Automatic removal via scheduled task or manual review
  Script: 05-Review-TravelExceptions.ps1 (run weekly)

Review cadence:
  Weekly: review exception group membership against active travel
  Monthly: review any exceptions that have been in place beyond their scheduled end
```

Customize the template to fit the organization's existing change-management processes.

### Step 3: Implement the exception management scripts

Two scripts support the workflow:

**Adding a travel exception:**

```powershell
./05-Add-TravelException.ps1 `
    -UserUPN "jane.user@contoso.com" `
    -Countries @("FR", "DE") `
    -StartDate "2026-05-01" `
    -EndDate "2026-05-15" `
    -TicketReference "TRAVEL-1234" `
    -Justification "Business travel to Paris and Berlin for client meetings"
```

The script:
1. Validates the user exists and is not a break glass account
2. Validates the start date is not in the past
3. Adds the user to the `CA-Exclude-Travel-Temporary` group with a description carrying the end date and ticket reference
4. Records the exception in a persistent log file (JSON append)
5. Returns the expected end date and the follow-up action

**Reviewing and expiring travel exceptions:**

```powershell
./05-Review-TravelExceptions.ps1
```

The script reads the exception log and the current exception group membership. For each member:
* Reports the ticket reference and scheduled end date
* Flags entries past their end date as due for removal
* Offers to remove expired entries in the same run with confirmation

Scheduled execution: run weekly, either manually or through an MSP automation platform. The operations runbook documents the schedule.

### Step 4: Configure automated expiration reminders

For tenants with Sentinel or an equivalent monitoring system, configure an alert on exception group membership changes:

```kql
AuditLogs
| where TimeGenerated > ago(7d)
| where OperationName in ("Add member to group", "Remove member from group")
| extend GroupName = tostring(TargetResources[1].displayName)
| where GroupName == "CA-Exclude-Travel-Temporary"
| extend Initiator = tostring(InitiatedBy.user.userPrincipalName)
| extend MemberUPN = tostring(TargetResources[0].userPrincipalName)
| project TimeGenerated, Initiator, OperationName, GroupName, MemberUPN
```

The query fires on any change to the exception group. Route to the same destination as the other PIM and CA-change alerts from the audit runbook (to be configured in a later runbook).

For tenants without Sentinel, a weekly report from the Review script (Step 3) substitutes.

### Step 5: Document the quarterly and annual review cadences

Update the operations runbook with:

* **Quarterly review:** confirm the allowed-countries list still matches operations, audit exception group membership for stale entries, confirm the review log is up to date
* **Annual review:** deeper review including review of the approval workflow effectiveness, any exceptions that went past the 30-day maximum, any patterns of recurring exceptions that suggest the country list should change permanently

### Step 6: Test the end-to-end workflow

Test exception request, approval, implementation, and removal:

1. A test user submits a travel exception request through the documented channel
2. The approver approves the exception
3. The admin runs `05-Add-TravelException.ps1` with the test user and test dates
4. Test user confirms (via VPN simulation or actual travel context) that sign-ins from the destination country now succeed
5. End date arrives, `05-Review-TravelExceptions.ps1` flags the entry, the admin confirms removal
6. Test user confirms that post-expiration sign-ins from the destination country are blocked again

Document the test in the operations runbook with date and outcome.

## Automation artifacts

* `automation/powershell/05-Review-AllowedCountries.ps1` - Displays current allowed-countries list with sign-in activity context
* `automation/powershell/05-Update-AllowedCountries.ps1` - Updates the allowed-countries named location
* `automation/powershell/05-Add-TravelException.ps1` - Adds a user to the travel exception group with logged end date
* `automation/powershell/05-Review-TravelExceptions.ps1` - Reports and expires stale exceptions
* `automation/powershell/05-Verify-Deployment.ps1` - Confirms the runbook's target configuration

## Verification

### Configuration verification

```powershell
./05-Verify-Deployment.ps1
```

Expected output:

```
Allowed Countries named location:
  Exists: Yes
  Country count: 4
  Countries: US, CA, GB, MX
  Owner documented in ops runbook: [check operations runbook]

Travel exception group:
  Exists: CA-Exclude-Travel-Temporary
  Current members: [N]
  Stale members (past end date): [N]

Workflow documentation:
  Operations runbook references workflow: [manual check required]

Scripts present:
  05-Add-TravelException.ps1: Yes
  05-Review-TravelExceptions.ps1: Yes
```

### Functional verification

1. **Current list matches operations.** Each country in the allowed list has a documented reason for being there.
2. **No stale exceptions.** Every member of the exception group has a current ticket reference and a scheduled end date within the maximum window.
3. **Workflow documentation exists.** The operations runbook contains the travel-exception workflow, the approvers, and the review cadences.
4. **End-to-end test passed within the last 12 months.** If not, re-run the test from Step 6.

## Additional controls (add-on variants)

No add-on-specific content for this runbook. The country-block pattern is identical across all variants because the underlying Conditional Access feature (country-based named locations) is available at P1 and P2.

## What to watch after deployment

* **Exception volume.** Track the number of active exceptions over time. High volume (more than 10% of users in the exception group at any given time) suggests the country list is too narrow and should be reviewed for permanent expansion.
* **Repeat exceptions for the same user.** An employee who needs the exception every month for the same country has a pattern the allowed-country list should probably accommodate permanently.
* **After-hours exception requests.** Urgent requests outside the approval SLA indicate gaps in the approval workflow. Either the SLA is too slow or users are not requesting exceptions in advance.
* **Exceptions not removed on time.** Entries past their end date indicate the weekly review is not happening reliably. Reinforce the cadence or move the review to automation.
* **Change in adversary targeting.** If threat intelligence identifies new regions of concern (after-incident industry advisories, CISA alerts on specific adversary infrastructure shifts), review whether the allowed-country list or specific travel exceptions should be re-evaluated.

## Rollback

Rolling back this runbook is not meaningful; the underlying CA006 policy was deployed by Runbook 02 and the exception workflow is operational process, not configuration. Disabling the workflow itself would leave the CA006 policy in place with no documented exception path, which creates operational friction without any posture improvement.

If the workflow itself produces too much overhead (very rare for properly-scoped operations), options are:

* Expand the allowed-country list to reduce exception volume
* Delegate exception approval to more approvers to reduce SLA friction
* For highly mobile organizations, consider whether country-based filtering is the right control and whether sign-in risk policy (Runbook 02's CA010 for P2 tenants) provides adequate coverage on its own

## References

* Microsoft Learn: [Using the location condition in a Conditional Access policy](https://learn.microsoft.com/en-us/entra/identity/conditional-access/location-condition)
* Microsoft Learn: [Define named locations in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-assignment-network)
* M365 Hardening Playbook: [No named-location policy blocking sign-ins from unexpected countries](https://github.com/pslorenz/m365-hardening-playbook/blob/main/conditional-access/no-country-block-policy.md)
* M365 Hardening Playbook: [MFA policy has a group exclusion that has grown beyond its original purpose](https://github.com/pslorenz/m365-hardening-playbook/blob/main/conditional-access/mfa-policy-group-exclusion-drift.md)
* CIS Microsoft 365 Foundations Benchmark v4.0: Conditional Access geographic restrictions
* NIST CSF 2.0: PR.AA-05, PR.AC-03
