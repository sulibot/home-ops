# Evidence Checklist

Source context:
- Handbook source: [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- Extracted text source: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- Supporting artifacts:
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/ams-target-architecture.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/ams-target-architecture.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/shared-responsibility-matrix.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/shared-responsibility-matrix.md)

This checklist is a first-pass evidence package for an enclave-centered Level 2 readiness effort.

It is designed to answer:
- what artifacts should already exist
- what artifacts should be created as part of the architecture project
- what operational proof points will likely be needed

## How to Use This

- Start with the `foundational evidence` section.
- Treat `technical evidence` as proof that the enclave is real, not just planned.
- Treat `operational evidence` as proof the company actually runs the environment the way the diagrams and policies claim.
- Replace generic descriptions with real system names as the environment is discovered.

## Foundational Evidence

These artifacts should exist early and stay current:

| Artifact | Why it matters | Typical owner | Minimum content |
| --- | --- | --- | --- |
| System Security Plan (`SSP`) | Central evidence artifact for scope, controls, responsibilities, and system description | Security / architect lead | system description, boundary definition, information flows, control implementation summary, inherited/shared controls |
| Asset inventory | Needed to show what is in and around scope | Internal IT with Security and business owners | system name, owner, role, location, category, boundary status |
| Network diagrams | Proves boundary design and permitted connections | Network / architect lead | zones, firewalls, trust boundaries, admin paths, cloud services, data flow between corporate, enclave, and OT |
| Data flow diagrams | Proves the scope follows the information | Architect lead with business owners | data sources, repositories, transfer paths, external exchanges, manufacturing handoff |
| Shared responsibility matrix | Needed when using cloud, MSP, MSSP, vendor, or shared enterprise services | Security / architect lead | service, owner, supporting parties, boundary relevance, inherited controls, evidence sources |
| Policies and standards | Shows the environment is governed, not improvised | Security | access control, MFA, remote access, incident response, change management, media handling, vendor access |
| Procedures / runbooks | Shows how policy is actually operationalized | IT / Security / Manufacturing | onboarding, access requests, privileged admin use, vendor support, backup/restore, incident handling |
| Organizational chart / role map | Supports separation of duties and evidence interviews | HR / leadership / Security | IT roles, security roles, business owners, admins, external providers |

## Boundary and Scoping Evidence

These artifacts defend the enclave itself:

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Certification boundary statement | Defines what the certificate should apply to | enclave scope narrative, included asset classes, exclusions |
| Assessment boundary statement | Explains connected/supporting/specialized systems | enclave plus shared services plus OT specialized assets |
| Asset categorization records | Shows how systems were classified | `CUI asset`, `security protection asset`, `specialized asset`, `contractor risk managed asset` |
| Boundary justification | Shows why some systems are out of scope | segmentation rationale, no-CUI rationale, isolation controls |
| Supporting organization and ESP list | Documents cloud/MSP/vendor dependencies | Microsoft 365, MSP, MSSP, OEM remote support, CSPs |
| Scope decision log | Preserves reasoning and assumptions | why ERP module X is in scope, why payroll is out of scope |

## Identity and Access Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| MFA policy and enforcement settings | Demonstrates required access control strength | MFA configuration screenshots, conditional access policies, SSO controls |
| Privileged account inventory | Shows who can administer enclave systems | named accounts, roles, break-glass accounts, service accounts |
| Access review records | Demonstrates periodic validation of access | manager reviews, quarterly attestations, group membership review |
| User/device compliance rules | Ties enclave access to managed devices | device compliance policies, enrollment records |
| Admin workstation / jump host records | Proves admin separation | device inventory, hardening baseline, assigned admins, logs |
| Remote access logs | Proves monitored and controlled remote access | VPN/ZTNA session logs, source device records, approvals |

## Endpoint, Server, and Application Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Endpoint baseline standard | Shows enclave endpoints are hardened intentionally | CIS-style baseline, GPOs, Intune policies, local admin restrictions |
| Encryption configuration | Demonstrates device and data protection | BitLocker/FileVault, removable media restrictions, key management |
| Patch and vulnerability records | Shows maintenance discipline | scan reports, patch cadence, exceptions, remediation tickets |
| EDR deployment and policy records | Shows endpoint monitoring and protection | coverage report, policy assignment, alert history |
| Application owner and admin records | Clarifies accountability for CAD/PDM/ERP systems | named owners, admin assignments, platform diagrams |
| System configuration snapshots | Useful for proving key settings at assessment time | firewall rules, tenant settings, application security configuration |

