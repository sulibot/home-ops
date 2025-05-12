output "template_name" {
  description = "Name of the Proxmox VM template"
  value       = proxmox_virtual_environment_vm.template.name
}

output "template_vmid" {
  description = "VMID of the Proxmox VM template"
  value       = proxmox_virtual_environment_vm.template.vm_id
}

