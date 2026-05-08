# CMMC Functional Project Plan

This plan uses the materials in `/Users/sulibot/repos/github/handy` as the current source set. It is designed to help leadership understand the path to readiness and help an SRE-led delivery team execute the work.

The plan also assumes use of the following working files created to close current prep and deliverable gaps:

- `level_1/L1_gap_register.md`
- `level_1/L1_prep_owner_matrix.md`
- `level_1/L1_prep_evidence_index.md`
- `level_1/L1_prep_gap_assessment_tracker.md`
- `level_2/L2_gap_register.md`
- `level_2/L2_gap_missing_domain_artifacts.md`
- `level_2/L2_prep_evidence_index.md`
- `level_2/L2_prep_POAM_tracker.md`
- `level_2/L2_prep_mock_assessment_checklist.md`

## Team Roles

- `Ryan Lin` - Chief Executive Officer and executive sponsor. Ultimate approver and accountable owner for organizational commitment, resource alignment, and final compliance decisions.
- `Joshua Hornback` - Site Reliability Engineer and primary implementation lead. Responsible for hands-on technical execution, control implementation, system validation, and evidence generation.
- `Andy Volk` - Business Operations and Compliance Coordination Lead. Responsible for staff-facing coordination, administrative process ownership, documentation support, scheduling, and organizational follow-through required for readiness.
- `Sulaiman Ahmad` - SRE Consultant and delivery coordinator. Responsible for sprint coordination, workflow management, and targeted automation work that improves long-term supportability, repeatability, and operational sustainability.

## Plan Summary

- `Level 1` is primarily an `FCI` protection and evidence-packaging effort across six foundational domains.
- `Level 2` is a broader `CUI` program effort across all 14 domains and requires a formal SSP, tailored policies and procedures, operational controls, and a practice-level evidence set.
- The current repository has stronger artifact coverage for `Level 1` than `Level 2`.
- The largest current gap is not conceptual understanding. It is turning templates and training material into owner-assigned, environment-specific, assessment-ready evidence.

## Level 1

### Executive and Manager View

#### Objective

Achieve a defensible `CMMC Level 1` posture for systems handling `FCI` by finalizing the six required domain artifacts, validating that the controls operate in practice, and preparing an attestation-ready evidence pack.

#### Scope

- In-scope systems, users, devices, networks, and physical locations that store, process, or transmit `FCI`
- Six foundational domains already represented in `/Users/sulibot/repos/github/handy/level_1`
  - `AC`
  - `IA`
  - `MP`
  - `PE`
  - `SC`
  - `SI`

#### Milestones

| Milestone | Goal | Expected Outputs |
| --- | --- | --- |
| L1-1 Scope and ownership | Confirm what is in scope and who owns each practice | Scope statement, owner matrix, evidence repository structure |
| L1-2 Artifact finalization | Replace template language with real operating content | Finalized Level 1 policies, procedures, lists, logs, and diagrams |
| L1-3 Control validation | Confirm controls are actually operating | Config checks, scan outputs, access lists, visitor records, media records |
| L1-4 Gap assessment | Measure current status against all 17 practices | Level 1 gap assessment, remediation list |
| L1-5 Readiness package | Prepare for attestation or internal sign-off | Practice-to-evidence matrix, reviewed evidence pack, readiness summary |

#### Task Groups

- Scope and inventory
- Policy and procedure completion
- Technical control validation
- Evidence collection and normalization
- Gap remediation
- Readiness review

#### Dependencies

- Clear definition of the `FCI` boundary
- Named owners for each domain artifact
- Access to current configurations, logs, and inventories
- Agreement on where evidence is stored and versioned

#### Required Artifacts and Evidence

- Access control policy and authorized user/device lists
- Authentication policy and account inventory
- Media disposal policy, reuse procedures, and disposal logs
- Physical access policy, access logs, badge issuance records, and authorized access lists
- Network diagrams, segmentation policy, monitoring policy, and boundary control evidence
- Patch, antivirus, vulnerability, and scan records
- Practice-to-evidence matrix
- Level 1 gap assessment output
- `level_1/L1_prep_owner_matrix.md`
- `level_1/L1_prep_evidence_index.md`
- `level_1/L1_prep_gap_assessment_tracker.md`

#### Owners

- Ryan Lin - executive sponsor and final approver
- Joshua Hornback - primary implementation lead
- Andy Volk - business operations and compliance coordination lead
- Sulaiman Ahmad - SRE consultant, delivery coordinator, and automation support

#### Risks and Gaps

- The `level_1` folder has many artifact templates and examples, but no single evidence index.
- No explicit Level 1 owner matrix is present in the current materials.
- No standalone Level 1 readiness pack or assessment-objective checklist appears to exist.
- Some artifacts may still be generic templates rather than environment-specific records.

#### Definition of Done

