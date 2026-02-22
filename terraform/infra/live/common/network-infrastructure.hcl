locals {
  # Base domain for all infrastructure FQDNs
  base_domain = "sulibot.com"

  # DNS configuration (centralized infrastructure)
  dns_servers = {
    ipv6 = "fd00:0:0:ffff::53"
    ipv4 = "10.255.0.53"
  }

  # NTP configuration - use internal DNS server which also provides NTP
  ntp_servers = ["fd00:0:0:ffff::53", "10.255.0.53"]

  # BGP configuration
  bgp = {
    asn_base            = 4210000000  # Base ASN for cluster ASN calculation
    remote_asn          = 4200001000  # PVE FRR AS (what cluster nodes peer with upstream)
    interface           = "ens18"     # Primary interface for BGP peering
    enable_bfd          = true        # BFD for fast failover
    advertise_loopbacks = true        # Advertise node loopbacks
  }

  # RouterOS edge router — values extracted from live device 2026-02-22
  routeros = {
    local_asn      = 4200000000              # RouterOS eBGP AS ("EDGE_AS" in FRR templates)
    router_id      = "10.255.0.254"          # BGP router-id (infra loopback IPv4)
    loopback_ipv4  = "10.255.0.254"          # ROS infra loopback IPv4
    loopback_ipv6  = "fd00:0:0:ffff::fffe"   # ROS infra loopback IPv6
    pve_range_ipv6 = "fd00:0:0:ffff::/64"    # PVE infra loopback range (BGP listen range)
    pve_asn        = 4200001000              # PVE FRR AS (remote AS from ROS perspective)
  }

  # OCI pull-through registry cache (Zot, VLAN 200, pve02)
  # All registries use the same endpoint with overridePath=true so containerd
  # passes the full /v2/<registry>/image path through to Zot for namespace routing.
  registry_mirrors = {
    endpoint = "http://[fd00:200::51]:5000"
    registries = [
      "docker.io",
      "ghcr.io",
      "gcr.io",
      "mirror.gcr.io",
      "registry.k8s.io",
      "quay.io",
      "lscr.io",
      "public.ecr.aws",
      "factory.talos.dev",
    ]
  }

  # SDN configuration
  sdn = {
    zone_id                    = "evpnz1"
    vrf_vxlan                  = 4096
    mtu                        = 1450  # VXLAN overhead accounted
    disable_arp_nd_suppression = false
    advertise_subnets          = true
  }

  # IP addressing patterns
  addressing = {
    # VIP suffixes
    vip_ipv6_suffix = "::10"
    vip_ipv4_suffix = ".10"

    # VM ID calculation offsets
    controlplane_offset = 11  # CP nodes: {cluster_id}0{11,12,13}
    worker_offset       = 21  # Worker nodes: {cluster_id}0{21,22,23}

    # Subnet patterns (parameterized by cluster_id)
    # ULA (Unique Local Address) - fd00::/7
    public_ipv6_pattern = "fd00:%d::"       # fd00:101::
    public_ipv4_pattern = "10.%d.0."        # 10.101.0.

    # Loopback networks (VM loopbacks per tenant/cluster)
    loopback_ipv6_pattern = "fd00:%d:fe::" # fd00:101:fe::
    loopback_ipv4_pattern = "10.%d.254."    # 10.101.254.

    # Kubernetes network CIDRs (derived from cluster_id)
    pods_ipv4_pattern          = "10.%d.224.0/20"  # Supports 16 nodes with /24 per-node allocations
    pods_ipv6_pattern          = "fd00:%d:224::/60"
    services_ipv4_pattern      = "10.%d.96.0/24"
    services_ipv6_pattern      = "fd00:%d:96::/108"
    loadbalancers_ipv4_pattern = "10.%d.250.0/24"
    loadbalancers_ipv6_pattern = "fd00:%d:250::/112"
  }
}
