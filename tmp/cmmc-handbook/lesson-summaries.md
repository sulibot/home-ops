# Lesson Summaries

Primary source:
- [`/Users/sulibot/Downloads/CMMC Class Handbook Clean.odg`](/Users/sulibot/Downloads/CMMC%20Class%20Handbook%20Clean.odg)
- extracted text: [`/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt`](/Users/sulibot/repos/github/home-ops/tmp/cmmc-handbook/handbook-pages-odg.txt)

## Lesson 1: Managing Risk within the Defense Supply Chain

PDF pages: 14-61

Summary:
- Introduces the defense supply chain threat environment and why cybersecurity obligations exist in contractor ecosystems.
- Frames the regulatory background for contractor handling of federal information, including `FCI`, `CUI`, and the related legal sources.
- Useful for understanding why a manufacturer can inherit security obligations even if it is not a software company.

Most useful for:
- regulatory framing
- contract-driven security obligations
- explaining why supply-chain manufacturers fall into scope

## Lesson 2: Handling Sensitive Information

PDF pages: 62-131

Summary:
- Distinguishes sensitive information categories and how they should be protected.
- Covers handling expectations, markings, access control concepts, segmentation, and practical protection measures.
- This lesson is one of the strongest bridges between policy language and architecture decisions.

Most useful for:
- `FCI` vs `CUI`
- data handling patterns
- access control and segmentation decisions

## Lesson 3: Ensuring Compliance through CMMC

PDF pages: 132-203

Summary:
- Explains the CMMC model structure, levels, ecosystem, and how assessments and self-assessments fit together.
- Clarifies that contract requirements determine the relevant CMMC level.
- Useful for understanding program context, expected level, and the difference between self-attestation and external assessment.

Most useful for:
- level determination context
- ecosystem roles
- readiness and assessment framing

## Lesson 4: Performing CCP Responsibilities

PDF pages: 204-227

Summary:
- Focuses on the role and behavior of a CCP rather than on technical architecture.
- Useful as context for how the handbook expects the practitioner to approach scoping, readiness, and professionalism.

Most useful for:
- role boundaries
- ethics
- expectation-setting for advisory work

## Lesson 5: Scoping Certification and Assessment Boundaries

PDF pages: 228-313

Summary:
- The most important lesson for enclave design.
- Defines scope, certification boundary, assessment boundary, host unit, supporting organizations, external service providers, and the core Level 2 asset categories.
- Establishes the justification for limiting scope with a dedicated enclave or security domain.

Most useful for:
- enclave architecture
- asset categorization
- certification boundary design
- SSP and network-diagram driven scoping

## Lesson 6: Preparing the OSC

PDF pages: 314-343

Summary:
- Focuses on organizational readiness, cybersecurity culture, and preparation for assessment.
- Reinforces the need for asset awareness, documentation, and realistic readiness evaluation before formal assessment.

Most useful for:
- implementation planning
- readiness review
- identifying documentation and process gaps

## Lesson 7: Determining and Assessing Evidence

PDF pages: 344-387

Summary:
- Explains the evidence an assessor will want to see and how the assessment guides are used.
- Bridges controls to artifacts, interviews, and testing.
- Critical for building the evidence package alongside the technical design.

Most useful for:
- SSP-driven planning
- evidence collection
- mapping controls to real artifacts

## Lesson 8: Implementing and Evaluating Level 1

PDF pages: 388-433

Summary:
- Covers Level 1 domains, gap analysis, and assessment considerations.
- Less central than Lesson 5 or Lesson 9 for a likely CUI/enclave project, but still useful for foundational control thinking.

Most useful for:
- foundational practices
- FCI-only environments
- basic assessment preparation

## Lesson 9: Identifying Level 2 Practices

PDF pages: 434-453

Summary:
- Introduces the Level 2 practice set aligned to `NIST SP 800-171`.
- The most important control-oriented lesson for a systems architect because it drives identity, access, logging, maintenance, incident response, and system protection design.

Most useful for:
- Level 2 control planning
- technical control implications
- architecture requirements

## Lesson 10: Working through an Assessment

PDF pages: 454-522

Summary:
- Covers the mechanics of assessment execution: roles, planning, conduct, reporting, and POA&M close-out.
- Useful once the boundary, controls, and evidence package have been drafted.

Most useful for:
- assessment preparation
- target scope submission
- remediation close-out expectations

## Priority Reading Order for Architecture Work

If the immediate deliverable is an enclave design:
1. Lesson 5
2. Lesson 9
3. Lesson 7
4. Lesson 6
5. Lesson 2
6. Lesson 3
