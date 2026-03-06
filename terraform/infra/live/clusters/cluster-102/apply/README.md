# Apply Talos Machine Configurations

`apply/` is the single runtime update path for cluster node machine configs.

## Workflow

```bash
cd ../config
terragrunt apply

cd ../apply
terragrunt apply
```

## Safety Defaults

- Apply mode: `staged_if_needing_reboot`
- Destroy safety: `reset = false`, `reboot = false`, `graceful = true`

The module exports resolved apply mode per node so operators can audit whether an update was applied as `auto` or staged behavior.

## Notes

- `bootstrap/` is separate and one-time for cluster creation.
- `patch/` execution path is retired.
