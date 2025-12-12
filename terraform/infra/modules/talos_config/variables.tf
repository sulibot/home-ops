variable "cilium_values_path" {
  description = "Path to Cilium Helm values file"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
}

variable "cluster_id" {
  description = "Numeric cluster identifier"
  type        = number
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint (e.g., https://[fd00:101::10]:6443)"
  type        = string
}

variable "talos_version" {
  description = "Talos version (e.g., v1.11.5)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g., v1.31.4)"
  type        = string
}

variable "vip_ipv6" {
  description = "Control plane VIP IPv6 address"
  type        = string
}

variable "vip_ipv4" {
  description = "Control plane VIP IPv4 address"
  type        = string
}

variable "all_node_ips" {
  description = "Map of all nodes with IP addresses (module will filter by type)"
  type = map(object({
    public_ipv4 = string
    public_ipv6 = string
    ip_suffix   = number
    # REMOVED - mesh network no longer needed for link-local migration
    # mesh_ipv4   = string
    # mesh_ipv6   = string
  }))
}

variable "pod_cidr_ipv6" {
  description = "IPv6 CIDR for pod network"
  type        = string
}

variable "pod_cidr_ipv4" {
  description = "IPv4 CIDR for pod network"
  type        = string
}

variable "service_cidr_ipv6" {
  description = "IPv6 CIDR for service network"
  type        = string
}

variable "service_cidr_ipv4" {
  description = "IPv4 CIDR for service network"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for cluster nodes"
  type        = list(string)
}

variable "kernel_args" {
  description = "Talos kernel arguments"
  type        = list(string)
  default     = []
}

variable "system_extensions" {
  description = "Talos system extensions (official only)"
  type        = list(string)
  default     = []
}

variable "install_disk" {
  description = "Disk to install Talos on"
  type        = string
  default     = "/dev/sda"
}

variable "installer_image" {
  description = "Custom Talos installer image (e.g., factory.talos.dev/installer/<schematic>:<version>)"
  type        = string
}

variable "region" {
  description = "Region identifier (injected by root terragrunt)"
  type        = string
  default     = "home-lab"
}
