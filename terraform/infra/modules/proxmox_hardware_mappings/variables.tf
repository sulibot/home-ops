variable "region" {
  description = "Region identifier (passed from root but not used)"
  type        = string
  default     = "home-lab"
}

variable "pci_mappings" {
  description = "List of PCI hardware mappings to create"
  type = list(object({
    name             = string
    comment          = optional(string)
    mediated_devices = optional(bool, false)
    maps = list(object({
      id           = string # Vendor:Product ID (e.g., "8086:56c1")
      node         = string # PVE node name (e.g., "pve01")
      path         = string # PCI path (e.g., "0000:00:02.1")
      comment      = optional(string)
      iommu_group  = optional(number)
      subsystem_id = optional(string)
    }))
  }))
  default = []
}

variable "usb_mappings" {
  description = "List of USB hardware mappings to create"
  type = list(object({
    name    = string
    comment = optional(string)
    maps = list(object({
      id      = string # Vendor:Product ID (e.g., "1a86:55d4")
      node    = string # PVE node name (e.g., "pve01")
      path    = optional(string)
      comment = optional(string)
    }))
  }))
  default = []
}