- All 17 Level 1 practices are mapped to named owners and concrete evidence.
- All Level 1 artifacts are environment-specific and current.
- Gaps are either remediated or formally tracked.
- Leadership can review a concise readiness summary and understand residual risk.

### SRE Execution View

#### Objective

Convert the existing `level_1` artifacts into an operational compliance set that proves the six foundational domains are implemented for the in-scope `FCI` environment.

#### Execution Sequence

1. Define the `FCI` boundary and system list.
2. Build a control matrix from Level 1 practice to artifact to owner.
3. Finalize and tailor the existing `level_1` files.
4. Validate actual control operation on systems, networks, and physical processes.
5. Capture reproducible evidence for each practice.
6. Run a Level 1 gap assessment and close high-risk deficiencies.

#### Task Groups

##### `AC`

- Validate authorized users, authorized devices, role definitions, external access approvals, and public-posting controls.

##### `IA`

- Validate unique identity, account inventory, authentication settings, and password procedures.

##### `MP`

- Validate sanitization, disposal, reuse, and handling records for media containing `FCI`.

##### `PE`

- Validate physical access rules, visitor handling, badge control, and access log retention.

##### `SC`

- Validate network boundary controls, segmentation, and monitoring.

##### `SI`

- Validate patching, malicious code protection, update cadence, and scan evidence.

#### Required Evidence Structure

- One folder or index entry per practice
- Current artifact
- One or more operational proofs
- Owner
- Review date
- Gap or exception note where relevant

#### Tracking Guidance

- Track each Level 1 practice as `not started`, `drafted`, `implemented`, `evidenced`, or `ready`.
- Track failed validations separately from missing documents.
- Avoid treating a template as evidence unless it reflects the live environment.
- Use `level_1/L1_gap_register.md` to track the current gap set and `level_1/L1_prep_gap_assessment_tracker.md` to track remediation.

#### Level 1 SRE Risks

- Evidence may exist but not be traceable to a specific practice.
- Policies may describe intended state while systems remain unvalidated.
- Physical and media controls are often the least integrated with SRE-owned evidence and need explicit coordination.

#### Level 1 SRE Definition of Done

- Every Level 1 practice has a control owner, implementation proof, and evidence location.
- All remediation items have owners and target dates.
- An internal reviewer can trace any practice from requirement to artifact to proof without interpretation work.

## Level 2

### Executive and Manager View

#### Objective

Achieve a `CMMC Level 2` assessment-ready posture for systems handling `CUI` by finalizing the SSP, filling missing domain documentation, implementing or validating the 14-domain control set, and building a full practice-level evidence package.

#### Scope

- All systems, users, services, assets, locations, and data flows that store, process, or transmit `CUI`
- All 14 CMMC Level 2 domains
- Existing artifacts in `/Users/sulibot/repos/github/handy/level_2`

#### Milestones

| Milestone | Goal | Expected Outputs |
| --- | --- | --- |
| L2-1 Boundary and SSP | Define the real `CUI` environment | Tailored SSP, inventory, boundary narrative, data flows |
| L2-2 Documentation coverage | Complete policy and procedure coverage across all domains | Tailored policy/procedure set, missing family artifacts created |
| L2-3 Technical and operational control validation | Validate implementation of Level 2 controls | Config evidence, logs, reviews, training records, baselines |
| L2-4 Evidence and remediation | Build full evidence structure and close major gaps | Evidence index, POA&M, remediation tracker |
| L2-5 Mock assessment readiness | Test the package before external assessment activity | Internal readiness review, mock assessment findings, residual risk summary |

#### Task Groups

- SSP and scope definition
- Policy and procedure tailoring
- Missing family documentation creation
- Technical control implementation and validation
- Evidence collection and indexing
- Internal assessment and remediation

#### Dependencies

- Accurate `CUI` boundary definition
- Asset inventory and service inventory
- Assigned domain owners
- Availability of system admins, security tooling, and business process owners
- Agreement on document approval and evidence storage process

#### Required Artifacts and Evidence

- Tailored `CMMC_L2_SSP_062025.md`
- Tailored policy and procedure set for all 14 domains
- Audit reviews, training records, account reviews, vulnerability reports, change records, incident records, and configuration baselines
- Practice-by-practice evidence index
- POA&M or remediation register
- Mock assessment notes and closure evidence
- `level_2/L2_gap_register.md`
- `level_2/L2_gap_missing_domain_artifacts.md`
- `level_2/L2_prep_evidence_index.md`
- `level_2/L2_prep_POAM_tracker.md`
- `level_2/L2_prep_mock_assessment_checklist.md`

#### Owners

- Ryan Lin - executive sponsor and final approver
- Joshua Hornback - primary implementation lead
- Andy Volk - business operations and compliance coordination lead
- Sulaiman Ahmad - SRE consultant, delivery coordinator, and automation support

#### Risks and Gaps

