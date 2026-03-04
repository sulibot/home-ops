output "containers" {
  value = {
    for name, c in proxmox_virtual_environment_container.this : name => {
      id          = c.id
      vm_id       = c.vm_id
      node_name   = c.node_name
      description = c.description
    }
  }
}
