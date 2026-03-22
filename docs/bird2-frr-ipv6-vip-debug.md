# Bird2/FRR IPv6 VIP Debug

Problem shape:
- local DNS resolves an HA hostname to the gateway IPv6 VIP
- IPv4 VIP works
- IPv6 VIP hangs

Root cause from this incident:
- Talos Bird2 was exporting the IPv6 LB pool
- upstream FRR initially filtered it because `PL_TENANT_V6` used `fd00:101::/48`
- that does not include `fd00:101:224::/60`, `fd00:101:250::/112`, or `fd00:101:fe::/64`

Fixed source:
- `/Users/sulibot/repos/github/home-ops/ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`
- `/Users/sulibot/repos/github/home-ops/ansible/lae.proxmox/roles/interfaces/templates/interfaces.pve.j2`
- tenant IPv6 defaults must be `/32`, not `/48`

Bird2 live inspection on Talos:
1. Find the Bird PID:
```bash
/opt/homebrew/bin/talosctl --talosconfig /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/talosconfig -n 10.101.0.11 processes | grep '/usr/local/sbin/bird -f'
```
2. Run `birdcl` from a node debug pod:
```bash
/opt/homebrew/bin/kubectl -n kube-system debug node/solcp01 -q --profile=sysadmin --image=alpine:3.20 -- \
  chroot /host/proc/<BIRD_PID>/root /usr/local/sbin/birdcl 'show route export upstream all'
```
3. Confirm the LB pool is exported:
- `fd00:101:250::/112`
- `fd00:101:250::11/128`
- `fd00:101:250::12/128`
- `fd00:101:250::120/128`

FRR verification on PVE:
```bash
ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 summary"'
ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 fd00:101:250::/112 json"'
ssh root@10.10.0.1 'vtysh -c "show route-map RM_VMS_IN_V6"'
```

Roll out FRR only:
```bash
cd /Users/sulibot/repos/github/home-ops/ansible/lae.proxmox
/opt/homebrew/bin/ansible-playbook -i inventory/hosts.ini playbooks/stage2-configure-frr.yml --limit 'pve01,pve02,pve03'
```

Final datapath check:
```bash
nc -vz fd00:101:250::11 443
curl -sk --resolve 'hass-app.sulibot.com:443:[fd00:101:250::11]' -D - https://hass-app.sulibot.com/
```

Expected success:
- `nc` succeeds
- `curl` returns `HTTP/2 200`
