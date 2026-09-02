# PostgreSQL manifest variants

Flux reconciles `app-false/` during normal operation and `app-true/` only during
an explicitly enabled recovery. The unsubstituted `app/` directory is a
non-reconciled reference copy; it is retained for operator comparison and must
not be treated as a live path.

Any persistent operational change—backup schedules, verification, monitoring,
roles, or storage policy—must be kept identical across all three directories
unless the difference is explicitly part of the recovery contract. The live
`postgres-vectorchord` Flux Kustomization's `spec.path` is the authoritative way
to confirm which variant is active before a change is merged.
