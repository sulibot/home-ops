version: 1
config:
  - type: physical
    name: ens18
    mtu: ${network.mtu}
    subnets:
      - type: static
        address: ${network.ipv4_address}
        netmask: ${network.ipv4_netmask}
        gateway: ${network.ipv4_gateway}
      - type: static6
        address: ${network.ipv6_address}/${network.ipv6_prefix}
        gateway: ${network.ipv6_gateway}
  - type: nameserver
    address:
%{ for dns in dns_servers ~}
      - ${dns}
%{ endfor ~}
