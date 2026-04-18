# Cost Model

Purpose:
- project likely upfront and ongoing costs for an enclave-centered compliance program
- help leadership understand that the cost is not only software or hardware
- identify staffing, services, contracts, assessment, and operational overhead

This is a qualitative cost model for an AMS-style manufacturer. It is not a pricing quote.

## Cost Categories

The major cost buckets are usually:
- internal staff time
- consulting and design services
- security tooling and platform changes
- infrastructure and segmentation work
- managed service or provider contract changes
- assessment and compliance program costs
- training, process, and evidence overhead

## 1. Upfront Internal Staff Costs

Likely one-time or project-heavy labor:
- CTO / IT leadership time for scoping and decisions
- architect time for enclave design
- systems / network engineer time for segmentation and identity changes
- endpoint engineering time for enclave device standards
- engineering systems owner time for CAD/PDM and release workflow changes
- ERP owner time for data classification and module scoping
- manufacturing / OT owner time for CNC/CMM/test mapping and vendor access redesign
- security/compliance time for SSP, policies, readiness, and evidence

Typical burden:
- moderate to high
- often underestimated because it is spread across multiple teams

## 2. Upfront External Services Costs

Likely project-phase professional services:
- enclave architecture/design consulting
- CMMC / NIST readiness assessment
- policy / SSP development support
- firewall / segmentation implementation support
- identity / MFA / conditional access design assistance
- OT security review or manufacturing network consulting
- ERP or CAD integration consulting if segregation is difficult

Typical burden:
- moderate to high
- highly dependent on internal capability and existing maturity

## 3. Tooling and Platform Costs

Possible new or expanded tools:
- MFA or conditional access licensing upgrades
- MDM / endpoint management licensing for enclave devices
- EDR / XDR / MDR licensing expansion
- SIEM or log-ingestion growth
- backup platform or immutable backup features
- vulnerability management / scanning coverage expansion
- privileged access or jump host tooling
- secure file transfer / controlled collaboration tooling
- DLP / retention / eDiscovery features if M365 is central to the enclave

Typical burden:
- low to high depending on current stack
- if the company already has Microsoft 365, EDR, and MDM, marginal costs may be moderate
- if tooling is basic today, costs can rise quickly

## 4. Infrastructure and Network Costs

Potential infrastructure work:
- firewall upgrades or additional interfaces/zones
- switch / VLAN redesign
- dedicated enclave servers or virtual infrastructure
- jump hosts / management network
- separate storage or repositories for controlled data
- manufacturing staging systems
- remote access redesign
- backup storage growth

Typical burden:
- moderate
- higher if the current network is flat or the OT environment is fragile

## 5. Device and Endpoint Costs

Likely endpoint-related expenses:
- dedicated enclave laptops/workstations for engineering or program staff
- admin workstations
- replacement of unsupported or weakly managed systems
- encryption, EDR, MDM, and compliance tooling on enclave devices

Typical burden:
- moderate
- higher if engineering currently uses mixed-purpose endpoints

## 6. Manufacturing / OT-Specific Costs

Common project drivers:
- discovery and inventory of specialized assets
- network segmentation around CNC/CMM/test systems
- vendor remote support controls
- compensating controls for legacy or unsupported systems
- maintenance-window coordination and exception management
- data transfer redesign between engineering and shop floor

Typical burden:
- moderate to high
- often one of the hardest areas because uptime and legacy dependencies constrain design choices

## 7. Provider and Contract Costs

Likely contract impacts:
- MSP contract changes for enclave-aware administration
- MSSP scope expansion for enclave monitoring
- cloud licensing and support increases
- machine-vendor support contract updates for MFA, logging, approval workflows, or session brokering
- readiness-assessment support contracts
- eventual C3PAO / assessment-related fees if formal assessment applies

Typical burden:
- moderate
- often missed early because existing provider contracts are rarely scoped with enclave boundaries in mind

## 8. Compliance and Assessment Costs

Likely direct compliance expenses:
- readiness review or gap assessment
- POA&M remediation management
- internal audit / mock assessment work
- formal assessment fees where required
- annual maintenance effort for evidence, reviews, and affirmations
- legal or contract review support when obligations are unclear

Typical burden:
- moderate
- ongoing even after the initial project

## 9. Ongoing Staffing Costs

Ongoing operational burden may require:
- internal security lead or vCISO support
- security operations coverage
- identity and access governance time
- evidence maintenance and compliance coordination
- vendor-access oversight
- periodic access reviews and exception management
- patching and vulnerability remediation for enclave and specialized assets

Possible models:
- absorb into existing IT/security staff
- expand MSP/MSSP contracts
- add part-time compliance/program management
- add dedicated security/compliance role if the business expects long-term controlled work

## 10. Ongoing Service and Subscription Costs

Likely recurring costs:
- identity and MFA licensing
- MDM / endpoint management
- EDR / MDR
- SIEM or logging retention
- backup storage and recovery services
- vulnerability scanning subscriptions
- secure collaboration / transfer services
- remote access platform
- consulting retainer or vCISO support

## 11. Hidden Costs Leadership Should Expect

These are frequently overlooked:
- user friction and productivity loss during transition
- engineering workflow redesign
- ERP workflow cleanup
- machine-vendor coordination delays
- evidence collection time
- documentation maintenance
- executive decision overhead when scope questions remain unresolved
- exception handling for legacy systems

## 12. Cost Pressure Points

The biggest cost drivers are usually:
- how much of ERP is pulled into scope
- whether identity can stay shared or needs stronger separation
- how many dedicated enclave endpoints are needed
- whether current Microsoft 365 / endpoint / security licensing is already sufficient
- how difficult OT/vendor access control becomes
- whether the company needs outside help to build the SSP and evidence package
- whether a formal third-party assessment is required

## 13. Likely Cost Profile by Phase

### Early phase

Primary costs:
- architect / leadership time
- discovery effort
- readiness consulting
- documentation and policy work

### Build phase

Primary costs:
- segmentation and identity changes
- endpoint rollout
- security tool expansion
- OT/vendor access redesign

### Operational phase

Primary costs:
- recurring licenses
- MSP/MSSP monitoring
- compliance coordination
- periodic reviews and evidence maintenance

## 14. Practical Staffing Forecast

For a small-to-mid-size manufacturer, a likely minimum operating model is:
- executive sponsor: part-time
- solution/security architect: project-heavy, then part-time
- systems/network engineer: project-heavy, then moderate ongoing
- security/compliance coordinator or vCISO: moderate ongoing
- engineering systems owner: periodic
- manufacturing/OT owner: periodic
- MSP/MSSP support: ongoing if used

If the company has little in-house security/compliance maturity, expect the need for:
- outside readiness support
- outside SSP/policy assistance
- possibly ongoing vCISO/compliance help

## 15. Recommendation

Leadership should budget for this as:
- a multi-function business/security/engineering project
- not just a software purchase
- not just a one-time consulting engagement

The safest planning assumption is:
- moderate upfront internal labor
- moderate-to-high upfront services and implementation cost
- moderate recurring platform and compliance cost

The final cost picture should be recalculated after discovery answers identify:
- true enclave size
- number of enclave users/devices
- ERP scope
- OT complexity
- provider contract changes
