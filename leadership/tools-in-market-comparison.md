# Tools in the Market: Honest Comparison

MSP leadership evaluating how to deploy and maintain a Microsoft 365 security posture encounters several categories of commercial tool that claim to solve the problem. This document is an honest assessment of those tools in relation to the baseline this repository provides.

The goal is not to dismiss commercial tools; several of them are genuinely useful. The goal is to distinguish what each tool actually does from what its marketing implies, and to help leadership decide which tools make sense alongside the baseline and which are positioned as replacements for thinking.

## The tool categories

Four distinct categories of tool show up in MSP conversations about M365 security, and they do different things:

1. **Multi-tenant management platforms.** Tools that provide a single pane of glass across many customer tenants. Examples: CIPP (community-maintained, open source), Augmentt, Rewst (automation-oriented), Nerdio (primarily Azure-focused but has M365 capabilities).
2. **Baseline and compliance enforcement tools.** Tools that deploy an opinionated security configuration and continuously enforce drift. Examples: Inforcer, Senserva, Octiga, some features within Augmentt.
3. **MDR and SOC-as-a-service.** Tools that add 24/7 monitoring and response capability on top of whatever M365 is producing as signal. Examples: Huntress M365, Blumira, SentinelOne Vigilance, eSentire.
4. **Secure score improvement tools.** Tools that target Microsoft Secure Score specifically and automate remediation of its findings. Examples: Coreview, Veritas Alta Vision, various CIPP extensions.

Categories overlap in practice. Several tools span two or three of the above categories; the distinctions matter less than understanding what job each tool is actually doing in your environment.

## Category 1: multi-tenant management platforms

**What they do well.** Cross-tenant visibility, bulk operations, automation of repetitive configuration tasks, role-based access control for MSP staff, and audit logging of MSP actions across the fleet. An MSP managing 20 customer tenants without a multi-tenant tool is signing in to 20 separate portals daily; with one of these tools, common tasks are doable from a single interface.

**What they do less well.** Most of these tools deploy configuration based on their vendor's opinion of what good looks like. That opinion is often weaker than what a thoughtful baseline would deploy, and the vendor rarely explains the reasoning behind their defaults. Some tools ship with default Conditional Access templates that are explicitly less restrictive than Microsoft's own secure foundation templates, on the theory that less restrictive is less likely to generate support tickets. That tradeoff is the vendor's, not yours.

**How they relate to the baseline.** Complementary when used correctly. The baseline specifies the target configuration; a multi-tenant tool can deploy that configuration across a fleet more efficiently than manual deployment. The value of the multi-tenant tool is the operational leverage, not the opinion about what to deploy.

**Recommendation.** If you are managing 10 or more customer tenants, a multi-tenant management platform is operationally worthwhile. Use the baseline as the specification for what the tool should be enforcing, rather than accepting the tool's defaults. CIPP is the default recommendation for cost reasons (open source, community maintained); commercial alternatives justify their pricing through vendor support, integrations, and SLA commitments.

## Category 2: baseline and compliance enforcement tools

**What they do well.** Continuous drift detection, remediation workflows, reporting that maps to specific compliance frameworks (CIS, CMMC, HIPAA), and audit trails that support compliance attestation work. For MSPs selling security-compliance-as-a-service to regulated customers, these tools produce the artifacts the compliance engagement requires.

**What they do less well.** The baselines they enforce vary substantially in quality. Some ship with reasonably strong defaults; others ship with the Microsoft Security Defaults configuration plus a handful of additional controls and call it a baseline. The vendor's baseline is often not documented in a form that lets the MSP technician verify what is being enforced before deploying, which produces the pattern of "we bought tool and it said we're compliant, so we're compliant" without anyone actually knowing what was configured.

The deeper problem is the positioning. Some of these tools are sold as replacements for understanding the underlying controls. An MSP that buys an enforcement tool to avoid having to think about the baseline is buying a worse outcome than an MSP that thinks about the baseline and uses the tool to operationalize it.

**How they relate to the baseline.** The baseline this repository provides is a specification of target state; the enforcement tools in this category claim to be both specification and enforcement. In a tenant where the tool's baseline matches the specification you want, the tool is useful. In a tenant where the tool's baseline does not match the specification you want, the tool is applying the wrong configuration and producing false confidence.

**Recommendation.** Before buying an enforcement tool, verify what it actually enforces. Ask the vendor for the exact configuration templates. Compare against the baseline in this repository. If the tool's configuration is materially weaker, either negotiate customization (some tools support this, many do not), use the tool only for its drift-detection capability while deploying your own configuration, or choose a different tool. An MSP that deploys a tool without reading what it deploys is outsourcing a configuration decision to a vendor whose defaults are tuned for low support ticket volume, not for strong security posture.

## Category 3: MDR and SOC-as-a-service

**What they do well.** Add 24/7 monitoring, alert triage, and incident response capability that most SMBs cannot staff internally. Produce actual human eyes on the logs the baseline is generating. For SMBs without the capacity to run their own SOC, these services fill a gap that no amount of configuration closes.

**What they do less well.** The MDR provider's visibility is only as good as the signals flowing to them. If the tenant's audit logging is misconfigured, the MDR provider cannot see what they cannot see. Several MDR providers have historically oversold their M365 capabilities; they monitor a subset of M365 signals and treat the rest as out of scope, which customers do not always understand.

