# ansible/nat64

Jool (kernel NAT64) and TAYGA (userspace NAT64/DNS64) - not PVE hosts, pulled
out of `ansible/lae.proxmox` during the 2026-07-13 refactor as the first
real non-PVE ansible domain (see `.claude/plans/declarative-forging-volcano.md`).

```
ansible-playbook -i inventory/hosts.ini playbooks/nat64.yml
ansible-playbook -i inventory/hosts.ini playbooks/tayga.yml
```

Shares host-generic roles from `../common/roles/` the same way
`../pve/` does.
