# Level 1 Owner Matrix

## Purpose

Assign an accountable owner and supporting roles for each `CMMC Level 1` practice family and artifact type.

## Scope

- `AC`
- `IA`
- `MP`
- `PE`
- `SC`
- `SI`

## Team Assignments

- `Ryan Lin` - executive sponsor and final approver
- `Joshua Hornback` - primary implementation lead
- `Andy Volk` - business operations and compliance coordination lead
- `Sulaiman Ahmad` - SRE consultant, delivery coordinator, and automation support

## Matrix

| Domain | Artifact Types | Primary Owner | Supporting Owners | Dependencies |
| --- | --- | --- | --- | --- |
| AC | policy, user/device lists, access approvals, public posting controls | Joshua Hornback | Andy Volk, Sulaiman Ahmad | scope definition, system inventory |
| IA | identity policy, account inventory, authentication settings, password procedures | Joshua Hornback | Sulaiman Ahmad | directory and account inventory |
| MP | disposal policy, reuse procedures, disposal logs | Andy Volk | Joshua Hornback | media inventory, disposal process |
| PE | physical access policy, access logs, badge records, visitor controls | Andy Volk | Joshua Hornback, Ryan Lin | site access process |
| SC | network diagrams, segmentation policy, monitoring policy, boundary evidence | Joshua Hornback | Sulaiman Ahmad | current network architecture |
| SI | patching, scanning, antivirus, remediation evidence | Joshua Hornback | Sulaiman Ahmad | tooling access, reporting cadence |

## Steps

1. Confirm the named person filling each assigned role.
2. Record the system or process they own.
3. Link each owner to the Level 1 evidence they must maintain.
4. Review ownership quarterly or after major personnel changes.

## Expected Outputs

- Signed or approved owner matrix
- Updated contact list for Level 1 readiness work

## Evidence or Artifacts Created

- Owner matrix
- Review log or approval record

## Definition of Done

- Every Level 1 artifact has a primary owner.
- All owner assignments are approved by the program lead.
