variable "template_name" {
  description = "Name of the template VM to create"
  type        = string
}

variable "template_vmid" {
  description = "Static VM ID to use for the template"
  type        = number
}

variable "node_name" {
  description = "Name of the Proxmox node to create the VM on"
  type        = string
}

variable "datastore_id" {
  description = "Target datastore ID where disk will be created"
  type        = string
}

variable "cloud_init_image_file_id" {
  description = "Proxmox storage path to the base image file (e.g. 'local:iso/debian.img')"
  type        = string
}

variable "user_data_file_id" {
  description = "Proxmox storage snippet ID for cloud-init user data"
  type        = string
}

variable "cpus" {
  description = "Number of virtual CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Size of the primary disk in GB"
  type        = number
  default     = 20
}

variable "dns_servers" {
  description = "List of DNS server IPv6 addresses"
  type        = list(string)
}

variable "dns_domain" {
  description = "DNS domain to set via cloud-init"
  type        = string
}

