# Executive Summary

This planning package uses the handbook source at [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg) and the extracted text at [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt) as the primary structured reference set, with the OCR PDF retained as a visual fallback.

## Current Working Assumption

The company likely has:
- standard Windows-based corporate IT
- engineering workstations and CAD workflows
- ERP / MRP supporting production
- CNC / CMM / test or other specialized manufacturing systems
- cloud-based identity and collaboration

If the company supports controlled aerospace or defense work, the most likely security challenge is not the office network itself. It is the spread of controlled technical data across engineering, collaboration, ERP, and manufacturing systems.

## Recommended Direction

The recommended design is a `bounded CUI enclave`:
- keep most general corporate IT outside the certification boundary
- place engineering and controlled technical workflows inside a dedicated logical enclave
- treat manufacturing and test systems as a connected but separately governed zone
- explicitly govern shared services such as identity, Microsoft 365, backup, EDR, SIEM, MSP tooling, and vendor access

This approach is more realistic and more defensible than trying to claim a narrow scope inside a mostly flat enterprise.

## Key Conclusions

- Scope follows the information.
- If systems that do not store `CUI` are not adequately isolated from systems that do, they can still become relevant to scope.
- ERP, collaboration platforms, and manufacturing programming systems are likely to determine how large the real scope becomes.
- Shared services and administrative paths are often some of the most important in-scope control providers.
- Evidence must be built as part of the design process, not collected at the end.

## Deliverables Created

The working set under [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/README.md`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/README.md) now includes:
- handbook text export and semantic structure
- lesson summaries and architecture interpretation
- asset classification matrix
- enclave boundary draft
- target-state architecture
- shared responsibility matrix
- evidence checklist
- implementation roadmap

## Immediate Decisions Needed

Leadership or project sponsors should answer these first:
- Does the company actually receive or generate `CUI`, `FCI`, export-controlled data, or all of the above?
- Which users and systems handle controlled engineering data today?
- Does ERP store controlled attachments, drawings, or work instructions?
- How are CNC/CMM/test systems supplied with engineering data?
- Which cloud, MSP, and vendor services have administrative reach into those systems?

## Bottom Line

For a company with this profile, the most defensible path is to design a constrained engineering-centered enclave with explicit interfaces to manufacturing and shared enterprise services. The quality of the eventual assessment outcome will depend less on generic security language and more on whether the company can prove the boundary, ownership model, data flows, and admin controls are real.
