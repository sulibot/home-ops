# LXC/VM service catalog - DERIVATION ADAPTER.
#
# Source of truth: site.yaml (repo root) -> site.json. Services are defined
# there by their deciding numbers only (tenant, suffix, node, size); this
# file computes everything else per the conventions in
# terraform/infra/ARCHITECTURE.md:
#
#   ipv4      = 10.<tenant>.0.<suffix>        (bare; ipv4_cidr adds /24)
#   ipv6      = fd00:<tenant>::<suffix>       (bare; ipv6_cidr adds /64)
#   vm_id     = tenant*1000 + suffix
#   gateways  = .254 / ::fffe
#   bridge    = vnet<tenant> (sdn) | vmbr0 + vlan <tenant> (vlan)
#
# `override:` on a site.yaml service entry replaces sizing fields.
# Exported shape per service: role, os, tenant_id, network{}, storage{},
# sizing{}, and (single-instance) node_name/hostname/vm_id/ipv4/ipv6/
# ipv4_cidr/ipv6_cidr or (multi-instance) instances{} of the same.

locals {
  site = jsondecode(file("${get_repo_root()}/site.json"))

  # Shared defaults for LXC-based service stacks.
  lxc_defaults = {
    provider_version = ">= 0.98.0, < 1.0.0"
    template_file_id = "resources:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    vm_datastore     = "rbd-vm"
  }

  tenant_network = {
    for tid, t in local.site.tenants : tid => {
      bridge       = t.mode == "sdn" ? "vnet${tid}" : "vmbr0"
      vlan_id      = t.mode == "vlan" ? tonumber(tid) : null
      ipv4_gateway = "10.${tid}.0.254"
      ipv6_gateway = "fd00:${tid}::fffe"
    }
  }

  # Tailscale behavior config stays here (HCL keeps the routing rationale
  # comments); identity/addressing comes from site.yaml like everyone else.
  tailscale_config = {
    tag                 = "tag:infra"
    advertise_exit_node = true
    # Infra/admin subnets only. Client VLANs (10.30/10.31) and the
    # cluster LB subnets (10.x.250.0/24) are deliberately excluded: apps
    # ride Cloudflare WARP, and the WARP managed-network probe
    # (10.3x.0.254:443) must never be reachable through this tunnel or
    # remote devices misdetect themselves as on the home network.
    advertise_routes = [
      "10.10.0.0/24",       # PVE management
      "10.100.0.0/24",      # tenant-100 service LXCs
      "fd00:100::/64",      # tenant-100 service LXCs (v6)
      "10.255.0.0/24",      # infra loopbacks + DNS
      "fd00:0:0:ffff::/64", # infra loopbacks + DNS (v6)
      "10.101.0.0/24",      # cluster-101 nodes + API VIP
      "10.101.254.0/24",    # cluster-101 node loopbacks
      "fd00:101::/64",      # cluster-101 nodes (v6)
      "10.104.0.0/24",      # cluster-104 nodes + API VIP
      "10.104.254.0/24",    # cluster-104 node loopbacks
      "fd00:104::/64",      # cluster-104 nodes (v6)
    ]
  }

  services = {
    for name, s in local.site.services : name => merge(
      {
        role      = s.role
        os        = try(s.os, "debian")
        tenant_id = tonumber(s.tenant)
        network   = local.tenant_network[tostring(s.tenant)]
        storage   = { vm_datastore = local.lxc_defaults.vm_datastore }
        sizing    = merge(local.site.sizes[s.size], try(s.override, {}))
      },
      can(s.suffix) ? {
        node_name = s.node
        hostname  = try(s.hostname, name)
        vm_id     = tonumber(s.tenant) * 1000 + s.suffix
        ipv4      = "10.${s.tenant}.0.${s.suffix}"
        ipv6      = "fd00:${s.tenant}::${s.suffix}"
        ipv4_cidr = "10.${s.tenant}.0.${s.suffix}/24"
        ipv6_cidr = "fd00:${s.tenant}::${s.suffix}/64"
      } : {},
      can(s.instances) ? {
        instances = {
          for iname, inst in s.instances : iname => {
            node_name = inst.node
            hostname  = try(inst.hostname, iname)
            vm_id     = tonumber(s.tenant) * 1000 + inst.suffix
            ipv4      = "10.${s.tenant}.0.${inst.suffix}"
            ipv6      = "fd00:${s.tenant}::${inst.suffix}"
            ipv4_cidr = "10.${s.tenant}.0.${inst.suffix}/24"
            ipv6_cidr = "fd00:${s.tenant}::${inst.suffix}/64"
          }
        }
      } : {},
      name == "tail" ? { tailscale = local.tailscale_config } : {}
    )
  }
}
