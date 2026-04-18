# Discovery Questionnaire

Purpose:
- validate the current AMS-style assumptions
- replace reasoned estimates with actual environment data
- support revision of the enclave boundary and final deliverable

Use this with:
- CTO / IT leadership
- engineering systems owners
- manufacturing / OT owners
- quality / compliance
- program management
- MSP / MSSP or key vendors where relevant

## 1. Business and Contract Context

1. Which customers does the company currently serve?
2. Are any current or expected customers `DoD`, `NASA`, prime contractors, or subcontractors on federal programs?
3. Does the company currently receive or generate:
- `FCI`
- `CUI`
- export-controlled technical data
- proprietary customer technical packages
4. Which contracts, subcontracts, or customer security requirements are currently driving this work?
5. Has the company already been told a required CMMC level, `NIST SP 800-171` requirement, or similar obligation?

## 2. Organizational Scope

1. Is the company planning to scope:
- the whole company
- one business unit
- one program enclave
- one site/facility
2. Which departments directly support controlled work?
3. Which departments need access to engineering or controlled customer data?
4. Are there separate legal entities, divisions, or sister organizations involved?
5. Are there subcontractors or affiliated organizations that support in-scope work?

## 3. Identity and User Population

1. What identity platform is used today?
2. Is authentication on-prem, cloud, or hybrid?
3. Is MFA enforced today? For whom?
4. Which users would likely be enclave users?
5. Are privileged admin accounts separate from normal user accounts?
6. Are there any shared admin accounts still in use?
7. Are contractors, MSP staff, or vendors granted administrative access?

## 4. Endpoints and User Devices

1. How many Windows endpoints exist overall?
2. Which endpoints are used by engineering?
3. Are engineering users on dedicated devices or ordinary corporate devices?
4. Are laptops used offsite or remotely?
5. Are mobile devices allowed to access company email or files?
6. What endpoint management and EDR tools are in use?
7. Is local admin access restricted?

## 5. Engineering and Controlled Data Systems

1. Which CAD tools are used?
2. Is there a `PDM`, `PLM`, or document control system?
3. Where do authoritative engineering files live today?
4. How are revisions approved and released?
5. How are drawings/specs shared internally?
6. How are drawings/specs shared externally?
7. Are any controlled files stored in SharePoint, Teams, OneDrive, or general file shares?

## 6. ERP / MRP / Quality Systems

1. Which ERP / MRP platform is in use?
2. Does ERP store:
- drawings
- attachments
- BOMs
- routings
- work instructions
- traveler data
- quality/test records
3. Can ERP access be separated by module, function, or data set?
4. Is quality management inside ERP or separate?
5. Do QA or quality systems contain customer-controlled technical data?

## 7. Collaboration and Cloud Services

1. Is Microsoft 365 in use? If yes, which services?
2. Is Teams used for engineering or customer collaboration?
3. Is SharePoint or OneDrive used for controlled content?
4. Are external sharing links enabled?
5. Are any AWS, Azure, Google Cloud, or other SaaS platforms used for in-scope systems?
6. Are there any third-party secure transfer tools in use?

## 8. Network and Segmentation

1. What sites or facilities exist?
2. Are there separate VLANs or firewalled network segments today?
3. Is there an existing engineering network, server network, or manufacturing network?
4. How is remote access provided?
5. Are there existing jump hosts or admin workstations?
6. Are corporate users able to reach shop-floor systems directly?
7. Are there any flat or poorly controlled network paths between engineering and manufacturing?

## 9. Manufacturing / OT / Specialized Assets

1. What CNC, CMM, metrology, test, or other specialized systems exist?
2. Which of these systems run Windows or general-purpose operating systems?
3. Which systems receive engineering files, toolpaths, or setup sheets?
4. Which systems store technical data locally?
5. How is engineering data transferred to the shop floor?
6. Is USB part of the normal process?
7. Do machine vendors or integrators have remote access?
8. How are test results and inspection outputs stored and returned to engineering or quality?

## 10. Security Operations and Shared Services

1. What tools are used for:
- EDR / AV
- logging / SIEM
- backup
- vulnerability scanning
- patch management
- MDM / RMM
- ITSM / ticketing
2. Which of those are internally managed versus MSP-managed?
3. Are any of those services shared across all corporate systems without enclave separation?
4. Can logs for enclave systems be isolated and reviewed separately?
5. Are backup admins and restore rights controlled?

## 11. MSP / MSSP / Vendor Access

1. Is there an MSP or MSSP?
2. Which systems can they access administratively?
3. What tools do they use to connect?
4. Is MFA required for provider access?
5. Are sessions logged and reviewed?
6. Are machine vendors or OEMs able to connect remotely?
7. Are approvals required before support sessions begin?

## 12. Policy, Governance, and Readiness

1. Does the company already have:
- SSP
- asset inventory
- network diagrams
- incident response plan
- change management process
- access review process
- backup/restore testing
2. Has a gap assessment already been performed?
3. Are there known exceptions or legacy systems that will be difficult to secure?
4. Are there current audit reports, certifications, or external assessments that can be reused?

## 13. Decision Questions

These questions should be explicitly answered before finalizing the deliverable:

1. What is the actual controlled-data boundary?
2. Who are the enclave users?
3. Which systems are authoritative for controlled technical data?
4. Is ERP fully in scope, partially in scope, or out of scope?
5. Which manufacturing systems are specialized assets versus full in-scope systems?
6. Which shared services can be inherited safely, and which need enclave-specific treatment?
7. Which providers require formal shared-responsibility and access-control documentation?

## Expected Output

Once this questionnaire is answered, the following artifacts should be revised:
- `asset-classification-matrix.md`
- `enclave-boundary-draft.md`
- `ams-target-architecture.md`
- `shared-responsibility-matrix.md`
- `evidence-checklist.md`
- `executive-summary.md`

