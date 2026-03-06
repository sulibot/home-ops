# Cluster Shared Context

This directory contains shared cluster stack context and artifact handoff files.

- `context.hcl`: shared defaults and centralized derivations used by cluster units.
- `artifacts-registry.json`: written by `terraform/infra/live/artifacts/registry` after apply.
- `artifacts-schematic.json`: written by `terraform/infra/live/artifacts/schematic` after apply.

Cluster `run-all` does not traverse `live/artifacts/*` dependencies. Refresh artifacts first,
then run cluster stacks.
