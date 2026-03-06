# Patch Stage Retired

`patch/` is intentionally retired as an execution path.

Use the single runtime update path:

1. `../config` -> `terragrunt apply`
2. `../apply` -> `terragrunt apply`

`apply/` uses Talos provider apply mode `staged_if_needing_reboot` by default to keep updates safe while reducing workflow complexity.