## Logging and Monitoring Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Log source inventory | Demonstrates monitoring coverage | domain controllers, firewalls, VPN, CAD repositories, servers, admin endpoints |
| SIEM/MDR scope statement | Shows enclave events are actually monitored | log routing diagrams, onboarding list, retention settings |
| Alert handling procedures | Demonstrates that monitoring leads to action | triage runbook, escalation matrix |
| Sample alerts and tickets | Operational proof of use | incident tickets, investigation records, follow-up actions |
| Audit log retention evidence | Supports accountability and forensic traceability | retention policies, archive configuration |

## Backup and Recovery Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Backup scope and schedule | Shows enclave data is protected | backup job definitions, protected systems list |
| Backup access control | Proves backup admins and restore rights are controlled | role assignments, approval workflow |
| Restore test records | Demonstrates recoverability | restore test reports, screenshots, validation notes |
| Offsite / immutable backup controls | Strengthens resilience posture | provider settings, immutability policies, vaulting evidence |

## ERP, CAD, and Controlled Data Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Authoritative repository definition | Shows where controlled engineering data officially lives | PDM repository map, SharePoint site list, file server mapping |
| Release workflow documentation | Proves controlled movement from engineering to manufacturing | approval workflow, revision release process, staging procedure |
| ERP data classification notes | Decides whether ERP modules or records are in scope | attachment review, module boundary notes, integration diagrams |
| External sharing controls | Proves controlled collaboration with customers/suppliers | sharing settings, secure transfer workflow, access records |

## Manufacturing and Specialized Asset Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Specialized asset inventory | Required for OT / CNC / test systems in the assessment conversation | machine name, controller, workstation, owner, connectivity |
| Manufacturing network diagram | Shows OT segmentation and access paths | enclave-to-OT firewall, staging server, vendor access path |
| Vendor maintenance procedure | Addresses remote maintenance risk | approval workflow, MFA requirement, supervised session procedure |
| Diagnostic media controls | Supports maintenance and malware prevention | media scanning procedure, approved tools list |
| Test / inspection data handling flow | Clarifies whether results become part of controlled records | export path, storage location, ownership |

## Incident Response and Operations Evidence

| Artifact / proof | Why it matters | Typical examples |
| --- | --- | --- |
| Incident response plan | Handbook and Level 2 logic expect a real handling capability | preparation, detection, analysis, containment, recovery, reporting |
| Incident tickets and after-action records | Shows the plan is used operationally | ticket examples, timelines, lessons learned |
| Change management records | Supports configuration and boundary integrity | firewall changes, admin changes, system onboarding records |
| Security awareness / role-based training records | Supports operational maturity | training completions, enclave admin training |
| Risk register / exceptions list | Shows known gaps are managed intentionally | risk entries, compensating controls, exception approvals |

## Evidence by Project Phase

### Phase 1: Scope and discovery

- asset inventory draft
- initial network diagrams
- initial data flows
- enclave user/system list
- provider and MSP inventory

### Phase 2: Enclave build

- endpoint baseline
- MFA and identity configs
- firewall and segmentation rules
- admin path design
- logging and EDR onboarding evidence

### Phase 3: Manufacturing integration

- specialized asset inventory
- transfer workflow documentation
- vendor access controls
- OT segmentation evidence

### Phase 4: Readiness

- finalized SSP
- finalized responsibility matrix
- policy/procedure set
- sample logs, tickets, approvals, restore tests, access reviews

## CTO Recommendation

Do not wait until the end to “collect evidence.” The diagrams, ownership decisions, admin model, access reviews, remote support controls, and release workflows should be created as evidence-producing processes from the start. For an enclave effort, the strongest proof is when the architecture, the admin model, and the operational records all tell the same story.

## Next Step

The next high-value artifact is a concise `executive-summary.md` or `implementation-roadmap.md` that translates the whole working set into:
- current assumptions
- target state
- phased decisions
- immediate discovery questions
