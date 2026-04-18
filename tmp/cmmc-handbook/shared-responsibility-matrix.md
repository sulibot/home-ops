# Shared Responsibility Matrix

Source context:
- Handbook source: [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- Extracted text source: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- Supporting artifacts:
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/ams-target-architecture.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/ams-target-architecture.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md)

This matrix is a first-pass ownership model for a manufacturer using shared enterprise services while trying to maintain a defensible `CUI enclave`.

Use it to answer:
- who owns the control
- whether the service sits inside the certification boundary or only the assessment boundary
- what evidence is needed to show the service supports the enclave appropriately

## Ownership Roles

- `Internal IT`: day-to-day enterprise infrastructure team
- `Security`: internal security lead, security ops, or vCISO function
- `Engineering Systems`: owners of CAD/PDM/document workflows
- `Manufacturing/OT`: owners of CNC/CMM/test and shop-floor systems
- `MSP/MSSP`: outsourced operations or monitoring provider
- `Vendor / CSP`: software, cloud, or equipment provider
- `Business owner`: process owner such as engineering, quality, or finance leadership

## Matrix

| Service / capability | Likely primary owner | Supporting parties | Boundary relevance | Typical decision | Evidence needed | Main risk if vague |
| --- | --- | --- | --- | --- | --- | --- |
| Enterprise identity / directory | Internal IT | Security, MSP | Assessment boundary, often certification boundary | Shared backbone with enclave-specific controls, unless risk forces split identity | tenant/domain design, admin roles, MFA policy, conditional access, privileged account model | shared identity with weak admin separation collapses the enclave |
| MFA platform | Security | Internal IT, Vendor | Certification boundary support | Shared service with enclave-specific enforcement | MFA policy, enrollment records, enforcement settings, logs | exceptions or unmanaged methods undermine access control |
| Enclave user device management | Internal IT or Security | MSP | Certification boundary support | Dedicated policy set for enclave devices | compliance policies, device inventory, baseline settings, admin assignments | corporate and enclave devices become indistinguishable |
| Admin workstations / jump hosts | Security or Internal IT | MSP | Certification boundary | Dedicated enclave-managed assets | inventory, hardening standard, access logs, admin assignment records | privileged admin occurs from ordinary user endpoints |
| Microsoft 365 / collaboration tenant | Internal IT | Security, Vendor | Assessment boundary; possibly certification boundary depending on use | Shared tenant with strong segmentation and sharing controls | tenant architecture, sharing settings, retention, DLP/configuration, admin roles | controlled data leaks through a broadly shared tenant |
| Enclave email / document sharing policy | Security | Internal IT, Business owner | Certification boundary support | Separate policy set for enclave users and data | access rules, sharing restrictions, transport protections, audit records | email and Teams become the uncontrolled data path |
| CAD / PDM / document control platform | Engineering Systems | Internal IT, Vendor | Certification boundary | Enclave-hosted or enclave-governed | system inventory, role mapping, storage locations, admin records, release procedures | authoritative technical data sits in an unmanaged or shared repository |
| ERP / MRP core platform | Business owner | Internal IT, Vendor | Split: outside, assessment, or certification boundary depending on module use | Prefer split-function scoping | data flow analysis, module owners, attachment usage, role model, integrations | the whole ERP estate gets pulled in by attachments and work instructions |
| ERP attachments / technical package functions | Business owner | Engineering Systems, Internal IT | Certification boundary if used for controlled data | Explicitly scoped as enclave-relevant | repository details, attachment controls, access model, workflow diagrams | no one knows where controlled technical records live |
| Firewall / segmentation platform | Internal IT | Security, MSP | Certification and assessment boundary support | Shared platform with enclave-specific rules | rule sets, network diagrams, change records, logs | enclave boundaries exist only on paper |
| VPN / ZTNA / remote access | Security | Internal IT, MSP, Vendor | Certification and assessment boundary support | Managed access path only | remote access policy, MFA enforcement, allowed device rules, logs | unmanaged remote access bypasses the enclave |
| SIEM / centralized logging | Security or MSSP | Internal IT, Vendor | Assessment boundary support | Shared platform with enclave-visible evidence | log source list, retention, admin roles, alert routing, sample events | inability to prove monitoring and admin accountability |
| EDR / XDR / MDR | Security or MSSP | Internal IT, Vendor | Assessment boundary support | Shared platform with enclave policy separation | policy assignments, deployment coverage, tamper controls, alerts, response records | global tool exists but enclave coverage is incomplete |
| Vulnerability management | Security | Internal IT, MSP | Assessment boundary support | Shared tooling with enclave reporting | scan scope, exception records, remediation workflow, reports | enclave assets are not actually scanned or tracked |
| Backup / recovery platform | Internal IT | Security, Vendor | Assessment boundary; sometimes certification boundary | Shared platform allowed only with strict admin/data separation | backup scope, encryption, restore procedures, access controls, test records | backup administrators have broad undeclared access to enclave data |
| Ticketing / ITSM / change records | Internal IT | Security, MSP | Assessment boundary support | Shared enterprise service is acceptable | change tickets, incident tickets, access approval records, audit trail | decisions affecting enclave have no traceable governance |
| MSP remote management tooling | MSP | Internal IT, Security | Assessment boundary, sometimes certification boundary | Must be explicitly approved and constrained | contract/SOW, admin scope, MFA, session logging, named personnel, access review | MSP tools become invisible super-admin channels |
| MSSP / SOC monitoring | MSSP or Security | Internal IT | Assessment boundary support | Shared security service with documented scope | monitoring scope, escalation procedures, evidence of review, log coverage | managed detection exists but not for enclave assets |
| Cloud hosting or SaaS outside Microsoft 365 | Vendor / CSP | Internal IT, Security, Business owner | Depends on system role | Case-by-case scoping and inheritance analysis | service description, shared responsibility terms, admin model, audit reports | cloud assumptions are undocumented and unenforceable |
| CNC programming environment | Manufacturing/OT | Engineering Systems, Vendor | Assessment boundary, sometimes certification boundary | Treat as specialized asset with controlled governance | asset inventory, data flow, admin method, maintenance procedure, network path | toolpaths and models are handled like ordinary files |
| Machine vendor remote support | Vendor | Manufacturing/OT, Internal IT | Assessment boundary support | Time-bounded, approved, logged access only | vendor access procedure, MFA method, logs, approvals, session records | vendor support becomes a permanent backdoor |
| Test equipment and metrology systems | Manufacturing/OT or Quality | Vendor, Internal IT | Specialized asset in assessment boundary | Documented specialized-asset model | inventory, local data handling, maintenance method, export path | test systems retain controlled data outside formal governance |
| Policy and standards management | Security | Internal IT, Business owners | Whole program | Internal ownership with business sign-off | policy set, standards, revision history, approvals | control implementation has no governing baseline |
| SSP and scope artifacts | Security or architect lead | Internal IT, Engineering, Manufacturing, Business owners | Core assessment evidence | Internal ownership required | SSP, diagrams, asset inventory, responsibility matrix | architecture and evidence diverge |

## Default Responsibility Positions

If the company resembles the assumed profile, I would recommend:
- `Internal IT` owns enterprise identity, network, endpoint management, backup, and general infrastructure operations.
- `Security` owns policy, MFA standards, privileged access model, logging requirements, incident handling design, and assessment evidence coordination.
- `Engineering Systems` owns CAD/PDM/document control decisions and technical-data workflow integrity.
- `Manufacturing/OT` owns CNC/CMM/test operating procedures and vendor access approval for shop-floor assets.
- `MSP/MSSP` can support operations, but only under explicit scoping, named responsibilities, and auditable access conditions.

## Non-Negotiable Documentation

For every shared service that touches the enclave, document:
- who administers it
- which users/systems in the enclave depend on it
- whether it is in the certification boundary or assessment boundary
- what controls are inherited versus locally implemented
- what evidence proves the control is real

## CTO Recommendation

Do not allow “shared service” to become shorthand for “unexamined dependency.” In an enclave design, the hardest failures usually come from identity, collaboration, backup, EDR, remote support, and MSP tooling because everyone assumes those are just background utilities. They are often some of the most important in-scope control providers.

## Next Step

Build `evidence-checklist.md` next so the architecture and shared-responsibility decisions can be tied to concrete artifacts and proof points.
