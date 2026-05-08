# CMMC Level 1 and Level 2 Task and Gap Review

This review compares three sources:

- `/Users/sulibot/repos/github/handy/CMMC Class Handbook.md`
- `/Users/sulibot/repos/github/handy/level_1/*.md`
- `/Users/sulibot/repos/github/handy/level_2/*.md`

The handbook is training and assessment-oriented. The `level_1` and `level_2` folders are implementation and evidence-oriented. Because of that, the main gaps are usually not "missing concepts" but "missing operational artifacts, ownership, and assessment-ready evidence."

## Level 1 Task List

Level 1 covers the six foundational domains represented in the `level_1` folder: `AC`, `IA`, `MP`, `PE`, `SC`, and `SI`.

### Foundation and Scope

- Confirm the in-scope environment that handles `FCI`.
- Create or validate the list of in-scope users, systems, devices, networks, and physical locations.
- Confirm who owns each Level 1 practice operationally.
- Define where Level 1 evidence will be stored and who maintains it.

### Access Control (`AC.L1`)

- Finalize the access control policy.
- Define authorized users and authorized devices.
- document role definitions and approved access levels.
- Validate system configuration settings that enforce access restrictions.
- Document external system access and VPN access rules.
- Control publicly posted or processed information on public systems.
- Maintain the list of authorized personnel and content review records.

### Identification and Authentication (`IA.L1`)

- Finalize the user identification policy.
- Maintain the list of system accounts and device identifiers.
- Finalize the authentication policy.
- Define password management procedures and required enforcement settings.
- Validate that unique identification and authentication are consistently implemented.

### Media Protection (`MP.L1`)

- Finalize the media disposal policy.
- Define media reuse procedures.
- Maintain disposal and sanitization logs.
- Validate that media containing `FCI` is sanitized or destroyed before disposal or reuse.

### Physical Protection (`PE.L1`)

- Finalize the physical access policy.
- Maintain authorized access lists and badge issuance records.
- Maintain visitor management procedures and access logs.
- Maintain the inventory of physical access devices.
- Validate visitor escorting, log retention, and badge control in practice.

### System and Communications Protection (`SC.L1`)

- Finalize network monitoring and segmentation policies.
- Maintain current network diagrams.
- Validate firewall and intrusion detection controls.
- Confirm external boundary protections for systems handling `FCI`.

### System and Information Integrity (`SI.L1`)

- Finalize patch management policy.
- Finalize antivirus and malicious code management policy.
- Maintain vulnerability scan reports, scan logs, update logs, and system scan logs.
- Validate timely flaw remediation and signature or engine updates.
- Confirm periodic scanning and real-time protection are actually operating.

### Assessment and Readiness

- Build a Level 1 control matrix mapping each artifact to its practice.
- Perform a Level 1 gap assessment against all 17 practices.
- Record remediation items for failed or partial controls.
- Prepare an attestation-ready evidence pack.

## Level 2 Task List

Level 2 expands coverage to all 14 domains and requires a much more formal policy, procedure, SSP, and evidence set.

### Program and Scope

- Finalize the SSP in `CMMC_L2_SSP_062025.md` with real system names, boundary, owners, data flows, and asset inventory.
- Define the `CUI` boundary and identify all in-scope assets, users, locations, and external services.
- Assign domain owners and evidence owners.
- Define the repository structure for policies, procedures, evidence, screenshots, exports, logs, and assessment notes.

### Existing Level 2 Policy and Procedure Families

The current `level_2` folder already contains templates for:

- `AU` Audit and Accountability
- `AT` Awareness and Training
- `CM` Configuration Management
- `IR` Incident Response procedure only
- `MA` Maintenance
- `PS` Personnel Security
- `RA` Risk Assessment
- `CA` Security Assessment

Tasks for these existing families:

- Tailor each template to the real environment.
- Remove non-applicable Level 3 language where present.
- Assign named roles and actual review cadence.
- Link procedures to operational systems and evidence sources.
- Approve and version-control the final policy and procedure set.

### Missing or Underrepresented Level 2 Families

The handbook teaches all 14 Level 2 domains, but the `level_2` folder does not currently include standalone implementation files for:

- `AC` Access Control
- `IA` Identification and Authentication
- `MP` Media Protection
- `PE` Physical Protection
- `SC` System and Communications Protection
- `SI` System and Information Integrity

It also appears to be missing:

- `IR` Incident Response policy

Tasks for these missing families:

