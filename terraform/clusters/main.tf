# First cluster configuration
module "cluster1" {
  source = "./proxmox_vm_module"

  # Configuration for Cluster 1
  name_prefix         = "sol"
  cp_quantity         = 3
  cp_cpus             = 4
  cp_memory           = 8192
  cp_disk_size        = 30
  wkr_quantity        = 3
  wkr_cpus            = 4
  wkr_memory          = 8192
  wkr_disk_size       = 30
  template_vmid       = 9000
  datastore_id        = "local-zfs"
  file_id             = "local:iso/jammy-server-cloudimg-amd64.img"
  dns_server          = ["10.0.0.1", "fd00::1"]
  dns_domain          = "sulibot.com"
  vlan_id             = 101
  cp_octet_start      = 11
  wkr_octet_start     = 21
  ipv4_address_prefix = "10.10.101."
  ipv4_address_subnet = "24"
  ipv4_gateway        = "10.10.101.1"
  ipv6_address_prefix = "fd00:101::" 
  ipv6_address_subnet = "64"
  ipv6_gateway        = "fd00:101::1"
}

# Second cluster configuration (updated for the new IP prefix)
module "cluster2" {
  source = "./proxmox_vm_module"

  # Configuration for Cluster 2
  name_prefix           = "luna"
  cp_quantity           = 3
  cp_cpus               = 2
  cp_memory             = 4096
  cp_disk_size          = 20
  wkr_quantity          = 3
  wkr_cpus              = 2
  wkr_memory            = 4096
  wkr_disk_size         = 20
  template_vmid         = 9001
  datastore_id          = "local-zfs"
  file_id               = "local:iso/jammy-server-cloudimg-amd64.img"
  dns_server            = ["10.0.0.1", "fd00::1"]
  dns_domain            = "sulibot.com"
  vlan_id               = 102
  cp_octet_start        = 11
  wkr_octet_start       = 21
  ipv4_address_prefix   = "10.10.102."  # Updated prefix for IPv4
  ipv4_address_subnet   = "24"
  ipv4_gateway          = "10.10.102.1"
  ipv6_address_prefix   = "fd00:102::"  # Updated prefix for IPv6
  ipv6_address_subnet   = "64"
  ipv6_gateway          = "fd00:102::1"
}