- The `level_2` folder has templates for only a subset of Level 2 families.
- Missing standalone family coverage currently includes `AC`, `IA`, `MP`, `PE`, `SC`, and `SI`.
- `IR` appears to have a procedure but no matching policy artifact.
- No full practice-level evidence index is present.
- No POA&M or assessor-ready evidence binder structure is currently visible in the folder.

#### Definition of Done

- The SSP reflects the real environment and has named owners.
- All 14 Level 2 families are represented by tailored documentation and operational evidence.
- Control gaps are tracked and reduced to an acceptable residual-risk set.
- Leadership can review a concise readiness summary with scope, status, and known risks.

### SRE Execution View

#### Objective

Turn the current Level 2 materials from a template set into a traceable operating compliance program with clear ownership, real evidence, and mock-assessment readiness.

#### Current State from Repository Review

Existing Level 2 documentation already exists for:

- `AU`
- `AT`
- `CM`
- `MA`
- `PS`
- `RA`
- `CA`
- `IR` procedure
- `SSP`

Missing or incomplete documentation coverage appears to include:

- `AC`
- `IA`
- `MP`
- `PE`
- `SC`
- `SI`
- `IR` policy

Primary working files for closing these gaps:

- `level_2/L2_gap_missing_domain_artifacts.md`
- `level_2/L2_prep_evidence_index.md`
- `level_2/L2_prep_POAM_tracker.md`
- `level_2/L2_prep_mock_assessment_checklist.md`

#### Execution Sequence

1. Rewrite the SSP with real scope, architecture, inventory, and ownership.
2. Tailor all existing Level 2 policies and procedures to the live environment.
3. Create missing family artifacts and map them to relevant `NIST SP 800-171` practices.
4. Build a full practice-to-evidence matrix for all in-scope Level 2 practices.
5. Validate technical control operation and recurring review processes.
6. Run an internal mock assessment and remediate failures.

#### Task Groups

##### Scope and Architecture

- Define boundary, trust zones, services, users, endpoints, and data flows.
- Align SSP narrative to actual systems and service dependencies.

##### Existing Family Tailoring

- Replace placeholders and generic language in `AU`, `AT`, `CM`, `MA`, `PS`, `RA`, `CA`, and `IR` procedure files.
- Add named roles, cadence, and evidence sources.

##### Missing Family Creation

- Create `AC`, `IA`, `MP`, `PE`, `SC`, and `SI` policy/procedure coverage.
- Add `IR` policy coverage to match the existing procedure.

##### Technical Validation

- Identity and privilege controls
- Logging and review
- Change control and baseline control
- Vulnerability, patching, and malware controls
- Encryption and protected communications
- Physical and media handling controls

##### Evidence and Tracking

- Build one evidence index row per practice
- Record owner, proof source, review date, and exceptions
- Track remediation separately from documentation drafting

#### Required Artifacts and Evidence

- SSP boundary, asset inventory, and diagrams
- Domain policies and procedures
- Control validation outputs
- Training completion records
- Access review records
- Audit review records
- Vulnerability and patching outputs
- Incident records and tabletop outputs
- POA&M or remediation tracker

#### Tracking Guidance

- Track Level 2 work by domain and by task type:
  - documentation
  - implementation
  - evidence
  - review
- Mark a task `ready` only when both implementation and evidence are present.
- Keep the SSP, evidence matrix, and remediation tracker synchronized.
- Use `level_2/L2_gap_register.md` as the source list of open structural gaps.

#### Level 2 SRE Risks

- Missing domain documentation can hide unowned control families.
- SSP drift will undermine every downstream assessment artifact.
- Control evidence is likely to be distributed across tools and teams unless indexed early.
- Manual or people-driven controls will fail assessment scrutiny if no recurring proof exists.

#### Level 2 SRE Definition of Done

- Every in-scope Level 2 practice has a mapped owner, implementation path, and evidence source.
- Missing family artifacts have been created and approved.
- High-risk gaps have been remediated or explicitly tracked in the POA&M.
- A mock assessment can be performed without inventing new evidence on the spot.

## Cross-Level Gap Summary

### Level 1 repository gaps

- No single Level 1 evidence index
- No explicit owner matrix
- No consolidated Level 1 gap assessment worksheet
- No attestation-ready package in one place

### Level 2 repository gaps

- Missing standalone documentation coverage for several Level 2 families
- No visible practice-level evidence index
- No visible POA&M or remediation log
- No assessor-ready evidence structure

## Recommended Immediate Next Steps

1. Approve the scope owner and evidence owner structure for both levels.
2. Complete the Level 1 control matrix and close the six-domain foundational gaps first.
3. Finalize the Level 2 SSP and create missing domain documentation immediately after Level 1 ownership is stable.
4. Stand up a single evidence index and remediation tracker that serve both levels.
5. Schedule Level 1 internal readiness review first, then Level 2 mock assessment once missing family coverage is complete.
