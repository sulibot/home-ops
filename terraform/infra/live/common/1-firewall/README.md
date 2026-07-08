# Proxmox Firewall

This stack adopts the live cluster firewall options and the xvrf inbound allow
rules used by the EVPN/VRF cross-connect path.

Current live posture:

- Cluster firewall is adopted but disabled.
- Two inbound rules allow `xvrf_evpnz1` and `xvrfp_evpnz1`.
- Provider policy defaults are ignored because Proxmox does not return those
  fields for the disabled cluster firewall in the imported state.

Do not enable the cluster firewall here without a separate maintenance window
and explicit host/VM rule review.
