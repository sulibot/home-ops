module "common" {
  source = "../common"
}

module "cluster1" {
  source                = "../proxmox_vm_module"
  name_prefix           = "sol"

  # Control Plane Configuration
  cp_quantity           = 3
  cp_cpus               = 4
  cp_memory             = 8192
  cp_disk_size          = 30

  # Worker Node Configuration
  wkr_quantity          = 8
  wkr_cpus              = 4
  wkr_memory            = 8192
  wkr_disk_size         = 30

  # Template and Datastore Configuration
  template_vmid         = 9000
  datastore_id          = module.common.local_datastore

  # Files and Cloud-init
  file_id               = "resources:iso/debian-12-backports-generic-amd64.img"
  user_data_file_id     = "resources:snippets/user-data-cloud-config.yaml"

  # DNS and Network Configuration
  dns_server            = module.common.local_dns_server
  dns_domain            = module.common.local_dns_domain
  vlan_id               = module.common.local_vlan_common["cluster-sol"]

  # IP Address Configuration
  cp_octet_start        = 11
  wkr_octet_start       = 21
  ipv4_address_prefix   = module.common.local_ip_config["cluster-sol"].ipv4_prefix
  ipv4_address_subnet   = "24"
  ipv4_gateway          = module.common.local_ip_config["cluster-sol"].ipv4_gateway
  ipv6_address_prefix   = module.common.local_ip_config["cluster-sol"].ipv6_prefix
  ipv6_address_subnet   = "64"
  ipv6_gateway          = module.common.local_ip_config["cluster-sol"].ipv6_gateway
}
