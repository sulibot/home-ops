locals {
  # DNS configuration (centralized infrastructure)
  dns_servers = {
    ipv6 = "fd00:255::53"
    ipv4 = "10.255.0.53"
  }

  # NTP configuration (uses same infrastructure as DNS)
  ntp_servers = ["fd00:255::53"]

  # BGP configuration
  bgp = {
    asn_base            = 4210000000  # Base ASN for cluster ASN calculation
    remote_asn          = 4200001000  # RouterOS BGP ASN
    interface           = "ens18"     # Primary interface for BGP peering
    enable_bfd          = true        # BFD for fast failover
    advertise_loopbacks = true        # Advertise node loopbacks
  }

  # SDN configuration
  sdn = {
    zone_id   = "evpnz1"
    vrf_vxlan = 4096
    mtu       = 1450  # VXLAN overhead accounted
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
    public_ipv4_pattern = "10.0.%d."        # 10.0.101.

    # Loopback networks (shared infrastructure)
    loopback_ipv6_pattern = "fd00:255:%d::" # fd00:255:101::
    loopback_ipv4_pattern = "10.255.%d."    # 10.255.101.

    # Kubernetes network CIDRs (derived from cluster_id)
    pods_ipv4_pattern          = "10.%d.240.0/20"
    pods_ipv6_pattern          = "fd00:%d:240::/60"
    services_ipv4_pattern      = "10.%d.96.0/24"
    services_ipv6_pattern      = "fd00:%d:96::/112"
    loadbalancers_ipv4_pattern = "10.%d.27.0/24"
    loadbalancers_ipv6_pattern = "fd00:%d:1b::/120"
  }
}
