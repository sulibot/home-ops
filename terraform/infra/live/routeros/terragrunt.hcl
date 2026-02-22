include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  versions = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  network  = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  creds    = yamldecode(sops_decrypt_file(find_in_parent_folders("common/secrets.sops.yaml")))
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        routeros = {
          source  = "terraform-routeros/routeros"
          version = "${local.versions.provider_versions.routeros}"
        }
      }
    }
    provider "routeros" {
      hosturl  = "${local.creds.routeros_hosturl}"
      username = "${local.creds.routeros_username}"
      password = "${local.creds.routeros_password}"
      insecure = true
    }
  EOF
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      backend "local" {}
    }
  EOF
}

terraform {
  source = "../../modules/routeros"
}

inputs = {
  # ── BGP ─────────────────────────────────────────────────────────────────────
  # Extracted from prod 2026-02-22.
  # Single dual-stack EDGE connection (not EDGE4/EDGE6 — see configure-routeros.sh which was never applied as-is).
  bgp = {
    instance_name   = "PVE_FABRIC"
    local_asn       = local.network.routeros.local_asn    # 4200000000
    router_id       = local.network.routeros.router_id    # 10.255.0.254
    connection_name = "EDGE"
    pve_asn         = local.network.routeros.pve_asn      # 4200001000
    remote_range    = local.network.routeros.pve_range_ipv6  # fd00:0:0:ffff::/64
    local_address   = local.network.routeros.loopback_ipv6   # fd00:0:0:ffff::fffe
    # afi="ip,ipv6", use_bfd=true, hold_time="30s", keepalive_time="10s"
    # redistribute="connected,static,bgp", default_originate="always"
    # All above use module defaults — match prod exactly.
  }

  # ── FIREWALL ADDRESS LISTS ───────────────────────────────────────────────────
  # defconf: no_forward_ipv4 — referenced by forward chain drop rules
  address_lists = [
    { list = "no_forward_ipv4", address = "0.0.0.0/8",       comment = "defconf: RFC6890" },
    { list = "no_forward_ipv4", address = "169.254.0.0/16",  comment = "defconf: RFC6890" },
    { list = "no_forward_ipv4", address = "224.0.0.0/4",     comment = "defconf: multicast" },
    { list = "no_forward_ipv4", address = "255.255.255.255", comment = "defconf: RFC6890" },
  ]

  # ── FIREWALL FILTER ──────────────────────────────────────────────────────────
  # defconf ruleset extracted from prod (rule 0 skipped — dynamic fasttrack counter).
  # List index = rule position on device.
  firewall_filter_rules = [
    {
      comment          = "defconf: accept ICMP after RAW"
      chain            = "input"
      action           = "accept"
      protocol         = "icmp"
    },
    {
      comment          = "defconf: accept established,related,untracked"
      chain            = "input"
      action           = "accept"
      connection_state = "established,related,untracked"
    },
    {
      comment           = "defconf: drop all not coming from LAN"
      chain             = "input"
      action            = "drop"
      in_interface_list = "!LAN"
    },
    {
      comment      = "defconf: accept all that matches IPSec policy"
      chain        = "forward"
      action       = "accept"
      ipsec_policy = "in,ipsec"
      disabled     = true
    },
    {
      comment            = "Allow inter-LAN traffic"
      chain              = "forward"
      action             = "accept"
      in_interface_list  = "LAN"
      out_interface_list = "LAN"
    },
    {
      comment          = "defconf: fasttrack"
      chain            = "forward"
      action           = "fasttrack-connection"
      connection_state = "established,related"
      hw_offload       = true
    },
    {
      comment          = "defconf: accept established,related, untracked"
      chain            = "forward"
      action           = "accept"
      connection_state = "established,related,untracked"
    },
    {
      comment          = "defconf: drop invalid"
      chain            = "forward"
      action           = "drop"
      connection_state = "invalid"
    },
    {
      comment              = "defconf:  drop all from WAN not DSTNATed"
      chain                = "forward"
      action               = "drop"
      connection_state     = "new"
      connection_nat_state = "!dstnat"
      in_interface_list    = "WAN"
    },
    {
      comment          = "defconf: drop bad forward IPs"
      chain            = "forward"
      action           = "drop"
      src_address_list = "no_forward_ipv4"
    },
    {
      comment          = "defconf: drop bad forward IPs"
      chain            = "forward"
      action           = "drop"
      dst_address_list = "no_forward_ipv4"
    },
  ]

  # ── FIREWALL NAT ─────────────────────────────────────────────────────────────
  firewall_nat_rules = [
    {
      chain              = "srcnat"
      action             = "masquerade"
      out_interface_list = "WAN"
    },
  ]

  # ── DNS (static infra records only) ─────────────────────────────────────────
  # Only records with ttl=5m are managed here.
  # Records with ttl=0s are owned by Kubernetes external-dns — do NOT add them.
  dns_records = [
    { name = "pve01.sulibot.com", type = "AAAA", address = "fd00:10::1", ttl = "5m" },
    { name = "pve02.sulibot.com", type = "AAAA", address = "fd00:10::2", ttl = "5m" },
    { name = "pve03.sulibot.com", type = "AAAA", address = "fd00:10::3", ttl = "5m" },
    { name = "pve04.sulibot.com", type = "AAAA", address = "fd00:10::4", ttl = "5m" },
    # IPv4 A records — currently disabled on device, kept here for completeness
    { name = "pve01.sulibot.com", type = "A", address = "10.10.0.1", ttl = "5m", disabled = true },
    { name = "pve02.sulibot.com", type = "A", address = "10.10.0.2", ttl = "5m", disabled = true },
    { name = "pve03.sulibot.com", type = "A", address = "10.10.0.3", ttl = "5m", disabled = true },
  ]
}
