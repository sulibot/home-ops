terraform {
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.72"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

# Cluster-wide firewall configuration to whitelist xvrf interfaces
# This allows xvrf /127 cross-connect traffic to bypass SDN IPAM filtering
resource "proxmox_virtual_environment_cluster_firewall" "cluster" {
  enabled = true

  # Allow xvrf interfaces for VRF-to-global routing
  # These rules permit the per-PVE /127 subnets on xvrf veth pairs
  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Allow xvrf_evpnz1 (global side of VRF cross-connect)"
    iface   = "xvrf_evpnz1"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "Allow xvrfp_evpnz1 (VRF side of cross-connect)"
    iface   = "xvrfp_evpnz1"
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Allow xvrf_evpnz1 outbound"
    iface   = "xvrf_evpnz1"
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Allow xvrfp_evpnz1 outbound"
    iface   = "xvrfp_evpnz1"
  }
}
