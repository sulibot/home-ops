# Level 2 Gap Register

## Purpose

Track the meaningful `CMMC Level 2` gaps between the current `level_2` artifact set and an assessment-ready implementation package.

## Scope

- SSP completion
- Missing family coverage
- Evidence structure
- Readiness and mock assessment preparation

## Gaps

| Level | Gap Name | Why It Matters | Existing Files That Partially Cover It |
| --- | --- | --- | --- |
| L2 | SSP tailoring incomplete | The SSP anchors scope, boundary, ownership, and data flow | `level_2/CMMC_L2_SSP_062025.md` |
| L2 | Missing domain documentation | Several Level 2 families do not have standalone artifacts | handbook Level 2 content, `level_2/*.md` |
| L2 | Evidence index missing | 110 practices require traceable proof, not just templates | `level_2/*.md`, handbook evidence guidance |
| L2 | POA&M or remediation tracker missing | Deficiencies need a formal tracking mechanism before assessment | `CMMC_L2_ticket_backlog.csv` partially helps |
| L2 | Mock assessment checklist missing | Readiness must be tested before formal assessment work | handbook assessment-process sections |

## Definition of Done

- Each Level 2 gap is linked to a concrete prep or deliverable file.
- Each gap has an owner and a closure path.

## Team Use

- `Ryan Lin` approves major priority, scope, and residual-risk decisions.
- `Joshua Hornback` owns primary technical closure work.
- `Andy Volk` coordinates organizational, administrative, and staff-facing readiness work.
- `Sulaiman Ahmad` supports delivery tracking and sustainable automation.
