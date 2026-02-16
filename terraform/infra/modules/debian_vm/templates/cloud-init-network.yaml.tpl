version: 2
ethernets:
  eth0:
    dhcp4: false
    dhcp6: false
    addresses:
      - ${network.ipv4_address}/24
%{ if network.ipv6_address != null && network.ipv6_address != "" ~}
      - ${network.ipv6_address}/64
%{ endif ~}
    gateway4: ${network.ipv4_gateway}
%{ if network.ipv6_gateway != null && network.ipv6_gateway != "" ~}
    gateway6: ${network.ipv6_gateway}
%{ endif ~}
    nameservers:
      addresses: ${jsonencode(dns_servers)}
    mtu: ${network.mtu}
