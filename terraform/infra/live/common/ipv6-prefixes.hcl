# IPv6 Delegated Prefixes from AT&T
# These prefixes are delegated via DHCPv6-PD from AT&T to RouterOS
# and mapped to corresponding Proxmox SDN VNets
#
# When AT&T changes these prefixes, update this file and redeploy via:
#   cd ansible/lae.proxmox
#   ansible-playbook -i inventory/hosts.ini playbooks/configure-ipv6-gua.yml

locals {
  # AT&T delegated prefixes (current as of 2025-12-16)
  # Source: RouterOS DHCPv6-PD pools
  delegated_prefixes = {
    vnet100 = "2600:1700:ab1a:500e::/64"  # General Workloads (from wan6-v100)
    vnet101 = "2600:1700:ab1a:500d::/64"  # Talos Cluster 101 (from wan6-v101)
    vnet102 = "2600:1700:ab1a:500c::/64"  # Talos Cluster 102 (from wan6-v102)
    vnet103 = "2600:1700:ab1a:500b::/64"  # Talos Cluster 103 (from wan6-v103)
  }

  # Gateway addresses follow the ::ffff pattern
  # Example: 2600:1700:ab1a:500e::/64 -> gateway is 2600:1700:ab1a:500e::ffff
  delegated_gateways = {
    for vnet, prefix in local.delegated_prefixes :
    vnet => "${trimsuffix(prefix, "::/64")}::ffff"
  }
}
