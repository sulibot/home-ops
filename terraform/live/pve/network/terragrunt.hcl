include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "${get_repo_root()}/terraform/modules/pve/network"
}

locals {
  globals = read_terragrunt_config(find_in_parent_folders("common/globals.hcl")).locals
  secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/live/common/secrets.sops.yaml"))
}

inputs = {
  # --- Proxmox auth (prefer token; fall back to user/pass if empty) ---
  pve_endpoint         = local.secrets.pve_endpoint
  pve_api_token_id     = local.secrets.pve_api_token_id
  pve_api_token_secret = local.secrets.pve_api_token_secret
  pve_username         = local.secrets.pve_username
  pve_password         = local.secrets.pve_password

  # --- Cluster nodes (names must match PVE node names exactly) ---
  nodes = [
    { name = "pve01", ssh_host = "root@pve01" },
    { name = "pve02", ssh_host = "root@pve02" },
    { name = "pve03", ssh_host = "root@pve03" },
  ]

  # run controller setup on this host (defaults to nodes[0] if "")
  primary_ssh_host = "root@pve01"

  # --- EVPN controller (PEER MODEL: set your RR/spine loopbacks here) ---
  sdn_controller = {
    id    = "evpn-ctrl"
    asn   = 65001
    peers = ["10.255.255.1","10.255.255.2"] # <-- replace with your real RR loopbacks
    # fabric intentionally omitted in peer model
  }

  # --- EVPN zones (per cluster id) ---
  configure_zones = true
  sdn_evpn_clusters = {
    "100" = { vrf_vxlan = 100, mtu = 8930 }
    "101" = { vrf_vxlan = 101, mtu = 8930 }
  }

  # --- VNets/Subnets (per cluster id) ---
  configure_vnets = true
  sdn_clusters = {
    "100" = {
      vnet_tag = 100
      v4_cidr  = "10.10.100.0/24"
      v6_cidr  = "fc00:100::/64"
    }
    "101" = {
      vnet_tag = 101
      v4_cidr  = "10.10.101.0/24"
      v6_cidr  = "fc00:101::/64"
    }
  }

  # --- Fabric creation toggle (peer model = false) ---
  configure_fabric = false
}
