variable "cilium_values_path" {
  description = "Path to Cilium Helm values file"
  type        = string
  default     = ""
}

variable "cilium_version" {
  description = "Cilium CNI version to install"
  type        = string
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
    # GPU passthrough configuration (optional, for worker nodes)
    gpu_passthrough = optional(object({
      enabled     = bool                      # Enable GPU passthrough for this node
      pci_address = string                    # PCI address of GPU (from cluster_core hostpci config)
      driver      = optional(string, "i915")  # Kernel driver (i915, amdgpu, nvidia, etc.)
      # Driver-specific parameters
      driver_params = optional(map(string), {
        "enable_display" = "0"
        "enable_guc"     = "3"
        "force_probe"    = "4680"
      })
    }))
  }))
}

variable "gua_prefix" {
  description = "IPv6 GUA (Global Unicast Address) prefix for internet connectivity (e.g., 2600:1700:ab1a:500e::). If not provided, only ULA will be configured."
  type        = string
  default     = ""
}

variable "gua_gateway" {
  description = "IPv6 GUA gateway address for internet access (e.g., 2600:1700:ab1a:500e::ffff). If not provided, ULA gateway will be used."
  type        = string
  default     = ""
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

variable "ntp_servers" {
  description = "NTP servers for time synchronization"
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

# BGP Configuration Variables
variable "bgp_asn_base" {
  description = "Base ASN for node BGP routing. Final ASN = base + (cluster_id * 1000) + node_suffix"
  type        = number
  # Default removed - should be provided by terragrunt from centralized config
  validation {
    condition     = var.bgp_asn_base >= 64512 && var.bgp_asn_base <= 4294967295
    error_message = "BGP ASN must be a valid private (64512-65535 or 4200000000-4294967295) or public ASN."
  }
}

variable "bgp_remote_asn" {
  description = "Upstream router BGP ASN (e.g., PVE FRR) - 4-byte ASN"
  type        = number
  # Default removed - should be provided by terragrunt from centralized config
  validation {
    condition     = var.bgp_remote_asn >= 1 && var.bgp_remote_asn <= 4294967295
    error_message = "BGP remote ASN must be between 1 and 4294967295."
  }
}

variable "bgp_interface" {
  description = "Network interface for BGP peering with upstream router"
  type        = string
  default     = "ens18"
}

variable "bgp_enable_bfd" {
  description = "Enable BFD (Bidirectional Forwarding Detection) for fast BGP failover"
  type        = bool
  default     = false
}

variable "bgp_advertise_loopbacks" {
  description = "Advertise node loopback addresses via BGP"
  type        = bool
  default     = false
}

variable "enable_i915" {
  description = "DEPRECATED: Use per-node gpu_passthrough configuration instead"
  type        = bool
  default     = false
}

# GPU driver configurations - centralized mappings for different GPU types
locals {
  gpu_driver_configs = {
    # Intel iGPU (Alder Lake and newer)
    i915 = {
      driver = "i915"
      kernel_params = {
        "enable_display" = "0"  # Disable display output to prevent boot stall
        "enable_guc"     = "3"  # Enable GuC/HuC firmware loading
        "force_probe"    = "*"  # Force probe for all Intel GPUs
      }
      kernel_args = [
        "i915.enable_display=0",
        "i915.enable_guc=3",
        "i915.force_probe=*"
      ]
    }
    # AMD GPU
    amdgpu = {
      driver = "amdgpu"
      kernel_params = {
        "dc"    = "1"  # Display Core
        "ppfeaturemask" = "0xffffffff"
      }
      kernel_args = [
        "amdgpu.dc=1",
        "amdgpu.ppfeaturemask=0xffffffff"
      ]
    }
    # NVIDIA GPU (requires proprietary extension)
    nvidia = {
      driver = "nvidia"
      kernel_params = {}
      kernel_args = [
        "nvidia-drm.modeset=1"
      ]
    }
  }
}

variable "machine_secrets" {
  description = "Existing Talos machine secrets to reuse; when set, secrets are not regenerated"
  type        = any
  default     = null
}

variable "client_configuration" {
  description = "Existing Talos client configuration to reuse with machine_secrets"
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  default = null
}
