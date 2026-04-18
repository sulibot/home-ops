# Enclave Boundary Draft

Source context:
- Handbook source: [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- Extracted text source: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- Supporting artifacts:
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-index.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-index.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/asset-classification-matrix.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/asset-classification-matrix.md)

This is a first-pass enclave boundary proposal for a small-to-mid-size aerospace manufacturer with Windows IT, CAD, ERP/MRP, and CNC/CMM-style manufacturing systems.

## Objective

Define a bounded `CUI enclave` that:
- contains the systems that process, store, or transmit controlled technical information and other likely `CUI`
- includes the security protection assets required to protect those systems
- limits unnecessary scope expansion into the broader corporate environment
- preserves controlled, auditable interfaces to manufacturing and business operations

## Boundary Model

The recommended model is:
- a `dedicated logical enclave` for engineering and controlled program execution
- a `connected but separately managed manufacturing/OT zone`
- a `general corporate zone` kept outside the certification boundary where feasible

This approach aligns with the handbook’s scoping logic:
- scope follows the information
- systems not adequately isolated from sensitive information can become in scope
- scope can be limited through physical or logical separation into a security domain or enclave

## Proposed Zones

### 1. Corporate Zone

Purpose:
- general office productivity
- HR, payroll, standard finance
- marketing and public web
- non-controlled business activity

Target status:
- outside the certification boundary
- outside the assessment boundary where possible

Conditions:
- no direct storage of `CUI`
- no routine handling of controlled drawings/specs/work instructions
- tightly controlled access into the enclave
- no shared unmanaged admin paths with enclave systems

### 2. CUI Enclave

Purpose:
- engineering, program, and controlled document workflows
- controlled collaboration with customers and suppliers
- technical data storage and release
- administration and protection of in-scope systems

Target status:
- primary certification boundary

Likely in-scope assets:
- engineering workstations
- CAD tools and supporting engineering applications
- PDM / PLM / controlled file repositories
- enclave collaboration and controlled document exchange
- enclave identity and MFA controls
- privileged admin workstations / jump hosts
- enclave firewalls and boundary-control systems
- enclave EDR / logging / backup / vulnerability management if dedicated or materially scoped to the enclave
- the controlled slice of ERP / MRP if it stores or presents controlled technical content

### 3. Manufacturing / OT Zone

Purpose:
- CNC programming
- CMM / inspection
- test equipment
- production execution systems
- vendor maintenance paths for manufacturing assets

Target status:
- likely part of the assessment boundary
- partly specialized assets, with some assets potentially inside the certification boundary if they directly process/store/transmit `CUI`

Design intent:
- do not treat this zone as ordinary corporate IT
- do not allow unrestricted lateral access from corporate endpoints
- use controlled transfer points and explicit admin methods

## Boundary Inclusion Logic

Include an asset in the certification boundary if any of the following are true:
- it directly stores, processes, or transmits controlled technical information or other likely `CUI`
- it is a required security protection asset for those systems
- it provides privileged administration to enclave systems
- it is the authoritative system of record for controlled engineering data

Include an asset in the assessment boundary, but not necessarily the certification boundary, if:
- it provides supporting or enabling functions to the enclave
- it is a specialized manufacturing asset relevant to the handling of controlled data
- it is a shared service whose controls or responsibilities must be evaluated for enclave protection

Keep an asset out of scope only if:
- it does not handle `FCI` or `CUI`
- it is logically and physically isolated from enclave systems
- it has no privileged or indirect administrative role that would compromise enclave protection

## Proposed In-Scope Systems

These are the systems I would assume belong in the enclave until proven otherwise:
- engineering user endpoints
- CAD and technical analysis systems
- drawing release / document control / PDM functions
- controlled file storage and approved collaboration mechanisms
- customer technical email/collaboration for enclave users
- identity, MFA, and conditional access controls used by enclave users
- privileged admin endpoints for enclave management
- firewall policy enforcement around enclave boundaries
- logging and EDR functions that directly protect enclave systems
- remote access platform used to access enclave systems
- ERP/MRP components that expose controlled drawings, travelers, routings, attachments, or work instructions

## Proposed Specialized / Adjacent Systems

These systems should be assumed relevant to the assessment until the real data flow is known:
- CNC programming stations
- machine controllers and shop-floor HMIs
- CMM / inspection workstations
- test systems and data acquisition platforms
- OT file servers or manufacturing staging repositories
- OEM or integrator remote support tools
- backup systems holding enclave or specialized-asset data

## Proposed Out-of-Scope Systems

These should remain outside the certification boundary if separation is real:
- public website and marketing stack
- general HR and payroll platforms
- standard accounting workflows not tied to controlled program data
- ordinary office productivity for users who do not touch controlled contracts

## Key Boundary Controls

The enclave is only credible if these controls exist:
- dedicated network segmentation between corporate, enclave, and manufacturing
- least-privilege identity and role separation
- MFA for privileged and remote access
- separate privileged administration path
- controlled file transfer path between enclave and manufacturing
- centralized logging and auditable admin activity
- controlled vendor and MSP remote access
- backup, recovery, and endpoint management that respect enclave boundaries

## Likely Failure Modes

These are the design choices most likely to invalidate the boundary:
- engineers using standard corporate endpoints for controlled work
- shared file repositories between corporate and enclave users
- ERP attachments making the whole ERP deployment in scope
- unmanaged or poorly logged vendor access into manufacturing assets
- shared admin credentials between corporate and enclave systems
- flat routing between engineering and shop-floor networks
- backups or EDR tools with global admin access but no boundary-aware governance

## Open Decisions

These decisions must be resolved to finalize the boundary:
- whether the identity layer is shared, segmented, or duplicated
- whether enclave email/collaboration is logically separated inside a shared tenant or carved out more strongly
- whether ERP is fully in scope or only a controlled subset
- whether CNC/CMM/test endpoints directly retain controlled technical data
- whether MSP/MSSP tools have admin reach into enclave systems
- whether the company can support dedicated enclave endpoints for engineering users

## Draft Boundary Statement

The proposed certification boundary consists of the engineering and controlled-program environment, including the endpoints, applications, repositories, identity services, administrative systems, and security protection assets required to process, store, transmit, and safeguard controlled technical information and related `CUI`. Manufacturing and test systems that consume or derive from controlled data are treated as connected specialized assets and included in the broader assessment scope, with inclusion in the certification boundary determined by the actual data retained, processed, and administered on those assets.

## Next Step

Use this draft to build:
- `ams-target-architecture.md`
- `shared-responsibility-matrix.md`
- `evidence-checklist.md`