- Create policy and procedure artifacts for each missing family.
- Map each family to the relevant `NIST SP 800-171` practices.
- Define implementation requirements, evidence expectations, and control owners.

### Technical and Operational Implementation

- Enforce least privilege, remote access control, and privileged account restrictions.
- Validate MFA, unique identity, and account lifecycle controls.
- Centralize audit logging and review audit events routinely.
- Define and enforce secure configuration baselines.
- Implement formal change management and security impact review.
- Validate incident reporting, escalation, and lessons-learned workflow.
- Operate a documented vulnerability, patching, and malicious code management program.
- Validate encryption, boundary protection, and secure communications for `CUI`.
- Validate physical access control, visitor handling, and alternate work site rules.
- Validate media handling, disposal, reuse, and transport controls.

### Evidence and Assessment Readiness

- Build a full Level 2 evidence index by practice.
- Build a POA&M or remediation tracker.
- Run a formal internal gap assessment against all 110 practices.
- Run a mock assessment using SSP, policies, procedures, and evidence.
- Close high-risk findings before third-party assessment activity.

## Handbook vs. Level 1 Folder

### What the handbook provides

- Conceptual explanation of Level 1 practices.
- Relationship between `FAR 52.204-21` and CMMC Level 1.
- Gap analysis and evidence concepts.
- Assessment-oriented context for applying the practices.

### What the `level_1` folder provides

- Templates and records for the six Level 1 domains.
- Policy skeletons and operational logs for many specific artifacts.
- Evidence-oriented files such as access lists, scan logs, and network diagrams.

### Gaps where the handbook covers more than the `level_1` folder

- No dedicated Level 1 evidence index or practice-to-artifact matrix.
- No explicit Level 1 gap analysis worksheet or readiness tracker.
- No explicit assessment-objective checklist tied to each Level 1 practice.
- No concise scope statement describing the in-scope `FCI` environment.
- No single owner matrix showing who is accountable for each artifact.

### Gaps where the `level_1` folder covers more than the handbook

- The folder contains concrete artifacts and templates the handbook does not provide.
- The folder provides evidence examples such as logs, lists, and diagrams not present in the handbook.

### Level 1 conclusion

The `level_1` folder has strong practice-level artifact coverage for the six required domains, but it still needs readiness packaging: scope, ownership, evidence mapping, and a formal gap assessment workflow.

## Handbook vs. Level 2 Folder

### What the handbook provides

- Conceptual explanation of all 14 Level 2 domains.
- Practice and assessment-objective context for Level 2.
- Assessment process context, roles, and workflow.

### What the `level_2` folder provides

- SSP template.
- Project-plan artifact.
- Policy and procedure templates for eight Level 2 families.

### Gaps where the handbook covers more than the `level_2` folder

- Handbook covers all 14 domains; folder only has dedicated files for eight families plus SSP.
- No standalone `AC`, `IA`, `MP`, `PE`, `SC`, or `SI` policy/procedure artifacts.
- No explicit `IR` policy file.
- No practice-by-practice evidence matrix.
- No POA&M or formal remediation register in the folder.
- No concrete evidence artifacts such as access review reports, log reviews, training completion records, patch reports, vulnerability results, or configuration baselines.
- No mock-assessment checklist or assessor-ready evidence binder structure.

### Gaps where the `level_2` folder covers more than the handbook

- The folder gives you editable policy/procedure starting points and an SSP template.
- The folder is closer to implementation artifacts, even though many are still generic templates.

### Level 2 conclusion

The handbook provides the assessment and conceptual model for Level 2, but the `level_2` folder is still incomplete as an implementation package. It needs missing domain documentation, environment-specific tailoring, and a large amount of operational evidence before it is assessment-ready.

## Priority Next Steps

### Level 1

1. Finalize all six domain artifacts and replace template language with environment-specific content.
2. Build a Level 1 evidence index mapped to the 17 practices.
3. Define the in-scope `FCI` boundary and owner matrix.
4. Run a Level 1 gap assessment and open remediation items.

### Level 2

1. Finalize the SSP and actual Level 2 boundary.
2. Create missing family artifacts for `AC`, `IA`, `MP`, `PE`, `SC`, `SI`, and `IR` policy coverage.
3. Tailor all existing templates to the real environment and assign owners.
4. Build a Level 2 practice-by-practice evidence index and POA&M.
5. Run an internal mock assessment against all in-scope Level 2 practices.
