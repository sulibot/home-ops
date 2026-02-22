terraform {
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.96"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

# Create PCI hardware mappings for GPU passthrough
resource "proxmox_virtual_environment_hardware_mapping_pci" "pci" {
  for_each = { for mapping in var.pci_mappings : mapping.name => mapping }

  name             = each.value.name
  comment          = try(each.value.comment, null)
  mediated_devices = try(each.value.mediated_devices, false)

  map = [
    for m in each.value.maps : {
      id           = m.id
      node         = m.node
      path         = m.path
      comment      = try(m.comment, null)
      iommu_group  = try(m.iommu_group, null)
      subsystem_id = try(m.subsystem_id, null)
    }
  ]
}

# Create USB hardware mappings for device passthrough
resource "proxmox_virtual_environment_hardware_mapping_usb" "usb" {
  for_each = { for mapping in var.usb_mappings : mapping.name => mapping }

  name    = each.value.name
  comment = try(each.value.comment, null)

  map = [
    for m in each.value.maps : {
      id      = m.id
      node    = m.node
      path    = try(m.path, null)
      comment = try(m.comment, null)
    }
  ]
}
