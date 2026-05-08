# CMMC Level 1 and Level 2 Project Plan

This plan uses the current document set in `/Users/sulibot/repos/github/handy` as the starting evidence package. It is an implementation plan, not an assessor determination of compliance.

## 1. Executive and Program Manager View

### Objective

Build a defensible CMMC program that first establishes Level 1 hygiene for Federal Contract Information (FCI), then matures to Level 2 practices and evidence for Controlled Unclassified Information (CUI).

### What success looks like

- Scope is defined: system boundary, in-scope users, assets, locations, and data flows are documented in the SSP.
- Governance is active: named owners, approved policies, approved procedures, and a recurring review cadence exist.
- Technical controls are operating: identity, logging, change control, incident response, vulnerability/risk management, and protection of CUI are implemented and evidenced.
- Evidence is organized: screenshots, exports, tickets, training records, inventories, and review logs map cleanly to CMMC practices.
- Readiness is measurable: open gaps, planned remediation dates, and pre-assessment results are visible at all times.

### Delivery model

1. Foundation and scope
   Confirm enclave/system boundary, CUI/FCI handling, owners, and authoritative inventory in `CMMC_L2_SSP_062025.md`.
2. Baseline documentation
   Tailor and approve the current policy/procedure templates for AU, AT, CM, IR, MA, PS, RA, and CA.
3. Control implementation
   Implement or verify technical and administrative controls for all Level 1 and Level 2 practice families, including families not yet represented by separate files in this folder.
4. Evidence and remediation
   Collect objective evidence, log gaps, and close remediation items through tracked tickets.
5. Readiness review
   Run an internal assessment, finalize the SSP/POA&M set, and enter formal CMMC preparation.

### Recommended phases

| Phase | Duration | Goal | Primary Outputs |
| --- | --- | --- | --- |
| 0. Mobilize | 1-2 weeks | Establish scope, ownership, cadence | RACI, milestone plan, source-of-truth repo |
| 1. Define boundary | 2-3 weeks | Lock in assets, users, data flows, CUI paths | Updated SSP, inventory, diagrams |
| 2. Tailor documents | 2-4 weeks | Convert templates into organization-specific policies and procedures | Approved policy/procedure set |
| 3. Implement controls | 4-10 weeks | Close technical and operational gaps | Control changes, runbooks, evidence |
| 4. Validate | 2-3 weeks | Test readiness and resolve final issues | Internal assessment, POA&M, evidence index |

### Program steering points

- Weekly: risk, blockers, and ticket burn-down.
- Biweekly: document approvals and control owner reviews.
- Monthly: executive status on scope, evidence coverage, and readiness date.

### Management risks to watch

- SSP remains generic instead of reflecting the real environment.
- Policies are approved but not backed by operating procedures or evidence.
- Missing Level 2 families in the current folder are not assigned early.
- Logging, access control, and asset inventory are implemented inconsistently across systems.
- Evidence collection is deferred until late, creating avoidable assessment risk.

## 2. SRE Execution View

### SRE mission

Turn the document set into a working compliance operating model by tying each CMMC practice to:

- a system owner,
- a technical control or process,
- a repeatable evidence source,
- and a tracked remediation item if the control is incomplete.

### Operating structure

| Workstream | SRE focus | Seed files in this folder |
| --- | --- | --- |
| System definition | Boundary, inventory, diagrams, services, trust zones | `CMMC_L2_SSP_062025.md` |
| Logging and traceability | Audit events, retention, time sync, alerting | `AuditandAccountabilityPolicyLevel2v01a.md`, `AuditandAccountabilityProcedureLevel2v01a.md` |
| Training and personnel | Role-based training, access lifecycle, insider awareness | `AwarenessandTraining*.md`, `PersonnelSecurity*.md` |
| Change and configuration | Baselines, change control, least functionality | `ConfigurationManagement*.md`, `Maintenance*.md` |
| Risk and validation | Risk assessments, internal reviews, corrective actions | `RiskAssessment*.md`, `SecurityAssessment*.md` |
| Incident readiness | Detection, escalation, response workflow, lessons learned | `IncidentResponseProcedureLevel2-3v01a.md` |

### Practical sequence for the SRE lead

1. Rewrite the SSP first.
   Replace placeholders, define the enclave, identify CUI stores/flows, list systems, and name responsible roles.
2. Tailor policies and procedures second.
   Remove non-applicable levels, assign real roles, and describe the actual operating process rather than template language.
3. Build the missing family coverage.
   Add tracked work for AC, IA, MP, PE, SC, and SI because those families appear in the SSP but do not have standalone files in this folder.
4. Convert each control into evidence.
   For every practice, define the proof source: ticket, config export, screenshot, log sample, training record, inventory snapshot, or signed review.
5. Run a readiness cadence.
   Keep a living gap register, monthly control-owner attestations, and a pre-assessment review before claiming readiness.

### Definition of done for a Level 2 control area

- Policy exists and is approved.
- Procedure describes the actual operating steps.
- Technical implementation is deployed or the manual process is demonstrably followed.
- Evidence can be reproduced on demand.
- Exceptions and residual risk are logged and owned.

### Suggested tracking fields

- Ticket ID
- Practice family
- Task type: document, implementation, evidence, review
- Owner
- Target date
- Dependency
- Evidence location
- Status
- Risk if late

### Immediate next actions

1. Finalize the SSP boundary and inventory.
2. Approve tailored versions of the existing templates.
3. Open backlog tickets for missing Level 2 families and technical controls.
4. Stand up a single evidence index tied to the ticket list.
5. Schedule an internal mock assessment once high-risk tickets are closed.
