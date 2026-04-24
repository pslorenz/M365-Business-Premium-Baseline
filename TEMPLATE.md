# [Runbook Number] - [Runbook Name]

**Category:** [Identity and Access / Conditional Access / Device Compliance / Defender for Office / Audit and Alerting / Operations]
**Applies to:** [Plain Business Premium / Defender Suite / E5 Security / EMS E5 - list the variants where this runbook applies]
**Prerequisites:** [List the runbooks that must be completed before this one]
**Time to deploy:** [Realistic estimate including observation windows]
**Deployment risk:** [Low / Medium / High]

## Purpose

One paragraph. What this runbook configures and why. What the tenant looks like before the runbook runs and what it looks like after. No diagnostic framing; this is target state, not triage.

## Prerequisites

What must be in place before this runbook can run. Other runbooks that must be completed, licensing that must be active, access that the deploying technician must have. For an MSP deployment, name the specific GDAP role required (usually Global Administrator for the initial tenant runbooks, narrower roles for subsequent runbooks).

## Target configuration

The specific configuration this runbook deploys. Not "configure MFA" but "deploy the following four Conditional Access policies with these exact settings." Prose description first, followed by the specific settings as a table or a configuration block.

For controls that have modular variation (specific to the organization's users, travel, or device fleet), call out the modular element explicitly: "The allowed countries list in the named-location policy is organization-specific; the default provided assumes US-only operations. Update before deployment."

## Deployment procedure

Ordered steps. Each step is:

1. The action in plain language
2. The automation artifact command or the portal path
3. The verification that the step completed correctly

Steps should be small enough that a failure at step N leaves the tenant in a recoverable state. Large irreversible actions (disabling Security Defaults, removing permanent admin role assignments) are flagged with explicit warnings.

## Automation artifacts

List the automation artifacts that deploy this runbook's configuration:

* `automation/powershell/[script-name].ps1` - brief description
* `automation/ca-policies/[policy-name].json` - brief description
* (Additional artifacts as needed)

For each artifact, include the command to run it and the expected output.

## Verification

How to confirm the runbook's target configuration is actually deployed. This is the baseline's equivalent of the playbook's "Validate the fix" section, but scoped to the specific configuration this runbook deploys rather than to the full posture.

Verification has two components:

* **Configuration verification.** The settings the runbook deploys are present in the tenant.
* **Functional verification.** The settings produce the expected behavior (a user sign-in goes through MFA, a legacy auth attempt is blocked, etc.).

## Additional controls (add-on variants)

Content in this section applies only to tenants with the specific add-on named in the heading. Readers on plain Business Premium can skip.

### Additional controls with Defender Suite, E5 Security, or EMS E5 (Entra ID P2 content)

[P2-specific content. PIM role settings, Identity Protection policy enforcement, authentication context, etc.]

### Additional controls with Defender Suite or E5 Security (Defender for Office 365 Plan 2 content)

[DfO P2-specific content. Safe Attachments dynamic delivery, Safe Links time-of-click for Teams, Attack Simulation Training, etc.]

### Additional controls with Defender Suite or E5 Security (Defender for Endpoint Plan 2 content)

[DfE P2-specific content. Attack surface reduction rules, advanced EDR, automated investigation and response, etc.]

Note that not every runbook has content in every add-on section. Runbooks that are entirely covered by the universal content simply do not include add-on sections.

## What to watch after deployment

Observations to make over the first 7 to 30 days after deployment. User experience issues that typically surface, log patterns to watch for, thresholds to tune. This is not ongoing operations (covered in the operations runbooks) but immediate post-deployment monitoring.

## Rollback

How to reverse the configuration this runbook deploys, if rollback is ever necessary. Identify which changes are immediately reversible, which require additional steps, and which are effectively permanent. For the baseline, rollback is almost always the wrong answer; the correct response to a deployment problem is usually to tune the specific control rather than reverting the runbook.

## References

* Microsoft Learn: [relevant documentation]
* M365 Hardening Playbook: [corresponding diagnostic finding, if applicable]
* CIS Microsoft 365 Foundations Benchmark: [section reference]
* NIST CSF 2.0: [function.category.subcategory]
