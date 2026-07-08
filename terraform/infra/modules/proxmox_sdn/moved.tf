moved {
  from = proxmox_virtual_environment_sdn_zone_evpn.main
  to   = proxmox_sdn_zone_evpn.main
}

moved {
  from = proxmox_virtual_environment_sdn_vnet.vnets
  to   = proxmox_sdn_vnet.vnets
}

moved {
  from = proxmox_virtual_environment_sdn_subnet.ipv4_subnets
  to   = proxmox_sdn_subnet.ipv4_subnets
}

moved {
  from = proxmox_virtual_environment_sdn_subnet.ula_subnets
  to   = proxmox_sdn_subnet.ula_subnets
}

moved {
  from = proxmox_virtual_environment_sdn_subnet.gua_subnets
  to   = proxmox_sdn_subnet.gua_subnets
}

moved {
  from = proxmox_virtual_environment_sdn_applier.main
  to   = proxmox_sdn_applier.main[0]
}
