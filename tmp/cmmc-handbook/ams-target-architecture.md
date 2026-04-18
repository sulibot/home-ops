# AMS Target Architecture

Source context:
- Handbook source: [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- Extracted text source: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- Supporting drafts:
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/asset-classification-matrix.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/asset-classification-matrix.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md)
  - [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md)

This document is a reasoned target-state architecture for an AMS-style manufacturer with:
- Windows-based corporate IT
- engineering and CAD workloads
- ERP / MRP
- CNC / CMM / test systems
- likely Microsoft 365 and cloud-backed identity/collaboration
- a required enclave deliverable

It is intentionally architecture-first and assumes the company wants to constrain the Level 2 boundary rather than certify the entire business network.

## Architecture Goal

Create a bounded `CUI enclave` that supports engineering and controlled program execution while preserving controlled interfaces to:
- general corporate business operations
- manufacturing / OT operations
- cloud services
- MSP / MSSP and vendor support

## Design Principles

- Follow the information, not the org chart.
- Keep the certification boundary as small as is operationally realistic.
- Use shared enterprise services only where separation and responsibility are defensible.
- Separate user access, administrative access, and machine/system-to-system access.
- Treat manufacturing as a connected but differently governed zone, not as normal office IT.
- Build evidence alongside the architecture.

## Target Zones

### 1. Corporate Zone

Purpose:
- general business productivity
- HR, payroll, standard finance
- sales/marketing
- ordinary office operations

Design intent:
- outside the certification boundary
- minimal trust to enclave systems
- no casual file sharing with enclave repositories

Typical systems:
- standard user laptops
- HR/payroll platforms
- finance/accounting
- public website and marketing tools
- general collaboration for non-enclave users

### 2. CUI Enclave

Purpose:
- engineering design
- controlled technical documentation
- program execution for covered work
- controlled customer/supplier collaboration
- protected administrative and security services

Design intent:
- primary certification boundary
- dedicated logical security domain
- higher assurance access controls and admin model

Typical systems:
- engineering workstations
- CAD / PDM / PLM
- controlled file storage
- enclave collaboration and email access
- privileged admin workstations
- jump hosts
- enclave firewalls
- enclave logging / EDR / backup / vulnerability tooling
- controlled ERP / MRP components

### 3. Manufacturing / OT Zone

Purpose:
- CNC programming and execution
- CMM / metrology
- test systems
- shop-floor support systems
- vendor maintenance paths

Design intent:
- separate from both corporate and enclave user zones
- controlled ingestion of approved technical data from enclave
- no broad interactive access from corporate endpoints

Typical systems:
- CNC programming workstations
- machine HMIs/controllers
- test workstations
- inspection systems
- staging repositories for approved manufacturing packages

## Identity Model

Recommended model:
- one enterprise identity backbone may be acceptable, but the enclave must have a separate administrative boundary
- enclave users should be in dedicated security groups and governed by enclave-specific conditional access and device compliance rules
- privileged accounts for enclave administration must be separate from day-to-day user identities

Minimum target state:
- MFA enforced for all enclave users
- privileged access through separate admin accounts
- privileged actions performed only from admin workstations or jump hosts
- conditional access tied to managed compliant devices
- disable or tightly constrain legacy authentication

Preferred target state:
- separate enclave admin tier
- dedicated privileged access workstations
- dedicated break-glass procedure and account governance for enclave services

## Endpoint Model

### Corporate endpoints

- remain outside the enclave
- do not access controlled repositories directly
- do not administer enclave systems

### Enclave user endpoints

- dedicated managed Windows devices for engineering and covered program users
- stronger hardening baseline than corporate endpoints
- managed local admin policy
- EDR, patching, encryption, device control, and logging aligned to enclave requirements

### Admin endpoints

- separate devices or locked-down administrative workstations
- used only for enclave administration
- isolated from general browsing and office work

## Network Model

Recommended segmentation:
- `corp-user` network
- `enclave-user` network
- `enclave-server` network
- `management/admin` network
- `manufacturing/OT` network
- `DMZ/integration` network if needed for specific transfer or publishing functions

Required controls:
- deny-by-default inter-zone policy
- firewall enforcement between all major zones
- explicit approved flows only
- logging of boundary crossings

Critical boundaries:
- corporate -> enclave
- enclave -> manufacturing
- vendor/MSP -> enclave
- vendor/MSP -> manufacturing

## Data and Application Placement

### CAD / PDM / document control

Target placement:
- fully inside the enclave

Reason:
- likely authoritative source for controlled technical data

