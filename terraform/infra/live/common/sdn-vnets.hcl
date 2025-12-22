locals {
  # Active cluster IDs in the infrastructure
  active_clusters = [100, 101, 102, 103]

  # Generate VNet definitions from cluster list
  vnets = { for cluster_id in local.active_clusters : "vnet${cluster_id}" => {
    # ULA addressing
    ipv6_subnet = "fd00:${cluster_id}::/64"
    ipv4_subnet = "10.0.${cluster_id}.0/24"

    # Anycast gateway
    ipv6_gateway = "fd00:${cluster_id}::ffff"
    ipv4_gateway = "10.0.${cluster_id}.254"

    # VXLAN configuration
    vxlan_id = 10000 + cluster_id  # 10100, 10101, 10102, 10103

    # VLAN (for non-SDN deployments)
    vlan_id = cluster_id
  }}
}
