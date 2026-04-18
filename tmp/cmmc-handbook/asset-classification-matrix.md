# Asset Classification Matrix

Source context:
- Handbook source: [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- Extracted text source: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- Company model: small-to-mid-size aerospace manufacturer with Windows corporate IT, CAD, ERP/MRP, CNC/CMM-style manufacturing systems, likely cloud collaboration, and an enclave deliverable.

This is a reasoned first-pass matrix, not a validated inventory.

## How to Use This

- Treat this as a scoping draft.
- Replace assumptions with real system names as they are discovered.
- Use the `likely boundary status` column to drive enclave decisions.
- Use the `questions / risks` column to identify what must be validated with stakeholders.

## Working Categories

- `CUI asset`: directly processes, stores, or transmits CUI.
- `Security protection asset`: protects in-scope assets or provides security-relevant control functions.
- `Specialized asset`: OT, IIoT, CNC/CMM/test, restricted systems, or other manufacturing technology treated specially in Level 2 scoping.
- `Contractor risk managed asset`: adjacent/supporting asset documented and governed through the contractor’s risk-based controls.
- `Out of scope`: no CUI/FCI handling and adequately isolated from in-scope systems.

## Matrix

| Asset / system class | Likely business role | Likely CUI exposure | Likely category | Likely boundary status | Why it matters | Questions / risks |
| --- | --- | --- | --- | --- | --- | --- |
| Corporate user laptops/desktops | email, office work, general business operations | Low to medium | Contractor risk managed asset or out of scope | Keep out if enclave separation is real | Corporate endpoints often drag the whole estate into scope when engineers or program staff use them for controlled work | Do engineering and program users use standard corporate endpoints or dedicated enclave devices? |
| Engineering workstations | CAD, modeling, drawing creation, design analysis | High | CUI asset | In certification boundary | Likely primary place where controlled technical data is created, modified, or reviewed | Are these dedicated devices, VDI sessions, or mixed-use workstations? |
| CAD application stack | design authoring and technical package creation | High | CUI asset | In certification boundary | Core technical data handling system | Which CAD/PDM tools are used and where is data actually stored? |
| PDM / PLM / document control | drawing revision control, approvals, release management | High | CUI asset | In certification boundary | Often the authoritative system for controlled engineering data | Is there a formal PDM/PLM or just file shares/SharePoint? |
| Engineering file shares / SharePoint / OneDrive / Teams | collaboration and storage | High if used for technical data | CUI asset or security protection asset | Likely in certification boundary | Shared storage/collaboration can quickly become the true enclave core | Are Microsoft 365 services shared with corporate users or segmented by policy and tenant controls? |
| Email and messaging for program/engineering staff | customer and supplier communication | Medium to high | CUI asset or security protection asset | Likely in certification boundary for enclave users | Technical exchanges often happen over email even when policy says otherwise | Which users exchange drawings/specs through email? Is DLP or message encryption used? |
| Identity provider for enclave users | authentication, MFA, conditional access, SSO | Medium to high | Security protection asset | In assessment boundary and often certification boundary | Identity is foundational for all enclave access control and evidence | Shared tenant or separate tenant? Shared AD domain or separate admin boundary? |
| Domain controllers / directory services supporting enclave | authentication and policy enforcement | Medium to high | Security protection asset | In boundary if they directly support enclave systems | Shared identity can greatly expand scope | Can the enclave inherit from enterprise AD safely, or is a separate domain/tier needed? |
| Privileged admin workstations / jump hosts | administration of enclave systems | High | Security protection asset | In certification boundary | Required to keep administrative access controlled and auditable | Are admins currently using general-purpose workstations? |
| VPN / ZTNA / remote access platform | remote user and vendor access | Medium to high | Security protection asset | In assessment boundary, likely certification boundary | Remote access is a common scope-expansion and control-failure point | How are remote employees, MSPs, and vendors connecting today? |
| Firewalls / segmentation gateways protecting enclave | network boundary control | Medium | Security protection asset | In assessment boundary, often certification boundary | Enclave validity depends on enforceable separation | Are there dedicated firewall policies between corporate, enclave, and OT? |
| EDR / AV / XDR platform for enclave endpoints | endpoint protection | Medium | Security protection asset | In assessment boundary | Must show protection and monitoring of in-scope endpoints | Shared global EDR tenant or enclave-specific policy set? |
| SIEM / log management | centralized logging and alerting | Medium | Security protection asset | In assessment boundary | Needed for evidence, incident response, and auditability | Are logs retained centrally and can enclave events be separated? |
| Vulnerability management / patching systems | maintenance and remediation | Medium | Security protection asset | In assessment boundary | Required to show managed maintenance and change discipline | Shared tooling is fine only if separation and role control are defensible |
| Backup platform for enclave data | recovery and resilience | Medium to high | Security protection asset | In assessment boundary | Backups often hold the same sensitive data as production systems | Are backups encrypted, access-controlled, and logically separated? |
| ERP / MRP platform core | parts, BOMs, routings, purchasing, work orders | Medium | CUI asset or contractor risk managed asset | Partial boundary or broader inclusion depending on use | ERP often becomes a scoping battleground because it mixes controlled and ordinary data | Does ERP store attachments, drawings, specs, or controlled traveler/work order data? |
| ERP document attachments / controlled work instructions | technical package references tied to production | High | CUI asset | In certification boundary if present | This is often what pulls ERP into scope | Can controlled documents be externalized from ERP or tightly segmented? |
| Quality management records | inspections, nonconformance, certifications, traceability | Medium | CUI asset or contractor risk managed asset | Often adjacent; sometimes in boundary | Quality systems may contain controlled test/acceptance data | Does QA system store customer-controlled specs or acceptance data? |
| CNC programming workstations | convert engineering data into machine instructions | High | Specialized asset or CUI asset | Likely in assessment boundary; may be in certification boundary | Common choke point where CUI becomes manufacturing instructions | Do these systems store models, toolpaths, setup sheets, or only consume one-time transfers? |
| CNC machine controllers / HMIs | execute manufacturing operations | Low to medium directly, high operationally | Specialized asset | Usually assessment-boundary specialized asset | OT assets are explicitly recognized in Level 2 scoping | Network isolation and vendor access are usually the primary risks |
| CMM / metrology systems | inspection and measurement | Medium | Specialized asset | Likely assessment boundary specialized asset | May store controlled specs and test results | Do they store controlled drawings/tolerances locally? |
| Test equipment / data acquisition systems | validation and qualification testing | Medium to high | Specialized asset | Likely assessment boundary specialized asset | Handbook explicitly calls out test equipment | What customer data and reports live there, and how are they exported? |
| OT historian / manufacturing file server | shop-floor data aggregation | Medium | Specialized asset or CUI asset | Often in boundary if it stores controlled production data | Can quietly become the manufacturing side of the enclave | Is there a dedicated manufacturing server layer? |
| Vendor remote support tools for machines | OEM or integrator maintenance access | Medium to high | Security protection asset or specialized asset support | In assessment boundary if used on in-scope/specialized assets | Remote maintenance is a major Level 2 risk area | Is access brokered, MFA-protected, logged, and time-bounded? |
| MSP / MSSP remote management tooling | outsourced IT and security operations | Medium to high | Security protection asset | In assessment boundary if it touches enclave systems | Shared tooling can collapse separation if not tightly controlled | Which tools have admin rights into enclave systems? |
| Public website / marketing stack | web presence and lead generation | Low | Out of scope | Keep out | Should remain outside if not connected to CUI workflows | Shared admins or hosting credentials can still create indirect risk |
| HR / payroll systems | personnel administration | Low | Out of scope | Keep out | Normally no reason to include in certification boundary | Shared identity/admin tooling may still matter |
| General finance / accounting | bookkeeping, AP/AR | Low | Out of scope or contractor risk managed asset | Keep out unless tied to controlled contract data | Normally should remain outside | Some ERP deployments mix accounting and controlled production data in one platform |
| Mobile devices for enclave users | email, MFA, collaboration | Medium | CUI asset or security protection asset | Often in boundary if used for controlled access | Mobile access expands the enclave surface area | Are phones enrolled/managed and allowed to access enclave mail/files? |
| Printers handling technical drawings | hard-copy output of controlled data | Medium | Contractor risk managed asset or CUI-adjacent | Document and control if used for enclave output | Printed drawings are still part of the information flow | Where are they located, and who can retrieve output? |

## CTO-Style Default Position

If the company resembles the assumed profile, the most defensible starting position is:
- keep general corporate IT outside the certification boundary where possible
- place engineering, controlled collaboration, and the controlled slice of ERP inside the enclave
- treat manufacturing and test systems as specialized assets in a tightly controlled connected zone
- place shared identity, remote access, logging, EDR, backup, and admin tooling under explicit shared-responsibility and scoping decisions

## Immediate Discovery Questions

These questions will collapse uncertainty fastest:
- Which users receive or generate customer technical data?
- Where are the authoritative CAD files and released drawings stored?
- Does ERP contain controlled attachments or only references?
- How are CNC/CMM/test systems fed from engineering?
- Which cloud services are used by engineering and program staff?
- Who administers enclave-relevant systems: internal IT, MSP, vendors, or a mix?
- Are there any existing VLANs, firewalls, jump hosts, or dedicated engineering domains?

## Next Step

Use this matrix to produce:
- `enclave-boundary-draft.md`
- `ams-target-architecture.md`
- `shared-responsibility-matrix.md`
