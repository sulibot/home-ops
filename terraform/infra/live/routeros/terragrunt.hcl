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
    local_asn       = local.network.routeros.local_asn # 4200000000
    router_id       = local.network.routeros.router_id # 10.255.0.254
    connection_name = "EDGE"
    pve_asn         = local.network.routeros.pve_asn        # 4200001000
    remote_range    = local.network.routeros.pve_range_ipv6 # fd00:0:0:ffff::/64
    local_address   = local.network.routeros.loopback_ipv6  # fd00:0:0:ffff::fffe
    # afi="ip,ipv6", use_bfd=true, hold_time="30s", keepalive_time="10s"
    # redistribute="connected,static,bgp", default_originate="always"
    # All above use module defaults — match prod exactly.
  }

  # ── FIREWALL ADDRESS LISTS ───────────────────────────────────────────────────
  # defconf: no_forward_ipv4 — referenced by forward chain drop rules
  address_lists = [
    { list = "no_forward_ipv4", address = "0.0.0.0/8", comment = "defconf: RFC6890" },
    { list = "no_forward_ipv4", address = "169.254.0.0/16", comment = "defconf: RFC6890" },
    { list = "no_forward_ipv4", address = "224.0.0.0/4", comment = "defconf: multicast" },
    { list = "no_forward_ipv4", address = "255.255.255.255", comment = "defconf: RFC6890" },
  ]

  # ── FIREWALL FILTER ──────────────────────────────────────────────────────────
  # defconf ruleset extracted from prod (rule 0 skipped — dynamic fasttrack counter).
  # List index = rule position on device.
  firewall_filter_rules = [
    {
      comment  = "defconf: accept ICMP after RAW"
      chain    = "input"
      action   = "accept"
      protocol = "icmp"
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

  # ── INTERFACE LISTS ──────────────────────────────────────────────────────────
  # Skip builtins: all, none, dynamic, static (IDs *2000000-*2000003).
  interface_lists = ["WAN", "LAN"]

  interface_list_members = [
    { list = "WAN", interface = "wan[ether1]" },
    { list = "LAN", interface = "br-fabric" },
    { list = "LAN", interface = "pve03[ether4]" },
    { list = "LAN", interface = "vlan10" },
    { list = "LAN", interface = "vlan30" },
    { list = "LAN", interface = "vlan31" },
    { list = "LAN", interface = "pve01[ether2]" },
    { list = "LAN", interface = "lo" },
    { list = "LAN", interface = "pve02[ether3]" },
    { list = "LAN", interface = "pve04[ether5]" },
    { list = "LAN", interface = "vlan200" },
    { list = "LAN", interface = "vlan1" },
    { list = "LAN", interface = "lo_dns" },
    { list = "LAN", interface = "wifi[ether6]" },
  ]

  # ── DNS GLOBAL SETTINGS ──────────────────────────────────────────────────────
  # Singleton — import ID "0". External-dns managed records (ttl=0s) are never touched.
  dns_settings = {
    allow_remote_requests  = true
    cache_max_ttl          = "1d"
    max_concurrent_queries = 200
    # set deduplicates — device shows "lo,lo" but provider normalises to unique members
    mdns_repeat_ifaces   = ["vlan30", "vlan200", "lo"]
    query_server_timeout = "3s"
    query_total_timeout  = "15s"
    servers              = ["2606:4700:4700::1111", "2606:4700:4700::1001", "1.1.1.1"]
  }

  # ── SYSTEM ────────────────────────────────────────────────────────────────────
  system = {
    identity             = "router"
    timezone             = "America/Los_Angeles"
    ntp_servers          = ["time.google.com", "time.cloudflare.com"]
    ntp_server_enabled   = true
    ntp_server_manycast  = true
    ntp_server_multicast = true
  }

  # ── IP / IPv6 SETTINGS ───────────────────────────────────────────────────────
  ip_settings = {
    icmp_rate_limit      = 100
    max_neighbor_entries = 16384
    send_redirects       = false
    tcp_syncookies       = true
  }

  ipv6_settings = {
    accept_redirects             = "no"
    accept_router_advertisements = "no"
    max_neighbor_entries         = 8192
  }

  # ── IP SERVICES ───────────────────────────────────────────────────────────────
  # Static (non-dynamic) services only. Import by service name (e.g. "ssh").
  ip_services = [
    { name = "ftp", port = 21, disabled = true },
    { name = "ssh", port = 22, address = "10.0.0.0/8,fd00::/8" },
    { name = "telnet", port = 23, disabled = true },
    { name = "www", port = 80, address = "0.0.0.0/0" },
    { name = "www-ssl", port = 443, address = "10.0.0.0/8,fd00::/8", certificate = "ssl-web-management" },
    { name = "winbox", port = 8291, address = "10.0.0.0/8,fd00::/8" },
    { name = "api", port = 8728, disabled = true },
    { name = "api-ssl", port = 8729, disabled = true },
  ]

  # ── IPv6 FIREWALL ADDRESS LISTS ───────────────────────────────────────────────
  ipv6_address_lists = [
    { list = "no_forward_ipv6", address = "fe80::/10", comment = "defconf: RFC6890 Linked-Scoped Unicast" },
    { list = "no_forward_ipv6", address = "ff00::/8", comment = "defconf: multicast" },
    { list = "NAT66-ULA", address = "fd00:100::/48", comment = "NAT66 ULA aggregate" },
    { list = "NAT66-ULA", address = "fd00:101::/48", comment = "NAT66 ULA aggregate" },
    { list = "NAT66-ULA", address = "fd00:102::/48", comment = "NAT66 ULA aggregate" },
    { list = "NAT66-ULA", address = "fd00:103::/48", comment = "NAT66 ULA aggregate" },
  ]

  # ── IPv6 FIREWALL FILTER RULES ────────────────────────────────────────────────
  # Rule 0 on device is dynamic fasttrack6 counter (D flag) — skipped.
  # Device indices 1-30 → TF keys 0-29.
  ipv6_firewall_filter_rules = [
    # 0 (*1E) — log rules for observability (no comment field, log-prefix only)
    { chain = "forward", action = "log", src_address = "fd00:101::/64", log_prefix = "VM_OUT" },
    # 1 (*1F)
    { chain = "forward", action = "log", src_address = "2600:1700:ab1a:500e::/64", log_prefix = "VM_GUA_OUT" },
    # 2 (*1D)
    { chain = "forward", action = "log", dst_address = "fd00:101::6/128", log_prefix = "TEST_TO_VM" },
    # 3 (*1B)
    { chain = "forward", action = "log", src_address = "2600:1700:ab1a:500e::/64", log_prefix = "TENANT_FWD" },
    # 4 (*1C)
    { chain = "forward", action = "log", dst_address = "2600:1700:ab1a:500e::/64", log_prefix = "TENANT_REPLY" },
    # 5 (*16)
    { chain = "forward", action = "fasttrack-connection", connection_state = "established,related", comment = "IPv6 fasttrack for performance" },
    # 6 (*1)
    { chain = "input", action = "accept", protocol = "icmpv6", comment = "defconf: accept ICMPv6 after RAW" },
    # 7 (*18)
    { chain = "forward", action = "accept", connection_state = "established,related,untracked", comment = "Accept established IPv6" },
    # 8 (*2)
    { chain = "input", action = "accept", connection_state = "established,related,untracked", comment = "defconf: accept established,related,untracked" },
    # 9 (*3)
    { chain = "input", action = "accept", protocol = "udp", dst_port = "33434-33534", comment = "defconf: accept UDP traceroute" },
    # 10 (*4)
    { chain = "input", action = "accept", protocol = "udp", src_address = "fe80::/10", dst_port = "546", comment = "defconf: accept DHCPv6-Client prefix delegation." },
    # 11 (*5)
    { chain = "input", action = "accept", protocol = "udp", dst_port = "500,4500", comment = "defconf: accept IKE" },
    # 12 (*6)
    { chain = "input", action = "accept", protocol = "ipsec-ah", comment = "defconf: accept IPSec AH" },
    # 13 (*7)
    { chain = "input", action = "accept", protocol = "ipsec-esp", comment = "defconf: accept IPSec ESP" },
    # 14 (*8)
    { chain = "input", action = "drop", in_interface_list = "!LAN", comment = "defconf: drop all not coming from LAN" },
    # 15 (*9)
    { chain = "forward", action = "accept", connection_state = "established,related,untracked", comment = "defconf: accept established,related,untracked" },
    # 16 (*A)
    { chain = "forward", action = "drop", connection_state = "invalid", comment = "defconf: drop invalid" },
    # 17 (*B)
    { chain = "forward", action = "drop", src_address_list = "no_forward_ipv6", comment = "defconf: drop bad forward IPs" },
    # 18 (*C)
    { chain = "forward", action = "drop", dst_address_list = "no_forward_ipv6", comment = "defconf: drop bad forward IPs" },
    # 19 (*D)
    { chain = "forward", action = "drop", protocol = "icmpv6", hop_limit = "equal:1", comment = "defconf: rfc4890 drop hop-limit=1" },
    # 20 (*E)
    { chain = "forward", action = "accept", protocol = "icmpv6", comment = "defconf: accept ICMPv6 after RAW" },
    # 21 (*F)
    { chain = "forward", action = "accept", protocol = "139", comment = "defconf: accept HIP" },
    # 22 (*10)
    { chain = "forward", action = "accept", protocol = "udp", dst_port = "500,4500", comment = "defconf: accept IKE" },
    # 23 (*11)
    { chain = "forward", action = "accept", protocol = "ipsec-ah", comment = "defconf: accept AH" },
    # 24 (*12)
    { chain = "forward", action = "accept", protocol = "ipsec-esp", comment = "defconf: accept ESP" },
    # 25 (*13)
    { chain = "forward", action = "accept", ipsec_policy = "in,ipsec", comment = "defconf: accept all that matches IPSec policy" },
    # 26 (*15)
    { chain = "forward", action = "accept", src_address = "fd00:10::/64", comment = "Allow PVE management network" },
    # 27 (*14)
    { chain = "forward", action = "drop", in_interface_list = "!LAN", comment = "defconf: drop everything else not coming from LAN" },
    # 28 (*19)
    { chain = "forward", action = "drop", connection_state = "invalid", comment = "Drop invalid IPv6" },
    # 29 (*1A)
    { chain = "input", action = "drop", src_address = "::/128", comment = "Drop unspecified IPv6" },
  ]

  # ── ROUTING FILTER RULES ──────────────────────────────────────────────────────
  routing_filter_rules = [
    { chain = "bgp-out", rule = "if (dst==0.0.0.0/0) { accept; }", comment = "Advertise IPv4 default to PVE" },
    { chain = "bgp-out", rule = "if (dst==::/0) { accept; }", comment = "Advertise IPv6 default to PVE" },
    { chain = "FROM-VM", rule = "if (dst in 10.255.101.0/24) { accept; }" },
    { chain = "TO-VM6", rule = "if (dst == ::/0) { accept; }" },
    { chain = "TO-VM", rule = "if (dst == 0.0.0.0/0) { accept; }" },
    { chain = "OSPF_OUT", rule = "if (dst==10.255.0.254/32) {accept}" },
  ]

  # BFD configurations: provider v1.99.0 validates addresses as plain IPs but
  # RouterOS BFD uses CIDR notation — provider bug, unmanageable for now.

  # ── DNS (static infra records only) ─────────────────────────────────────────
  # Only records with ttl=5m are managed here.
  # Records with ttl=0s are owned by Kubernetes external-dns — do NOT add them.
  dns_records = [
    { name = "pve01.sulibot.com", type = "AAAA", address = "fd00:10::1", ttl = "5m" },
    { name = "pve02.sulibot.com", type = "AAAA", address = "fd00:10::2", ttl = "5m" },
    { name = "pve03.sulibot.com", type = "AAAA", address = "fd00:10::3", ttl = "5m" },
    { name = "pve04.sulibot.com", type = "AAAA", address = "fd00:10::4", ttl = "5m" },
    # MinIO S3 object storage LXC (VLAN 200, pve02)
    { name = "minio.sulibot.com", type = "AAAA", address = "fd00:200::52", ttl = "5m" },
    { name = "minio.sulibot.com", type = "A", address = "10.200.0.52", ttl = "5m" },
    # VIP naming (front door) for LB failover/anycast work.
    { name = "kanidm-vip.sulibot.com", type = "AAAA", address = "fd00:100::60", ttl = "5m" },
    { name = "kanidm-vip.sulibot.com", type = "A", address = "10.100.0.60", ttl = "5m" },
    { name = "idm.sulibot.com", type = "AAAA", address = "fd00:100::60", ttl = "5m" },
    { name = "idm.sulibot.com", type = "A", address = "10.100.0.60", ttl = "5m" },
    { name = "idm01.sulibot.com", type = "AAAA", address = "fd00:100::61", ttl = "5m" },
    { name = "idm01.sulibot.com", type = "A", address = "10.100.0.61", ttl = "5m" },
    { name = "idm02.sulibot.com", type = "AAAA", address = "fd00:100::62", ttl = "5m" },
    { name = "idm02.sulibot.com", type = "A", address = "10.100.0.62", ttl = "5m" },
    { name = "idm03.sulibot.com", type = "AAAA", address = "fd00:100::63", ttl = "5m" },
    { name = "idm03.sulibot.com", type = "A", address = "10.100.0.63", ttl = "5m" },
    { name = "kanidm.sulibot.com", type = "AAAA", address = "fd00:100::60", ttl = "5m" },
    { name = "kanidm.sulibot.com", type = "A", address = "10.100.0.60", ttl = "5m" },
    # IPv4 A records — currently disabled on device, kept here for completeness
    { name = "pve01.sulibot.com", type = "A", address = "10.10.0.1", ttl = "5m", disabled = true },
    { name = "pve02.sulibot.com", type = "A", address = "10.10.0.2", ttl = "5m", disabled = true },
    { name = "pve03.sulibot.com", type = "A", address = "10.10.0.3", ttl = "5m", disabled = true },
  ]
}
