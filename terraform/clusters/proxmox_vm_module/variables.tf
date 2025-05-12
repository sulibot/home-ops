#variable "cluster_key" {
#  description = "Key to select the appropriate cluster configuration from common.clusters"
#  type        = string
#}

variable "cluster" {
  description = "Cluster config object for this environment"
  type        = any
}

variable "cluster_name" {
  description = "Prefix for VM names"
  type        = string
}

variable "cp_quantity" {
  description = "Number of control plane VMs"
  type        = number
}

variable "cp_cpus" {
  description = "Number of CPUs for control plane VMs"
  type        = number
}

variable "cp_memory" {
  description = "Memory (in MB) for control plane VMs"
  type        = number
}

variable "cp_disk_size" {
  description = "Disk size (in GB) for control plane VMs"
  type        = number
}

variable "wkr_quantity" {
  description = "Number of worker VMs"
  type        = number
}

variable "wkr_cpus" {
  description = "Number of CPUs for worker VMs"
  type        = number
}

variable "wkr_memory" {
  description = "Memory (in MB) for worker VMs"
  type        = number
}

variable "wkr_disk_size" {
  description = "Disk size (in GB) for worker VMs"
  type        = number
}

variable "template_vmid" {
  description = "Template VM ID to clone from"
  type        = number
}

variable "datastore_id" {
  description = "Datastore ID for storage"
  type        = string
}

variable "file_id" {
  description = "File ID for cloud-init image"
  type        = string
}

variable "user_data_file_id" {
  description = "File ID for cloud-init snippet"
  type        = string
  
}
#variable "dns_server" {
#  description = "List of DNS servers"
#  type        = list(string)
#}

#variable "dns_domain" {
#  description = "DNS domain name"
#  type        = string
#}

#variable "vlan_id" {
#  description = "vlan id"
#  type        = string
#}

#variable "ipv4_address_prefix" {
#  description = "IPv4 address prefix"
#  type        = string
#}

variable "cp_octet_start" {
  description = "Starting octet for control plane addresses"
  type        = number
}

variable "wkr_octet_start" {
  description = "Starting octet for worker addresses"
  type        = number
}

#variable "ipv4_address_subnet" {
#  description = "IPv4 address subnet"
#  type        = string
#}

#variable "ipv4_gateway" {
#  description = "IPv4 gateway address"
#  type        = string
#}

#variable "ipv6_address_prefix" {
#  description = "IPv6 address prefix"
#  type        = string
#}

#variable "ipv6_address_subnet" {
#  description = "IPv6 address subnet"
#  type        = string
#}

#variable "ipv6_gateway" {
#  description = "IPv6 gateway address"
#  type        = string
#}
