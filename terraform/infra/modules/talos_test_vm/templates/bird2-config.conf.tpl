# bird2 BGP daemon configuration for test VM ${hostname}
# Router ID uses the loopback (.254)
router id ${router_id};

# Logging
log syslog all;

# Device protocol - learns about network interfaces
protocol device {
  scan time 10;
}

# Direct protocol - imports directly connected routes
protocol direct {
  interface "dummy0", "lo";
  ipv4;
  ipv6;
}

# Kernel protocol for IPv4 - imports/exports routes from/to kernel
protocol kernel {
  ipv4 {
    import none;
    export filter {
      if proto = "cilium_sim" then reject;
      accept;
    };
  };
  merge paths on;
}

# Kernel protocol for IPv6
protocol kernel {
  ipv6 {
    import none;
    export filter {
      if proto = "cilium_sim" then reject;
      accept;
    };
  };
  merge paths on;
}

# BFD protocol
protocol bfd {
  interface "*" { multiplier 3; interval 300 ms; };
}

# BGP - GoBGP Cilium Simulation via localhost
# Mirrors production: bird2 is passive, GoBGP connects from ::1 (same as Cilium)
protocol bgp cilium_sim {
  description "GoBGP Cilium Simulation";
  passive on;
  multihop 2;
  local as ${local_asn};
  neighbor ::1 as ${gobgp_asn};

  ipv4 {
    import all;
    export none;  # One-way: GoBGP -> bird2
    extended next hop on;
  };

  ipv6 {
    import all;
    export none;
  };
}

# BGP - Upstream Peering (PVE ULA Anycast Gateway)
protocol bgp upstream {
  description "PVE ULA Anycast Gateway";
  local as ${local_asn};
  source address ${source_ipv6};
  neighbor ${upstream_peer} as ${upstream_asn};
  bfd on;

  ipv4 {
    import all;
    export filter {
      # Tag Loopbacks (protocol direct) as Public (Community :200) so PVE exports them to Edge
      if proto = "direct" then {
        bgp_large_community.add((${upstream_asn}, 0, 200));
        accept;
      }
      accept;
    };
    next hop self;
    extended next hop on;
  };

  ipv6 {
    import filter {
      # Reject the local node subnet - nodes use direct kernel routes
      if net = ${local_subnet_v6} then reject;
      accept;
    };
    export filter {
      if proto = "direct" then {
        bgp_large_community.add((${upstream_asn}, 0, 200));
        accept;
      }
      accept;
    };
    next hop self;
  };
}
