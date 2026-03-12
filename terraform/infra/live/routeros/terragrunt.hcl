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
    use_bfd         = false
    # afi="ip,ipv6", hold_time="30s", keepalive_time="10s"
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
      comment            = "Allow personal devices to reach IoT"
      chain              = "forward"
      action             = "accept"
      in_interface       = "vlan30"
      out_interface      = "vlan31"
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
    {
      comment       = "Allow SSDP discovery from personal to IoT"
      chain         = "forward"
      action        = "accept"
      protocol      = "udp"
      dst_port      = "1900"
      in_interface  = "vlan30"
      out_interface = "vlan31"
    },
    {
      comment       = "Allow SSDP discovery from IoT to personal"
      chain         = "forward"
      action        = "accept"
      protocol      = "udp"
      dst_port      = "1900"
      in_interface  = "vlan31"
      out_interface = "vlan30"
    },
    {
      comment       = "Allow IGMP between personal and IoT"
      chain         = "forward"
      action        = "accept"
      protocol      = "igmp"
      in_interface  = "vlan30"
      out_interface = "vlan31"
    },
    {
      comment       = "Allow IGMP between IoT and personal"
      chain         = "forward"
      action        = "accept"
      protocol      = "igmp"
      in_interface  = "vlan31"
      out_interface = "vlan30"
    },
    {
      comment      = "Block new IoT connections to personal devices"
      chain        = "forward"
      action       = "drop"
      in_interface = "vlan31"
      out_interface = "vlan30"
      connection_state = "new"
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
  bridges = [
    {
      name           = "br-fabric"
      comment        = "defconf"
      admin_mac      = "02:00:00:00:00:01"
      auto_mac       = false
      igmp_snooping  = true
      pvid           = 1
      protocol_mode  = "rstp"
      vlan_filtering = true
    },
    {
      name    = "lo_dns"
      comment = "DNS server loopback"
    },
  ]

  bridge_ports = [
    { bridge = "br-fabric", interface = "pve01[ether2]" },
    { bridge = "br-fabric", interface = "pve02[ether3]" },
    { bridge = "br-fabric", interface = "pve03[ether4]" },
    { bridge = "br-fabric", interface = "pve04[ether5]" },
    { bridge = "br-fabric", interface = "wifi[ether6]", pvid = 30 },
    { bridge = "br-fabric", interface = "ilom-pve03[ether7]" },
    { bridge = "br-fabric", interface = "spare[ether8]" },
  ]

  bridge_vlans = [
    {
      bridge   = "br-fabric"
      vlan_ids = ["10"]
      tagged   = ["br-fabric", "pve01[ether2]", "pve02[ether3]", "pve03[ether4]", "pve04[ether5]", "ilom-pve03[ether7]"]
    },
    {
      bridge   = "br-fabric"
      vlan_ids = ["1"]
      tagged   = ["br-fabric"]
      untagged = ["pve01[ether2]", "pve02[ether3]", "pve03[ether4]", "pve04[ether5]", "ilom-pve03[ether7]", "spare[ether8]"]
    },
    {
      bridge   = "br-fabric"
      vlan_ids = ["30"]
      tagged   = ["br-fabric", "pve01[ether2]", "pve02[ether3]", "pve03[ether4]", "pve04[ether5]", "spare[ether8]"]
      untagged = ["wifi[ether6]"]
    },
    {
      bridge   = "br-fabric"
      vlan_ids = ["31"]
      tagged   = ["br-fabric", "wifi[ether6]", "pve01[ether2]", "pve02[ether3]", "pve03[ether4]", "pve04[ether5]", "spare[ether8]"]
    },
    {
      bridge   = "br-fabric"
      vlan_ids = ["200"]
      tagged   = ["br-fabric", "pve01[ether2]", "pve02[ether3]", "pve03[ether4]", "pve04[ether5]", "ilom-pve03[ether7]", "spare[ether8]"]
    },
    {
      bridge   = "br-fabric"
      vlan_ids = ["100"]
      tagged   = ["br-fabric", "pve01[ether2]", "pve02[ether3]", "pve03[ether4]", "pve04[ether5]"]
    },
  ]

  vlan_interfaces = [
    { name = "vlan1", interface = "br-fabric", vlan_id = 1, comment = "Native VLAN - Untagged traffic" },
    { name = "vlan10", interface = "br-fabric", vlan_id = 10, comment = "Management/Infrastructure VLAN" },
    { name = "vlan30", interface = "br-fabric", vlan_id = 30, comment = "WiFi Client Network" },
    { name = "vlan31", interface = "br-fabric", vlan_id = 31, comment = "WiFi IoT Devices" },
    { name = "vlan100", interface = "br-fabric", vlan_id = 100, comment = "kanidm" },
    { name = "vlan200", interface = "br-fabric", vlan_id = 200, comment = "VM/Container Standard LAN" },
  ]

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
    mdns_repeat_ifaces   = ["vlan30", "vlan31"]
    query_server_timeout = "3s"
    query_total_timeout  = "15s"
    servers              = ["2606:4700:4700::1111", "2606:4700:4700::1001", "1.1.1.1"]
  }

  snmp = {
    enabled = true
    vrf     = "main"
  }

  snmp_communities = [
    {
      name        = "public"
      addresses   = ["10.101.224.0/20", "fd00:101:224::/60"]
      read_access = true
      security    = "none"
      write_access = false
      comment     = "Restricted to snmp-exporter pod CIDRs"
    },
  ]

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

  ipv4_addresses = [
    { address = "10.30.0.254/24", network = "10.30.0.0", interface = "vlan30", comment = "wifi" },
    { address = "10.31.0.254/24", network = "10.31.0.0", interface = "vlan31", comment = "wifi-iot" },
    { address = "10.255.0.53/32", network = "10.255.0.53", interface = "lo_dns" },
    { address = "10.10.0.254/24", network = "10.10.0.0", interface = "vlan10" },
    { address = "10.1.0.254/24", network = "10.1.0.0", interface = "vlan1" },
    { address = "10.0.10.254/24", network = "10.0.10.0", interface = "vlan10" },
    { address = "10.200.0.254/24", network = "10.200.0.0", interface = "vlan200", comment = "Standard VM LAN" },
    { address = "10.255.0.254/32", network = "10.255.0.254", interface = "lo" },
  ]

  ipv4_pools = [
    { name = "dhcp_pool_vlan30", ranges = ["10.30.0.11-10.30.0.239"] },
    { name = "dhcp_pool_vlan31", ranges = ["10.31.0.30-10.31.0.240"] },
    { name = "dhcp_pool_vlan9", ranges = ["10.0.9.230-10.0.9.250"] },
    { name = "dhcp_pool_vlan10", ranges = ["10.10.0.230-10.10.0.250"] },
    { name = "dhcp_pool16", ranges = ["10.0.9.200-10.0.9.253"] },
    { name = "dhcp_pool_vlan200", ranges = ["10.200.0.201-10.200.0.250"] },
  ]

  ipv4_dhcp_options = [
    { name = "domain-search", code = 119, value = "0x07'sulibot'0x03'com'0x0007'sulibot'0x05'local'0x00" },
    { name = "next-server", code = 66, value = "'10.0.9.254'" },
    { name = "boot-file-pxe-bios", code = 67, value = "0x756e64696f6e6c792e6b70786500" },
    { name = "boot-file-pxe-uefi", code = 67, value = "0x697078652e65666900" },
    { name = "bootfile-netbootxyz", code = 67, value = "'netboot.xyz.efi'" },
    { name = "next-server-netbootxyz", code = 66, value = "'10.0.9.254'" },
  ]

  ipv4_dhcp_option_sets = [
    { name = "domain-search-set", options = ["domain-search"] },
    { name = "boot-pxe-bios", options = ["boot-file-pxe-bios", "next-server"] },
    { name = "boot-pxe-uefi", options = ["boot-file-pxe-uefi", "next-server"] },
    { name = "netboot.xyz", options = ["bootfile-netbootxyz", "next-server-netbootxyz"] },
  ]

  ipv4_dhcp_servers = [
    {
      name            = "dhcp_vlan31"
      interface       = "vlan31"
      address_pool    = "dhcp_pool_vlan31"
      lease_time      = "30m"
      use_radius      = "no"
      use_reconfigure = false
    },
    {
      name            = "dhcp_vlan30"
      interface       = "vlan30"
      address_pool    = "dhcp_pool_vlan30"
      lease_time      = "30m"
      use_radius      = "no"
      use_reconfigure = false
      dhcp_option_set = "domain-search-set"
    },
    {
      name            = "dhcp_vlan200"
      interface       = "vlan200"
      address_pool    = "dhcp_pool_vlan200"
      lease_time      = "30m"
      use_radius      = "no"
      use_reconfigure = false
    },
    {
      name            = "dhcp_vlan10"
      interface       = "vlan10"
      address_pool    = "dhcp_pool_vlan10"
      lease_time      = "30m"
      use_radius      = "no"
      use_reconfigure = false
    },
  ]

  ipv4_dhcp_server_networks = [
    {
      address    = "10.10.0.0/24"
      gateway    = "10.10.0.254"
      dns_server = ["10.10.0.254"]
      domain     = "sulibot.com"
    },
    {
      address    = "10.30.0.0/24"
      gateway    = "10.30.0.254"
      dns_server = ["10.30.0.254"]
      domain     = "sulibot.com"
    },
    {
      address    = "10.31.0.0/24"
      gateway    = "10.31.0.254"
      dns_server = ["10.31.0.254"]
      domain     = "sulibot.com"
    },
    {
      address    = "10.200.0.0/24"
      gateway    = "10.200.0.254"
      dns_server = ["10.200.0.254"]
      domain     = "sulibot.com"
      comment    = "Standard VM LAN"
    },
  ]

  ipv4_dhcp_server_leases = [
    {
      address     = "10.10.0.53"
      mac_address = "44:B7:D0:D5:85:6B"
      client_id   = "1:44:b7:d0:d5:85:6b"
    },
    {
      address     = "10.30.0.5"
      mac_address = "14:D4:24:F5:AA:02"
      client_id   = "1:14:d4:24:f5:aa:2"
      server      = "dhcp_vlan30"
    },
    {
      address     = "10.30.0.1"
      mac_address = "90:09:D0:12:93:B7"
      client_id   = "1:90:9:d0:12:93:b7"
      server      = "dhcp_vlan30"
    },
  ]

  ospf_instances = [
    {
      name         = "PVE_UNDERLAY"
      version      = 2
      vrf          = "main"
      router_id    = "10.255.0.254"
      redistribute = ["connected"]
    },
    {
      name         = "PVE_UNDERLAY_V6"
      version      = 3
      vrf          = "main"
      router_id    = "10.255.0.254"
      redistribute = ["connected"]
    },
  ]

  ospf_areas = [
    {
      name     = "backbone"
      instance = "PVE_UNDERLAY"
      area_id  = "0.0.0.0"
      type     = "default"
    },
    {
      name     = "backbone_v6"
      instance = "PVE_UNDERLAY_V6"
      area_id  = "0.0.0.0"
      type     = "default"
    },
  ]

  ospf_interface_templates = [
    {
      area                = "backbone"
      interfaces          = ["vlan10"]
      instance_id         = 0
      type                = "broadcast"
      retransmit_interval = "5s"
      transmit_delay      = "1s"
      hello_interval      = "10s"
      dead_interval       = "40s"
      priority            = 128
      cost                = 1000
    },
    {
      area                = "backbone_v6"
      interfaces          = ["vlan10"]
      instance_id         = 0
      type                = "broadcast"
      retransmit_interval = "5s"
      transmit_delay      = "1s"
      hello_interval      = "10s"
      dead_interval       = "40s"
      priority            = 128
      cost                = 1000
    },
    {
      area                = "backbone"
      interfaces          = ["lo"]
      instance_id         = 0
      type                = "broadcast"
      retransmit_interval = "5s"
      transmit_delay      = "1s"
      hello_interval      = "10s"
      dead_interval       = "40s"
      priority            = 128
      cost                = 1
      passive             = true
    },
    {
      area                = "backbone_v6"
      interfaces          = ["lo"]
      instance_id         = 0
      type                = "broadcast"
      retransmit_interval = "5s"
      transmit_delay      = "1s"
      hello_interval      = "10s"
      dead_interval       = "40s"
      priority            = 128
      cost                = 1
      passive             = true
    },
    {
      area                = "backbone"
      interfaces          = ["lo_dns"]
      instance_id         = 0
      type                = "broadcast"
      retransmit_interval = "5s"
      transmit_delay      = "1s"
      hello_interval      = "10s"
      dead_interval       = "40s"
      priority            = 128
      cost                = 1
      passive             = true
    },
    {
      area                = "backbone_v6"
      interfaces          = ["lo_dns"]
      instance_id         = 0
      type                = "broadcast"
      retransmit_interval = "5s"
      transmit_delay      = "1s"
      hello_interval      = "10s"
      dead_interval       = "40s"
      priority            = 128
      cost                = 1
      passive             = true
    },
  ]

  ipv6_dhcp_clients = [
    {
      interface                     = "wan6-v31"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["default"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-v31"
      pool_prefix_length            = 64
    },
    {
      interface                     = "wan6-v200"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["default"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-v200"
      pool_prefix_length            = 64
    },
    {
      interface                     = "wan6-v10"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["default"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-v10"
      pool_prefix_length            = 64
      script                        = "update-nat66-on-prefix-change"
    },
    {
      interface                     = "wan6-vnet100"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["main:25"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-vnet100"
      pool_prefix_length            = 64
    },
    {
      interface                     = "wan6-vnet101"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["main:25"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-vnet101"
      pool_prefix_length            = 64
    },
    {
      interface                     = "wan6-vnet102"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["main:25"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-vnet102"
      pool_prefix_length            = 64
    },
    {
      interface                     = "wan6-vnet103"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["main:25"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-vnet103"
      pool_prefix_length            = 64
    },
    {
      interface                     = "wan6-v30"
      request                       = ["prefix"]
      accept_prefix_without_address = true
      add_default_route             = false
      default_route_tables          = ["default"]
      check_gateway                 = "none"
      use_peer_dns                  = false
      validate_server_duid          = true
      allow_reconfigure             = false
      pool_name                     = "pd-v30"
      pool_prefix_length            = 64
      script                        = "update-nat66-on-prefix-change"
    },
  ]

  ipv6_addresses = [
    {
      interface = "vlan10"
      address   = "fd00:10::fffe/64"
      advertise = true
    },
    {
      interface = "vlan10"
      from_pool = "pd-v10"
      address   = "::fffe"
      advertise = true
      comment   = "Gateway - Auto from PD"
    },
    {
      interface = "vlan30"
      address   = "fd00:30::fffe/64"
      advertise = true
    },
    {
      interface = "vlan30"
      address   = "fd00:30::/128"
      advertise = false
    },
    {
      interface = "vlan31"
      address   = "fd00:31::fffe/64"
      advertise = true
    },
    {
      interface = "vlan31"
      from_pool = "pd-v31"
      address   = "::fffe"
      advertise = true
      comment   = "Gateway - Auto from PD"
    },
    {
      interface = "vlan200"
      address   = "fd00:200::fffe/64"
      advertise = true
      comment   = "Standard VM LAN IPv6"
    },
  ]

  ipv6_neighbor_discovery = [
    {
      interface                     = "vlan10"
      advertise_dns                 = true
      advertise_mac_address         = true
      managed_address_configuration = false
      other_configuration           = true
      dns                           = "fd00:10::fffe"
      ra_delay                      = "3s"
      ra_interval                   = "3m20s-10m"
      ra_lifetime                   = "30m"
      ra_preference                 = "medium"
    },
    {
      interface                     = "vlan30"
      advertise_dns                 = true
      advertise_mac_address         = false
      managed_address_configuration = false
      other_configuration           = true
      dns                           = "fd00:30::fffe"
      ra_delay                      = "3s"
      ra_interval                   = "20s-1m"
      ra_lifetime                   = "30m"
      ra_preference                 = "medium"
    },
    {
      interface                     = "vlan31"
      advertise_dns                 = true
      advertise_mac_address         = true
      managed_address_configuration = false
      other_configuration           = true
      dns                           = "fd00:31::fffe"
      ra_delay                      = "3s"
      ra_interval                   = "3m20s-10m"
      ra_lifetime                   = "30m"
      ra_preference                 = "medium"
    },
    {
      interface                     = "vlan200"
      advertise_dns                 = true
      advertise_mac_address         = false
      managed_address_configuration = false
      other_configuration           = true
      dns                           = "fd00:200::fffe"
      ra_delay                      = "3s"
      ra_interval                   = "20s-1m"
      ra_lifetime                   = "30m"
      ra_preference                 = "medium"
    },
  ]

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
    { chain = "forward", action = "log", dst_address = "fd00:101::6/128", log_prefix = "TEST_TO_VM" },
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
    { name = "ap.sulibot.com", type = "AAAA", address = "fd00:30::1", ttl = "5m" },
    { name = "ap.sulibot.com", type = "A", address = "10.30.0.1", ttl = "5m" },
    { name = "printer.sulibot.com", type = "AAAA", address = "fd00:31::5", ttl = "5m" },
    { name = "printer.sulibot.com", type = "A", address = "10.31.0.5", ttl = "5m" },
    # IPv4 A records — currently disabled on device, kept here for completeness
    { name = "pve01.sulibot.com", type = "A", address = "10.10.0.1", ttl = "5m", disabled = true },
    { name = "pve02.sulibot.com", type = "A", address = "10.10.0.2", ttl = "5m", disabled = true },
    { name = "pve03.sulibot.com", type = "A", address = "10.10.0.3", ttl = "5m", disabled = true },
  ]
}
