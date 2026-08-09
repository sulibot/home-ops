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
    # Infra/admin subnets only. Client VLANs (10.30/10.31) and the cluster LB
    # subnets (10.x.250.0/24) are deliberately excluded because application
    # clients use Cloudflare WARP for those private routes.
    # Consolidated into larger aggregates (2026-07-31) rather than one route
    # per /24 or /64 - fd00::/8 is this repo's entire ULA convention (every
    # tenant + infra + service VIP address lives inside it), so one route
    # covers all of them plus any future tenant/vnet with no update needed
    # here. 10.100.0.0/22 aggregates the tenant-100/101 primary /24s (also
    # covers the currently-unused but reserved 102/103 blocks) - the
    # loopback /24s (third octet 254) and the OpenBao VIP /32 don't share
    # that alignment so they stay separate. Deliberately NOT going to
    # 10.0.0.0/8 or fc00::/7 (the true maximal supersets) - too broad, would
    # risk colliding with a client's own home/hotel LAN using unrelated
    # 10.x space, with no benefit since nothing outside this fabric uses
    # either range anyway.
    advertise_routes = [
      "10.10.0.0/24",           # PVE management
      "10.100.0.0/22",          # tenant vnets 100-103 (100/101 in use, 102/103 reserved)
      "10.100.240.67/32",       # OpenBao routed service VIP
      "10.101.254.0/24",        # cluster-101 node loopbacks
      "10.104.0.0/24",          # cluster-104 nodes + API VIP
      "10.104.254.0/24",        # cluster-104 node loopbacks
      "10.200.0.0/24",          # tenant-200 LXCs (MinIO tf-state, zot)
      "10.255.0.0/24",          # infra loopbacks + DNS
      "10.99.99.0/30",          # ENG-453: OCI Phoenix WireGuard tunnel P2P
      "fd00::/8",               # entire ULA space - all tenants, infra, OpenBao VIP (v6)
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
      can(s.vip) ? { vip = s.vip } : {},
      name == "tail" ? { tailscale = local.tailscale_config } : {}
    )
  }
}
