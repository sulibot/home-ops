# Interview Worksheet

Purpose:
- turn discovery into a repeatable interview process
- capture answers in a format that can directly update the planning package
- support revision of the enclave boundary and final deliverable

Instructions:
- Use one worksheet per interview session or stakeholder group.
- Record assumptions, direct answers, and follow-up items separately.
- If the answer is unknown, write `unknown` rather than guessing.
- If evidence exists, record where it lives.

## Session Information

| Field | Value |
| --- | --- |
| Interview date | |
| Interviewer | |
| Interviewee(s) | |
| Role / department | |
| Follow-up owner | |
| Related systems | |
| Notes | |

## Answer Conventions

Use these fields where helpful:
- `Answer`
- `Confidence`
- `Evidence / source`
- `Follow-up`

Confidence values:
- `high`
- `medium`
- `low`

## 1. Business and Contract Context

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Which customers does the company currently serve? | | | | |
| Are any current or expected customers `DoD`, `NASA`, primes, or federal subcontractors? | | | | |
| Does the company receive or generate `FCI`? | | | | |
| Does the company receive or generate `CUI`? | | | | |
| Does the company handle export-controlled technical data? | | | | |
| Which contracts or security requirements are driving this effort? | | | | |
| Has the company been given a required CMMC level or `NIST SP 800-171` obligation? | | | | |

## 2. Organizational Scope

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Is the intended scope the whole company, one site, one host unit, or one enclave? | | | | |
| Which departments directly support controlled work? | | | | |
| Which departments need access to controlled engineering data? | | | | |
| Are there separate legal entities or divisions involved? | | | | |
| Are subcontractors or supporting organizations involved? | | | | |

## 3. Identity and User Population

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| What identity platform is used? | | | | |
| Is authentication on-prem, cloud, or hybrid? | | | | |
| Is MFA enforced today? For whom? | | | | |
| Who would be enclave users? | | | | |
| Are privileged admin accounts separate from standard user accounts? | | | | |
| Are shared admin accounts still in use? | | | | |
| Do contractors, MSPs, or vendors have admin access? | | | | |

## 4. Endpoints and User Devices

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| How many Windows endpoints exist? | | | | |
| Which endpoints are used by engineering? | | | | |
| Are engineering users on dedicated devices? | | | | |
| Are devices used remotely or offsite? | | | | |
| Are mobile devices allowed to access company mail/files? | | | | |
| What endpoint management and EDR tools are in use? | | | | |
| Is local admin access restricted? | | | | |

## 5. Engineering and Controlled Data Systems

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Which CAD tools are used? | | | | |
| Is there a `PDM`, `PLM`, or document control system? | | | | |
| Where do authoritative engineering files live? | | | | |
| How are revisions approved and released? | | | | |
| How are drawings/specs shared internally? | | | | |
| How are drawings/specs shared externally? | | | | |
| Are controlled files stored in SharePoint, Teams, OneDrive, or general shares? | | | | |

## 6. ERP / MRP / Quality Systems

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Which ERP / MRP platform is used? | | | | |
| Does ERP store drawings or attachments? | | | | |
| Does ERP store BOMs, routings, or work instructions tied to controlled data? | | | | |
| Can ERP access be separated by module or function? | | | | |
| Is quality management inside ERP or separate? | | | | |
| Do quality systems contain controlled specs, test records, or technical results? | | | | |

## 7. Collaboration and Cloud Services

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Is Microsoft 365 used? Which services? | | | | |
| Is Teams used for engineering or customer collaboration? | | | | |
| Is SharePoint or OneDrive used for controlled content? | | | | |
| Are external sharing links enabled? | | | | |
| Are AWS, Azure, Google Cloud, or other SaaS platforms used for in-scope work? | | | | |
| Are secure file transfer tools used? | | | | |

## 8. Network and Segmentation

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| How many sites or facilities exist? | | | | |
| Are there separate VLANs or firewalled zones today? | | | | |
| Is there an engineering network or server zone? | | | | |
| Is there a manufacturing or OT network? | | | | |
| How is remote access provided? | | | | |
| Are there jump hosts or admin workstations today? | | | | |
| Can corporate users reach shop-floor systems directly? | | | | |

## 9. Manufacturing / OT / Specialized Assets

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| What CNC, CMM, metrology, test, or specialized systems exist? | | | | |
| Which systems run Windows or general-purpose operating systems? | | | | |
| Which systems receive engineering files or toolpaths? | | | | |
| Which systems store technical data locally? | | | | |
| How is engineering data transferred to the shop floor? | | | | |
| Is USB part of the normal process? | | | | |
| Do machine vendors or integrators have remote access? | | | | |
| How are test and inspection results returned to engineering or quality? | | | | |

## 10. Security Operations and Shared Services

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| What tools are used for EDR / AV? | | | | |
| What tools are used for logging / SIEM? | | | | |
| What tools are used for backup and recovery? | | | | |
| What tools are used for vulnerability scanning and patching? | | | | |
| What tools are used for MDM / RMM and ticketing? | | | | |
| Which services are internally managed versus MSP-managed? | | | | |
| Can enclave logs be isolated and reviewed separately? | | | | |
| Are backup admin and restore rights controlled? | | | | |

## 11. MSP / MSSP / Vendor Access

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Is there an MSP or MSSP? | | | | |
| Which systems can providers access administratively? | | | | |
| What tools do they use to connect? | | | | |
| Is MFA required for provider access? | | | | |
| Are provider sessions logged and reviewed? | | | | |
| Do machine vendors or OEMs connect remotely? | | | | |
| Are approvals required before support sessions begin? | | | | |

## 12. Policy, Governance, and Readiness

| Question | Answer | Confidence | Evidence / source | Follow-up |
| --- | --- | --- | --- | --- |
| Does an `SSP` already exist? | | | | |
| Does an asset inventory already exist? | | | | |
| Do current network diagrams exist? | | | | |
| Does an incident response plan exist? | | | | |
| Is there a formal change management process? | | | | |
| Are access reviews performed? | | | | |
| Are backup/restore tests performed? | | | | |
| Has a gap assessment already been done? | | | | |
| Are there known difficult legacy systems or exceptions? | | | | |

## 13. Decision Log

| Decision item | Current answer | Owner | Date needed | Notes |
| --- | --- | --- | --- | --- |
| Actual controlled-data boundary | | | | |
| Enclave user population | | | | |
| Authoritative engineering repository | | | | |
| ERP scope decision | | | | |
| Manufacturing specialized-asset scope | | | | |
| Shared-service inheritance decisions | | | | |
| Provider access/control decisions | | | | |

## 14. Assumptions Replaced

| Original assumption | Updated answer | Source |
| --- | --- | --- |
| | | |
| | | |
| | | |

## 15. Follow-Up Actions

| Action | Owner | Due date | Status |
| --- | --- | --- | --- |
| | | | |
| | | | |
| | | | |
