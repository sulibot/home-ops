# Common variables for reuse across clusters
locals {
  dns_server  = ["10.0.0.1", "fd00::1"]
  dns_domain  = "sulibot.com"
  datastore   = "local-zfs"
  vlan_common = {
    cluster1 = 102
    cluster2 = 122
  }
  ip_config = {
    cluster1 = {
      ipv4_prefix = "10.10.102."
      ipv4_gateway = "10.10.102.1"
      ipv6_prefix = "fd00:102::"
      ipv6_gateway = "fd00:102::1"
    }
    cluster2 = {
      ipv4_prefix = "10.10.122."
      ipv4_gateway = "10.10.122.1"
      ipv6_prefix = "fd00:122::"
      ipv6_gateway = "fd00:122::1"
    }
  }
}

# Cluster 1 configuration
module "cluster1" {
  source                = "../proxmox_vm_module"
  name_prefix           = "luna"
  cp_quantity           = 3
  cp_cpus               = 4
  cp_memory             = 8192
  cp_disk_size          = 30
  wkr_quantity          = 3
  wkr_cpus              = 4
  wkr_memory            = 8192
  wkr_disk_size         = 30
  template_vmid         = 9000
  datastore_id          = local.datastore
  file_id               = "resources:iso/debian-12-backports-generic-amd64.img"
  user_data_file_id     = "resources:snippets/user-data-cloud-config.yaml"
  dns_server            = local.dns_server
  dns_domain            = local.dns_domain
  vlan_id               = local.vlan_common.cluster1
  cp_octet_start        = 11
  wkr_octet_start       = 21
  ipv4_address_prefix   = local.ip_config.cluster1.ipv4_prefix
  ipv4_address_subnet   = "24"
  ipv4_gateway          = local.ip_config.cluster1.ipv4_gateway
  ipv6_address_prefix   = local.ip_config.cluster1.ipv6_prefix
  ipv6_address_subnet   = "64"
  ipv6_gateway          = local.ip_config.cluster1.ipv6_gateway
}

# Cluster 2 configuration
#module "cluster2" {
#  source                = "./proxmox_vm_module"
#  name_prefix           = "luna"
#  cp_quantity           = 3
#  cp_cpus               = 2
#  cp_memory             = 4096
#  cp_disk_size          = 20
#  wkr_quantity          = 3
#  wkr_cpus              = 2
#  wkr_memory            = 4096
#  wkr_disk_size         = 20
#  template_vmid         = 9001
#  datastore_id          = local.datastore
#  file_id               = "resources:iso/debian-12-backports-generic-amd64.img"
#  user_data_file_id     = "resources:snippets/user-data-nocloud-config.yaml"
#  dns_server            = local.dns_server
#  dns_domain            = local.dns_domain
#  vlan_id               = local.vlan_common.cluster2
#  cp_octet_start        = 11
#  wkr_octet_start       = 21
#  ipv4_address_prefix   = local.ip_config.cluster2.ipv4_prefix
#  ipv4_address_subnet   = "24"
#  ipv4_gateway          = local.ip_config.cluster2.ipv4_gateway
#  ipv6_address_prefix   = local.ip_config.cluster2.ipv6_prefix
#  ipv6_address_subnet   = "64"
#  ipv6_gateway          = local.ip_config.cluster2.ipv6_gateway
#}
