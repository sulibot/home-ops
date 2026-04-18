# Handbook Index

Primary source:
- [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- extracted text: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)

Visual fallback:
- [`/Users/sulibot/Downloads/CMMC Class Handbook OCR.pdf`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20OCR.pdf)

## Chunk Schema

Each chunk is labeled with:
- `lesson`
- `topic`
- `pdf_pages`
- `cmmc_level`
- `domains`
- `focus`
- `keywords`

## Topic Chunks

| Chunk | PDF pages | Lesson | Topic | CMMC level | Domains | Focus | Keywords |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `L1-TA` | 14-23 | Lesson 1 | Identify Threats to the Defense Supply Chain | General | Governance, risk | Policy, architecture, operations | defense supply chain, threats, contractors, risk, external threats |
| `L1-TB` | 24-61 | Lesson 1 | Identify Regulatory Responses against Threats | General | Governance, legal, compliance | Policy, evidence | FAR 52.204-21, FISMA, DFARS, CUI, FCI, NIST, regulations |
| `L2-TA` | 62-79 | Lesson 2 | Identify Sensitive Information | Level 1-2 | Data protection | Scoping, policy, operations | FCI, CUI, CTI, markings, ITAR, export control |
| `L2-TB` | 80-131 | Lesson 2 | Manage the Sensitive Information | Level 1-2 | Access control, physical protection, system protection | Architecture, operations, policy | access control, segmentation, encryption, MFA, physical security, handling |
| `L3-TA` | 132-149 | Lesson 3 | Describe the CMMC Model Architecture | Level 1-3 | Program structure | Policy, evidence | model, levels, domains, practices, assessment guides |
| `L3-TB` | 150-186 | Lesson 3 | Define the CMMC Program and Its Ecosystem | Level 1-3 | Governance, assessment | Policy, evidence, operations | Cyber AB, C3PAO, CCP, CCA, ecosystem, level determination |
| `L3-TC` | 187-203 | Lesson 3 | Define Self-Assessments | Level 1-2 | Assessment | Evidence, operations | self-assessment, SPRS, affirmations, readiness |
| `L4-TA` | 204-214 | Lesson 4 | Identify Responsibilities of the CCP | General | Roles, governance | Policy, operations | responsibilities, consultant role, readiness, assessment support |
| `L4-TB` | 215-227 | Lesson 4 | Demonstrate Appropriate Ethics and Behavior | General | Ethics, governance | Policy | ethics, impartiality, confidentiality, professional conduct |
| `L5-TA` | 228-243 | Lesson 5 | Use the CMMC Assessment Scope Documentation | Level 1-2 | Scoping | Scoping, architecture, evidence | scope, asset categories, OSC, host unit, ESP, specialized assets |
| `L5-TB` | 244-269 | Lesson 5 | Get Oriented to the OSC Environment | Level 1-2 | Scoping, shared responsibility | Scoping, architecture, evidence | organizational context, cloud, MSP, ESP, contracts, responsibility matrix |
| `L5-TC` | 270-289 | Lesson 5 | Determine How Sensitive Information Moves | Level 1-2 | Data flows | Scoping, architecture | data flow, ingestion, sharing, subcontractors, lifecycle |
| `L5-TD` | 290-301 | Lesson 5 | Identify Systems in Scope | Level 1-2 | Scoping, SSP | Scoping, architecture, evidence | certification boundary, assessment boundary, SSP, network diagrams |
| `L5-TE` | 302-313 | Lesson 5 | Limit Scope | Level 1-2 | Boundary protection | Architecture, policy | enclave, isolation, security domain, logical separation, physical separation |
| `L6-TA` | 314-326 | Lesson 6 | Foster a Mature Cybersecurity Culture | General | Governance, people | Policy, operations | culture, accountability, adoption, leadership |
| `L6-TB` | 327-343 | Lesson 6 | Evaluate Readiness | Level 1-2 | Readiness, asset management | Evidence, operations | gap analysis, asset inventory, NIST 800-171, readiness, documentation |
| `L7-TA` | 344-357 | Lesson 7 | Determine Evidence | Level 1-2 | Evidence collection | Evidence | SSP, policies, standards, diagrams, shared responsibility matrix, records |
| `L7-TB` | 358-387 | Lesson 7 | Assess the Practices Using the CMMC Assessment Guides | Level 1-2 | Assessment methods | Evidence, operations | assessment objectives, examine, interview, test, MFA, boundary protection |
| `L8-TA` | 388-408 | Lesson 8 | Identify CMMC Level 1 Domains and Practices | Level 1 | All Level 1 domains | Policy, operations | Level 1, FCI, foundational practices |
| `L8-TB` | 409-425 | Lesson 8 | Perform a CMMC Level 1 Gap Analysis | Level 1 | Gap analysis | Evidence, operations | gap analysis, remediation, baseline |
| `L8-TC` | 426-433 | Lesson 8 | Assess CMMC Level 1 Practices | Level 1 | Assessment | Evidence | Level 1 evidence, assessor methods |
| `L9-TA` | 434-453 | Lesson 9 | Identify CMMC Level 2 Practices | Level 2 | All Level 2 domains | Architecture, policy, evidence, operations | Level 2, NIST 800-171, AC, IA, IR, MA, SC, SI |
| `L10-TA` | 454-466 | Lesson 10 | Identify Assessment Roles and Responsibilities | Level 1-2 | Assessment | Evidence, operations | assessor roles, OSC roles, pre-assessment |
| `L10-TB` | 467-481 | Lesson 10 | Plan and Prepare the Assessment | Level 1-2 | Assessment planning | Evidence, operations | target scope, artifacts, NDAs, review preparation |
| `L10-TC` | 482-502 | Lesson 10 | Conduct the Assessment | Level 1-2 | Assessment execution | Evidence, operations | interviews, testing, walkthroughs, traceability |
| `L10-TD` | 503-509 | Lesson 10 | Report the Assessment Results | Level 1-2 | Assessment reporting | Evidence | reporting, findings, deficiencies, scoring |
| `L10-TE` | 510-522 | Lesson 10 | Conduct the CMMC POA&M Close-Out Assessment | Level 2 | POA&M | Evidence, operations | remediation, close-out, unresolved findings |

## High-Value Architecture Chunks

Use these first if the task is enclave design or systems scoping:
- `L5-TA` (228-243): scoping rules, asset categories, specialized assets.
- `L5-TB` (244-269): external service providers, cloud/shared responsibility context.
- `L5-TC` (270-289): data flow tracing.
- `L5-TD` (290-301): certification boundary, assessment boundary, SSP.
- `L5-TE` (302-313): enclave and separation rationale.
- `L6-TB` (327-343): readiness and asset inventory.
- `L7-TA` (344-357): evidence package and artifacts.
- `L9-TA` (434-453): Level 2 practices that drive architecture decisions.

## Notes

- The scoping lesson is the core design driver for an enclave deliverable.
- The `.odg` extraction is the preferred textual source for this index.
- The handbook is training material, not the authoritative source of contract obligations. Use it to organize and operationalize the work, then verify material decisions against the governing clauses and standards.
