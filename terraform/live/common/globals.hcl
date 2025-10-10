locals {
  snippet_datastore_id = "resources"
  datastore_id         = "rdb-vm"
  default_tags         = ["managed-by=terraform", "environment=prod"]
  default_vm_specs = {
    cpus   = 4
    memory = "16Gi"
  }
}
