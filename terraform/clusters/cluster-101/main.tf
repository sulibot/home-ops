module "common" {
  source = "../common"
  cluster_key  = "cluster-101"
}

module "cluster1" {
  source                = "../proxmox_vm_module"

  cluster       = module.common.selected_cluster
  
  cluster_name           = "sol"


  vm_password_hashed = module.common.vm_password_hashed

  # Control Plane Configuration
  cp_quantity           = 1
  cp_cpus               = 4
  cp_memory             = 8192
  cp_disk_size          = 30

  # Worker Node Configuration
  wkr_quantity          = 1  
  wkr_cpus              = 4
  wkr_memory            = 8192
  wkr_disk_size         = 30

  # Template and Datastore Configuration
  template_vmid         = 9000
  datastore_id          = module.common.selected_cluster.datastore_id


  # Files and Cloud-init
  file_id               = "resources:iso/debian-12-backports-generic-amd64.img"
  user_data_file_id     = "resources:snippets/user-data-cloud-config.yaml"

  # IP Address Configuration
  cp_octet_start        = 11
  wkr_octet_start       = 21


}
