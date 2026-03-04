locals {
  # Tenant VNets managed by SDN (explicitly includes vnet100 for Kanidm/services).
  tenant_ids = [100, 101, 102, 103]

  # Generate VNet definitions from tenant list
  vnets = { for tenant_id in local.tenant_ids : "vnet${tenant_id}" => {
    # ULA addressing
    ipv6_subnet = "fd00:${tenant_id}::/64"
    ipv4_subnet = "10.${tenant_id}.0.0/24"

    # Anycast gateway
    ipv6_gateway = "fd00:${tenant_id}::fffe"
    ipv4_gateway = "10.${tenant_id}.0.254"

    # VXLAN configuration
    vxlan_id = 10000 + tenant_id  # 10100, 10101, 10102, 10103

    # VLAN (for non-SDN deployments)
    vlan_id = tenant_id
  }}
}
