terraform {
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.98.0, < 1.0.0"
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
  enabled = false

  lifecycle {
    ignore_changes = [
      forward_policy,
      input_policy,
      output_policy,
    ]
  }
}

# Allow xvrf interfaces for VRF-to-global routing.
# These rules permit the per-PVE /127 subnets on xvrf veth pairs.
resource "proxmox_virtual_environment_firewall_rules" "cluster_xvrf" {
  depends_on = [proxmox_virtual_environment_cluster_firewall.cluster]

  rule {
    type   = "in"
    action = "ACCEPT"
    iface  = "xvrf_evpnz1"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    iface  = "xvrfp_evpnz1"
  }
}
