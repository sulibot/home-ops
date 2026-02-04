output "pci_mapping_names" {
  description = "Names of created PCI hardware mappings"
  value       = [for mapping in proxmox_virtual_environment_hardware_mapping_pci.pci : mapping.name]
}

output "usb_mapping_names" {
  description = "Names of created USB hardware mappings"
  value       = [for mapping in proxmox_virtual_environment_hardware_mapping_usb.usb : mapping.name]
}
