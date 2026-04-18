# Architecture View

This document translates the handbook into a systems-architect working model.

Primary source:
- [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- extracted text: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)

Visual fallback:
- [`/Users/sulibot/Downloads/CMMC Class Handbook OCR.pdf`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20OCR.pdf)

## Core Read

The handbook is clear on the architectural logic:
- Scope is driven by where sensitive information is processed, stored, transmitted, or insufficiently isolated.
- The organization should document that scope in an asset inventory, SSP, and network diagrams.
- Scope can be limited with a separate security domain or enclave if separation is real and enforceable.
- Specialized manufacturing and OT assets remain relevant at Level 2 even when assessed differently.

Primary handbook anchors:
- `L5-TA` pages 228-243
- `L5-TD` pages 290-301
- `L5-TE` pages 302-313
- `L7-TA` pages 344-357
- `L9-TA` pages 434-453

## Scoping Rules

Use these as first-pass decision rules:
- If a system handles `FCI` or `CUI`, it is in scope.
- If a system does not handle `FCI` or `CUI` but is not logically or physically isolated from systems that do, it is likely in scope.
- If a service provider touches in-scope systems or data, the provider relationship and inherited/shared controls matter.
- If a manufacturing or OT asset receives, stores, or acts on controlled data, it must be documented and considered in the Level 2 scope analysis.

## Boundary Rules

The handbook supports an enclave model:
- A certification boundary is narrower than the total contractor environment.
- An assessment boundary can include enabling assets and supporting assets outside the certification boundary.
- The SSP should document boundaries, information flows, and responsibilities.
- The rationale for limiting scope is separation: physical, logical, or both.
- If separation is weak, the boundary expands.

## Asset Categories That Matter

For enclave design, treat these as the practical working categories:
- `CUI assets`: systems that directly process, store, or transmit CUI.
- `Security protection assets`: systems that protect the enclave, such as identity, logging, EDR, firewalls, backup, and admin tooling.
- `Specialized assets`: OT, IIoT, CNC/CMM/test systems, restricted systems, and certain manufacturing technology.
- `Contractor risk managed assets`: adjacent or connected systems that influence risk and must be documented and governed even if not assessed against all practices.

## Shared Service Implications

The handbook repeatedly pushes shared responsibility and provider context. For architecture work, that means:
- Shared identity, cloud, backup, EDR, SIEM, and remote access services can pull themselves into the assessment boundary.
- If a shared service is reused between corporate IT and the enclave, the control inheritance and separation model must be explicit.
- MSP, MSSP, cloud, and subcontractor relationships need documented responsibility boundaries.

## Evidence Requirements

The minimum planning artifacts implied by the handbook are:
- `SSP`
- `asset inventory`
- `network diagrams`
- `IT/security policies`
- `standards/procedures`
- `organizational charts`
- `shared responsibility matrix`
- supporting plans such as incident response and configuration management

## Likely Technical Controls

The handbook points toward these recurring design requirements at Level 2:
- MFA for privileged access and network access to non-privileged users.
- Segmentation and boundary protection.
- Centralized identity and account control.
- Logging, auditability, and evidence retention.
- Managed remote maintenance, especially for nonlocal vendor support.
- Configuration management and documented change control.
- Incident handling capability with tracking, reporting, and testing.

## Manufacturer / Enclave Reading

For a Windows-based manufacturer with ERP, CAD, and CNC/CMM-style systems, the handbook implies this default design stance:
- Build a dedicated `CUI enclave` around engineering, controlled document handling, and the subset of business systems that hold technical contract data.
- Treat manufacturing systems as a separate zone with controlled transfers from the enclave.
- Do not assume the full corporate environment belongs in the certification boundary.
- Do assume shared security services and admin paths may belong in the assessment boundary.

## Recommended Next Artifacts

Build these next from the handbook and the target company context:
- `asset-classification-matrix.md`
- `enclave-boundary-draft.md`
- `shared-responsibility-matrix.md`
- `evidence-checklist.md`
- `ams-target-architecture.md`
