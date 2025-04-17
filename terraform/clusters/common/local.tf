locals {
  dns_server  = ["fd00:8::1"]
  dns_domain  = "sulibot.com"
  datastore   = "local"

  vlan_common = {
    "cluster-sol"  = 101
    "cluster-luna" = 102

  }

  ip_config = {
    "cluster-sol" = {
      ipv4_prefix   = "10.10.101."
      ipv4_gateway  = "10.10.101.254"
      ipv6_prefix   = "fd00:101::"
      ipv6_gateway  = "fd00:101::fffd"
    }
        "cluster-luna" = {
      ipv4_prefix   = "10.10.102."
      ipv4_gateway  = "10.10.102.1"
      ipv6_prefix   = "fd00:102::"
      ipv6_gateway  = "fd00:102::1"
    }
  }
}
