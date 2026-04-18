# CMMC Enclave Planning Draft

## Purpose

This document is a planning draft for a likely enclave-based compliance architecture for an AMS-style aerospace manufacturer. It is built from:
- the handbook source at [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- the extracted handbook text at [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)
- a reasoned model of the company’s likely environment based on its public profile and your stated assumptions

This draft should be treated as:
- a structured starting point
- a decision-support document
- a deliverable that will be revised once discovery answers are available

## Current Assumption Set

The company is assumed to have:
- a standard Windows-based corporate network
- engineering users and CAD workflows
- ERP / MRP supporting production operations
- CNC / CMM / test or similar specialized manufacturing systems
- cloud-backed identity and collaboration

The company is also assumed to potentially support controlled aerospace, defense, or adjacent work, which means the main security problem is likely the spread of controlled technical data across engineering, collaboration, ERP, and manufacturing.

## Recommended Strategic Direction

The recommended direction is to establish a `bounded CUI enclave` rather than trying to certify the entire enterprise by default.

This means:
- general corporate IT should remain outside the certification boundary where possible
- engineering and controlled technical workflows should be placed inside a dedicated logical enclave
- manufacturing and test systems should be treated as a connected but separately governed zone
- shared services such as identity, Microsoft 365, backup, EDR, SIEM, MSP tooling, and vendor access must be explicitly governed as part of the boundary design

## Working Architecture Position

### Corporate Zone

Should contain:
- general office productivity
- HR and payroll
- ordinary finance and accounting
- sales and marketing
- public web presence

Should remain out of scope unless:
- it stores or handles controlled technical data
- it has direct administrative reach into enclave systems
- it is not actually separated from enclave systems

### CUI Enclave

Should contain:
- engineering workstations
- CAD and engineering applications
- PDM / PLM / document control
- controlled file storage
- enclave collaboration and technical exchange
- privileged admin workstations
- identity, MFA, logging, EDR, backup, and other security functions needed to protect the enclave
- the controlled portion of ERP / MRP if it stores or presents controlled technical data

This is the most likely `certification boundary`.

### Manufacturing / OT Zone

Should contain:
- CNC programming systems
- machine HMIs/controllers
- CMM / metrology systems
- test systems
- controlled manufacturing staging points
- vendor maintenance paths

This zone is likely part of the `assessment boundary` and includes specialized assets. Some individual systems may also belong in the certification boundary depending on whether they directly store, process, or transmit controlled technical data.

## Core Scoping Conclusions

- Scope follows the information.
- Systems that do not directly store `CUI` can still become relevant if they are not properly isolated from systems that do.
- ERP, collaboration tools, and manufacturing programming workflows are likely to determine how large the real scope becomes.
- Shared services are not background utilities; they are often in-scope control providers.
- The enclave is only defensible if segmentation, admin separation, data transfer controls, and evidence all align.

## Key Planning Artifacts Developed

The working package includes:
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-index.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-index.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/lesson-summaries.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/lesson-summaries.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/architecture-view.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/asset-classification-matrix.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/asset-classification-matrix.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/enclave-boundary-draft.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/ams-target-architecture.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/ams-target-architecture.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/shared-responsibility-matrix.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/shared-responsibility-matrix.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/evidence-checklist.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/evidence-checklist.md)
- [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/implementation-roadmap.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/implementation-roadmap.md)

## Most Important Open Questions

The draft cannot be finalized until these are answered:
- does the company actually handle `FCI`, `CUI`, export-controlled data, or all three?
- which users handle controlled engineering data?
- where are the authoritative CAD / technical files stored?
- does ERP store controlled attachments, drawings, work instructions, or quality records?
- how does engineering data move to CNC / CMM / test systems?
- which cloud, MSP, and vendor services have administrative reach into the environment?
- what segmentation or enclave-like controls already exist?

## Immediate Recommendations

1. Run the discovery questionnaire in [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/discovery-questionnaire.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/discovery-questionnaire.md).
2. Replace assumptions in the asset matrix and enclave draft with actual system and ownership data.
3. Confirm whether the organization is scoping one business line, one site, one host unit, or the whole company.
4. Validate the real boundary of technical data before making irreversible architecture decisions.
5. Revise this deliverable after discovery.

## Bottom Line

The current draft supports a clear architecture position: a constrained engineering-centered enclave with controlled interfaces to manufacturing and shared enterprise services is the most defensible path for a company with this profile. The final version of the deliverable should be issued only after discovery confirms where controlled data lives, who touches it, and which shared services materially support it.