Rules:
- no uncontrolled sync to general corporate shares
- no unmanaged local replicas on non-enclave devices
- formal release path to manufacturing staging

### ERP / MRP

Target placement:
- split-function model where possible

Recommended approach:
- keep ordinary finance/accounting outside the certification boundary
- place controlled engineering/manufacturing data functions inside the enclave or behind enclave-mediated access

Examples likely to be in scope:
- drawing attachments
- controlled work instructions
- traveler data tied to technical specs
- BOM/routing details that reveal controlled design information

### Email / collaboration

Target placement:
- shared tenant is acceptable only if enclave users and enclave data are governed by clearly separable controls

Requirements:
- managed devices only
- MFA and conditional access
- restricted external sharing
- auditable access and retention
- documented responsibility model for tenant-wide services

### File transfer to manufacturing

Target placement:
- controlled transfer point between enclave and manufacturing

Recommended pattern:
- released manufacturing package exported from enclave
- transferred through approved staging process
- integrity-preserving handoff
- limited return path for inspection/test results

Avoid:
- general SMB shares spanning enclave and OT
- engineers RDPing directly into random shop-floor stations from corporate devices
- USB as the normal business process

## Security Services Model

### Logging / SIEM

- enclave-relevant logs centralized and retained
- admin actions, authentication, file access, and boundary-device events included
- ability to separate enclave events from corporate noise

### EDR / endpoint security

- all enclave endpoints covered
- enclave-specific policy set
- tamper protection and alert routing defined

### Backup / recovery

- enclave data backed up with protected admin access
- restoration process documented and tested
- backup repositories treated as sensitive

### Vulnerability / patch management

- enclave endpoints and servers patched on controlled cadence
- exceptions documented, especially for manufacturing dependencies
- specialized assets handled through risk-managed maintenance process

## Remote Access Model

Recommended:
- no direct broad VPN access from unmanaged endpoints
- remote access only from managed devices with MFA
- privileged remote administration only through jump infrastructure
- vendor access brokered, time-bounded, approved, and logged

Manufacturing-specific requirement:
- remote maintenance to CNC/test assets should terminate in the manufacturing zone, not bypass directly into enclave systems

## Administrative Model

Separate three classes of administration:
- `enterprise/corporate admin`
- `enclave admin`
- `manufacturing/OT admin`

Rules:
- no shared everyday admin credentials across all zones
- enclave admins use dedicated accounts and managed admin workstations
- vendor admin actions are supervised or strongly controlled
- high-risk administrative actions are logged and reviewable

## Shared Service Decisions

These services need explicit decision and documentation:
- identity provider
- Microsoft 365 / collaboration
- email hygiene / secure mail gateway
- backup platform
- EDR / MDR
- SIEM / SOC
- vulnerability management
- ticketing / ITSM
- remote support tooling

For each shared service, document:
- whether it is inside the certification boundary, assessment boundary, or inherited support
- who administers it
- what enclave-specific controls exist
- what evidence proves those controls

## Implementation Sequence

### Phase 1: Scope and stabilize

- identify enclave users and systems
- classify assets
- define boundary diagrams
- stop obvious scope bleed
- establish dedicated enclave admin path

### Phase 2: Build the enclave core

- enclave endpoint baseline
- identity and MFA controls
- segmentation/firewall policy
- CAD/PDM/document storage placement
- logging, EDR, backup, patching

### Phase 3: Integrate ERP and manufacturing safely

- map controlled ERP functions
- establish manufacturing staging and transfer model
- constrain vendor access
- document specialized asset handling

### Phase 4: Evidence and readiness

- complete SSP
- complete asset inventory and network diagrams
- finalize policies, standards, and procedures
- run readiness review against likely Level 2 controls

## CTO Recommendation

For a company like AMS, the most defensible and cost-effective design is:
- keep most corporate IT outside the certification boundary
- place engineering and controlled program execution inside a dedicated logical enclave
- treat manufacturing as a tightly controlled connected zone with specialized assets
- use shared enterprise platforms only when role separation, device control, logging, and administration are strong enough to support the enclave boundary

The wrong design would be a mostly flat enterprise where engineering, ERP, Microsoft 365, and manufacturing all interoperate freely and the company attempts to declare only a small subset “in scope.” That boundary would be difficult to defend.

## Recommended Next Artifact

Build `shared-responsibility-matrix.md` next so the architecture can be tied to actual service ownership, especially for identity, Microsoft 365, EDR, backup, SIEM, MSP, and vendor access.
