# Proxmox HA

This stack adopts the live Proxmox VE 9 HA rule model and derives desired HA
resources/rules from enabled cluster catalogs.

`cluster-101` is currently restricted to `pve01` and `pve02`. pve03 is excluded
from the HA rule because the GPU-passthrough workers can fail there with missing
Intel iGPU VF PCI devices. Split GPU and non-GPU HA rules before reintroducing
pve03 for these HA-managed VMs.

Existing live objects:

- HA resources: `vm:101011`, `vm:101012`, `vm:101013`, `vm:101021`,
  `vm:101022`, `vm:101023`
- HA rule: `sol-k8s-nodes`

After this stack is adopted, avoid also managing the same HA objects through
`ha-manager` shell commands or the legacy Ansible HA group path.

`cluster_core` still accepts the old `proxmox_ha` input for compatibility, but
its legacy HA `null_resource` provisioners are no-ops. This stack is the source
of truth for HA.
