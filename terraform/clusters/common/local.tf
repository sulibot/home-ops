# clusters.tf - Shared Cluster Configuration Module

locals {
  dns_domain              = "sulibot.com"
  global_ipv4_dns_server = ["10.8.0.1"]
  global_ipv6_dns_server = ["fd00:8::1"]


  # Base prefixes for derived addressing
  ipv4_mesh_base_prefix   = "10.10"
  ipv4_egress_base_prefix = "10.20"
  ipv4_address_subnet     = "24"
  ipv6_mesh_base_prefix   = "fc00"
  ipv6_egress_base_prefix = "fd00"
  ipv6_address_subnet     = "64"

  # Base input per cluster
  clusters_base_info = {
    "cluster-101" = {
      cluster_id   = 101
      datastore_id = "local"
      egress_mtu   = 1500
      mesh_mtu     = 9000
    }
    "cluster-102" = {
      cluster_id   = 102
      datastore_id = "local"
      egress_mtu   = 1500
      mesh_mtu     = 9000
    }
    "cluster-103" = {
      cluster_id   = 103
      datastore_id = "local"
      egress_mtu   = 1500
      mesh_mtu     = 9000
    }
  }

  # Derived configuration per cluster
  clusters = {
    for key, cluster in local.clusters_base_info : key => {
      cluster_id              = cluster.cluster_id
      egress_vlan_id          = cluster.cluster_id
      mesh_vlan_id            = cluster.cluster_id  + 900
      egress_mtu              = cluster.egress_mtu
      mesh_mtu                = cluster.mesh_mtu

      ipv4_mesh_prefix        = "${local.ipv4_mesh_base_prefix}.${cluster.cluster_id}"
      ipv4_egress_prefix      = "${local.ipv4_egress_base_prefix}.${cluster.cluster_id}"
      ipv4_mesh_gateway       = "${local.ipv4_mesh_base_prefix}.${cluster.cluster_id}.254"
      ipv4_egress_gateway     = "${local.ipv4_egress_base_prefix}.${cluster.cluster_id}.254"
      ipv4_dns_server         = ["${local.ipv4_egress_base_prefix}.${cluster.cluster_id}.253"]

      ipv6_mesh_prefix        = "${local.ipv6_mesh_base_prefix}:${cluster.cluster_id}"
      ipv6_egress_prefix      = "${local.ipv6_egress_base_prefix}:${cluster.cluster_id}"
      ipv6_mesh_gateway       = "${local.ipv6_mesh_base_prefix}:${cluster.cluster_id}::fffd"
      ipv6_egress_gateway     = "${local.ipv6_egress_base_prefix}:${cluster.cluster_id }::fffe"
      ipv6_dns_server         = ["${local.ipv6_egress_base_prefix}:${cluster.cluster_id }::fffd"]


      ipv4_address_subnet     = local.ipv4_address_subnet
      ipv6_address_subnet     = local.ipv6_address_subnet
      global_ipv4_dns_server  = local.global_ipv4_dns_server
      global_ipv6_dns_server  = local.global_ipv4_dns_server
      dns_domain              = local.dns_domain
      datastore_id            = cluster.datastore_id

      loopback_ipv6_prefix    = "fc00:255:${cluster.cluster_id}" 
    }
  }
}

output "clusters" {
  value = local.clusters
}
locals {
  cluster = local.clusters[var.cluster_key]
}
