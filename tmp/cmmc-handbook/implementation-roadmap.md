# Implementation Roadmap

Source context:
- Handbook source: [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- Extracted text source: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- Planning package root: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/README.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/README.md)

This roadmap turns the current planning package into a practical sequence for building a defensible enclave in an AMS-style environment.

## Objective

Move from assumptions and public-profile modeling to:
- a validated boundary
- a working enclave design
- operational controls
- assessment-ready evidence

## Phase 0: Confirm Business and Contract Context

Goal:
- validate whether the target environment truly supports `DoD`, `NASA`, or other controlled programs

Actions:
- identify actual customer types and program classes
- identify whether the company receives customer technical data packages
- determine whether `FCI`, `CUI`, export-controlled data, or all three are present
- identify any existing contractual or regulatory security commitments

Outputs:
- customer/program context summary
- initial sensitive-information decision memo
- updated risk assumptions

## Phase 1: Discover and Classify the Environment

Goal:
- replace reasoned assumptions with actual system and data ownership

Actions:
- inventory endpoints, servers, cloud services, ERP/MRP, CAD/PDM, OT, and vendor access paths
- identify who uses which systems
- map where technical data is created, stored, shared, and released
- classify systems using the working categories:
  - `CUI asset`
  - `security protection asset`
  - `specialized asset`
  - `contractor risk managed asset`
  - `out of scope`

Outputs:
- validated asset inventory
- first real data flow diagrams
- updated asset-classification matrix
- provider/MSP/vendor dependency list

## Phase 2: Define the Boundary

Goal:
- turn discovery into a defendable certification and assessment boundary

Actions:
- identify enclave users
- define enclave systems
- identify supporting shared services
- identify manufacturing and specialized assets
- document in-scope and out-of-scope rationale
- validate where ERP and collaboration actually land

Outputs:
- finalized enclave boundary draft
- certification boundary statement
- assessment boundary statement
- scope decision log

## Phase 3: Build the Enclave Core

Goal:
- establish the minimum viable secure operating domain for controlled work

Actions:
- provision dedicated enclave endpoints for engineering and covered users
- implement enclave-specific identity and MFA controls
- establish privileged admin separation
- segment enclave networks from corporate and OT networks
- place CAD/PDM/document repositories inside the enclave
- onboard enclave systems to logging, EDR, patching, and backup

Outputs:
- enclave user/device baseline
- enclave network segmentation
- admin path implementation
- enclave service inventory

## Phase 4: Integrate Business Systems Safely

Goal:
- keep business operations functional without allowing scope to sprawl unnecessarily

Actions:
- determine whether ERP can be split by function or module
- isolate or mediate controlled attachments and work instructions
- configure collaboration and external sharing for enclave users
- document shared enterprise service inheritance

Outputs:
- ERP scoping decision
- collaboration/security configuration decisions
- shared responsibility matrix with actual owners

## Phase 5: Integrate Manufacturing and Specialized Assets

Goal:
- control how engineering data reaches production and test systems

Actions:
- define approved release path from enclave to manufacturing staging
- isolate CNC/CMM/test systems in a manufacturing zone
- control vendor remote access
- document specialized asset management approach
- define return path for inspection/test records

Outputs:
- manufacturing network and transfer design
- specialized asset inventory
- vendor maintenance procedure
- OT boundary controls

## Phase 6: Operationalize and Produce Evidence

Goal:
- ensure the environment is not only designed but operated in a way that can be proven

Actions:
- complete SSP
- finalize policies, standards, and procedures
- implement access reviews, change records, incident workflows, and backup/restore tests
- collect sample evidence from real operations
- validate diagrams and inventories against reality

Outputs:
- assessment-ready evidence package
- completed SSP
- sample operational records
- readiness review package

## Phase 7: Readiness Review and Remediation

Goal:
- identify weak points before formal assessment pressure

Actions:
- test the boundary against real admin paths and user behavior
- verify logging coverage and restore processes
- review access control, remote maintenance, and shared-service governance
- resolve gaps and document residual risks

Outputs:
- readiness findings
- remediation plan
- updated risk register

## Immediate Priorities

If resources are limited, do these first:
1. confirm whether the company actually handles `CUI`
2. identify enclave users and engineering data repositories
3. classify ERP and collaboration exposure
4. identify manufacturing data-transfer paths
5. establish privileged admin separation and enclave segmentation strategy

## CTO Readout

The largest practical risks are not usually missing policies. They are:
- uncontrolled technical data movement
- shared identity and admin paths
- ERP scoping ambiguity
- vendor/MSP access into enclave or OT systems
- manufacturing assets quietly handling controlled data without governance

The roadmap should therefore prioritize scope discipline and control-plane separation before large policy-writing exercises.