The commercial MDR market has also consolidated around a few delivery models: full-fleet monitoring with standardized alert rules, or custom tuning for each customer tenant. Standardized is cheaper and less effective; custom is more expensive and more effective. Pricing often does not clearly distinguish the two.

**How they relate to the baseline.** Deeply complementary. The baseline produces signal (configured audit logging, alert rules on high-value events); the MDR provider consumes the signal and responds to it. An MSP with the baseline deployed and no MDR relationship is generating alerts that may not be watched; an MSP with MDR and no baseline is paying for a service that has nothing useful to watch.

**Recommendation.** For SMB customers without 24/7 internal monitoring, an MDR relationship is worth the cost. Huntress is the common recommendation for budget-constrained SMBs; Blumira targets a similar market with a slightly different delivery model. Expel and eSentire target larger customers with more sophisticated threat models. The choice between them is primarily about cost and the specific industry focus.

Before buying MDR, confirm:

* What M365 signals the provider actually monitors
* Whether the provider ingests from Sentinel, Defender XDR, or their own collection
* Whether custom alert rules can be added to their monitoring
* What the SLA is for alert acknowledgment and what escalation looks like
* Whether incident response is included or is an additional engagement

## Category 4: secure score improvement tools

**What they do well.** Automate the specific recommended actions that Microsoft Secure Score identifies as missing. Produce a dashboard that shows score improvement over time. Satisfy customer demand for a visible security metric.

**What they do less well.** Secure Score is a proxy metric, not a security outcome. It was also designed as a sales tool. A tenant with a high Secure Score can still be trivially compromised if the specific controls that Secure Score weights are not the controls that actually matter for the attack paths hitting the tenant. Tools that optimize for Secure Score optimize for the metric, not the posture.

**How they relate to the baseline.** Weakly related. A tenant deployed according to this baseline will have a reasonable Secure Score, because the baseline covers the controls Secure Score cares about. The reverse is not true: a tenant optimized for Secure Score may not have the baseline's posture, because Secure Score does not weight every baseline control and weights some controls that the baseline considers lower priority.

**Recommendation.** Secure Score is a useful dashboard for customer conversations and a weak tool for actual security work. Do not buy a tool whose primary value proposition is Secure Score improvement. Deploy the baseline, allow Secure Score to follow, and use the score as a communication artifact for customer reporting rather than as a target.

## The composite picture

An MSP with a mature M365 security practice typically has:

* **A baseline** (this repository, a competitor's published baseline, or an internal baseline the MSP has developed) as the specification of target state
* **A multi-tenant management tool** (CIPP commonly, or a commercial alternative) to operationalize deployment and monitoring across the fleet
* **An MDR relationship** (Huntress, Blumira, or similar) to provide the 24/7 monitoring and response that SMB customers cannot staff themselves
* **Internal expertise** sufficient to customize, tune, and operate the above rather than accepting vendor defaults

The baseline this repository provides covers the first element specifically. The other three are business decisions for the MSP that this repository does not make for you. The honest framing is that tools help only when paired with expertise; any tool positioned as a replacement for expertise is being misrepresented and often dangerous.

## Questions to ask vendors

If a vendor is pitching a tool that overlaps with the baseline's scope, questions worth asking:

1. **What exactly does your tool enforce?** Ask for the configuration templates. If the vendor cannot or will not share them, the tool is opaque and you cannot verify what it is doing.
2. **How is your baseline maintained?** Microsoft changes defaults, introduces new controls, and deprecates old ones continuously. A baseline updated annually is a baseline six months out of date for half the year.
3. **What is your position on controls where you disagree with Microsoft's recommendations?** Vendors with strong opinions about where Microsoft is wrong are often right; vendors who claim to agree with Microsoft on everything are either not paying attention or are marketing.
4. **Can I customize the baseline you deploy?** If yes, great. If no, you are committed to the vendor's opinion.
5. **What is the support model when something breaks?** Automated deployment tools occasionally misconfigure tenants; the support response time and escalation path matter.
6. **How do you handle tenants with existing configuration?** A tool that assumes a clean tenant is not useful for remediating an existing deployment.

Answers to these questions separate vendors worth evaluating from vendors positioned as "set it and forget it" for work that cannot be set and forgotten.

## What this repository competes with and what it does not

This repository explicitly competes with:

* Outdated or underwhelming internal baselines at MSPs that do not invest in security-specific expertise
* Vendor-default configurations in baseline enforcement tools, when those defaults are weaker than an articulated baseline would be
* The Microsoft Security Defaults baseline for tenants that actually have Business Premium licensing

This repository does not compete with:

* Multi-tenant management tools (complementary; use both)
* MDR providers (complementary; they monitor the signals the baseline produces)
* CIS benchmarks (complementary; CIS is reference material, this baseline is deployment guidance)
* Compliance attestation tools (different purpose)
* Mature internal baselines at experienced MSPs (those are probably fine; this baseline is not positioned as better than a deeply-tuned MSP baseline, only better than the average SMB baseline)

The honest positioning: this baseline is the output of deliberate thought about what correctly-configured Business Premium looks like, made available publicly so that SMB security posture can improve industry-wide. It is not a product; it is a reference. Use it as such.
