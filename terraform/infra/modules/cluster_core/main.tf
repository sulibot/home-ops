terraform {
  # Backend configuration will be injected by Terragrunt
  backend "local" {}

  required_providers {
    external = { source = "hashicorp/external", version = "~> 2.2" }
    proxmox  = { source = "bpg/proxmox", version = "~> 0.89.0" }
    sops     = { source = "carlpett/sops", version = "~> 1.3.0" }
  }
}

variable "region" {
  type        = string
  description = "Region identifier (injected by root terragrunt)"
  default     = "home-lab"
}

variable "cluster_id" {
  type        = number
  description = "The unique ID for the cluster, used for IP address calculations."
}

variable "proxmox" {
  description = "Proxmox storage + node defaults"
  type = object({
    datastore_id = string
    vm_datastore = string
    node_primary = string
    nodes        = list(string)
  })
}

variable "vm_defaults" {
  description = "Default VM sizing"
  type = object({
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
  })
}

variable "network" {
  description = "Default network wiring"
  type = object({
    bridge_public = string
    vlan_public   = number
    bridge_mesh   = string
    vlan_mesh     = number
    public_mtu    = optional(number, 1500)
    mesh_mtu      = optional(number, 1500)
    use_sdn       = optional(bool, false) # Enable SDN VNet bridges instead of VLAN-aware bridges
  })
}

variable "nodes" {
  description = "Cluster nodes definition"
  type = list(object({
    name          = string
    vm_id         = optional(number)
    ip_suffix     = number # Suffix for IP calculation
    control_plane = optional(bool, false)
    # Optional overrides for specific nodes
    node_name   = optional(string)
    cpu_cores   = optional(number)
    memory_mb   = optional(number)
    disk_gb     = optional(number)
    vlan_public = optional(number)
    vlan_mesh   = optional(number)
    public_mtu  = optional(number)
    mesh_mtu    = optional(number)
    # GPU passthrough configuration
    gpu_passthrough = optional(object({
      pci_address = string           # PCI address of GPU (e.g., "0000:00:02.0")
      pcie        = optional(bool, true)  # Use PCIe passthrough
      rombar      = optional(bool, true)  # Enable ROM BAR
      x_vga       = optional(bool, false) # Primary VGA (usually false for secondary GPU)
    }))
  }))
}

variable "ip_config" {
  description = "Configuration for generating node IP addresses"
  type = object({
    mesh = object({
      ipv6_prefix  = string
      ipv4_prefix  = string
      ipv6_gateway = optional(string)
      ipv4_gateway = optional(string)
    })
    public = object({
      ipv6_prefix  = string
      ipv4_prefix  = string
      ipv6_gateway = optional(string)
      ipv4_gateway = optional(string)
      gua_ipv6_prefix  = optional(string, "")  # GUA prefix for internet connectivity
      gua_ipv6_gateway = optional(string, "")  # GUA gateway
    })
    dns_servers = list(string)
  })
}

variable "talos_image_file_id" {
  description = "The Proxmox file ID of the uploaded Talos image (e.g., local:iso/talos-....img)"
  type        = string
}

variable "talos_version" {
  description = "Talos version (e.g., v1.8.2)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g., v1.31.4)"
  type        = string
  default     = "v1.31.4"
}

locals {
  # Cluster ID for SDN VNet naming (vnet${cluster_id})
  cluster_id = var.cluster_id

  # Generate full node configuration, including calculated IP addresses
  nodes = { for idx, node in var.nodes : node.name => merge(node, {
    index       = idx
    # REMOVED - mesh network no longer needed for link-local migration
    # mesh_ipv6   = format("%s%d", var.ip_config.mesh.ipv6_prefix, node.ip_suffix)
    # mesh_ipv4   = format("%s%d", var.ip_config.mesh.ipv4_prefix, node.ip_suffix)
    public_ipv6 = format("%s%d", var.ip_config.public.ipv6_prefix, node.ip_suffix)
    public_ipv4 = format("%s%d", var.ip_config.public.ipv4_prefix, node.ip_suffix)
    # GUA IPv6 address (if configured)
    gua_ipv6 = var.ip_config.public.gua_ipv6_prefix != "" ? format("%s::%d", trimsuffix(var.ip_config.public.gua_ipv6_prefix, "::/64"), node.ip_suffix) : ""
  }) }

  hypervisors = length(var.proxmox.nodes) > 0 ? var.proxmox.nodes : [var.proxmox.node_primary]

  # Kubernetes Network CIDRs (derived from cluster_id)
  # Aligned with IP addressing documentation:
  # - Pod CIDR: 10.<TID>.244.0/22 and fd00:<TID>:244::/60
  # - Service CIDR: 10.<TID>.96.0/24 and fd00:<TID>:96::/108
  # - LoadBalancer VIP Pool: 10.<TID>.240.0/24 and fd00:<TID>:fffe::/112
  k8s_network_config = {
    pods_ipv4          = format("10.%d.244.0/22", var.cluster_id)
    pods_ipv6          = format("fd00:%d:244::/60", var.cluster_id)
    services_ipv4      = format("10.%d.96.0/24", var.cluster_id)
    services_ipv6      = format("fd00:%d:96::/108", var.cluster_id)
    loadbalancers_ipv4 = format("10.%d.240.0/24", var.cluster_id)
    loadbalancers_ipv6 = format("fd00:%d:fffe::/112", var.cluster_id)
    talosVersion      = var.talos_version
    kubernetesVersion = var.kubernetes_version
  }
}

# Hardware mapping approach DISABLED due to bpg/proxmox provider bug
# The provider v0.89.0 removes the iommugroup parameter when creating/updating hardware mappings
# See: https://github.com/bpg/terraform-provider-proxmox/issues/886
#
# Instead, we use direct PCI ID passthrough via the hostpci.id parameter in the VM resource
# This requires root PAM credentials (already configured) and bypasses hardware mappings entirely

# Custom cloud-init user-data to configure sysctls during install phase
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  # Upload all cloud-init files to the primary node to avoid race conditions
  # The shared "resources" datastore makes files available to all nodes
  node_name = var.proxmox.node_primary

  source_raw {
    data = <<-EOT
      #cloud-config
      bootcmd:
        # Set sysctls for neighbor discovery and ARP notifications
        - sysctl -w net.ipv6.conf.all.accept_ra=0
        - sysctl -w net.ipv6.conf.default.accept_ra=0
        - sysctl -w net.ipv6.conf.ens18.accept_ra=0
        - sysctl -w net.ipv6.conf.all.ndisc_notify=1
        - sysctl -w net.ipv6.conf.default.ndisc_notify=1
        - sysctl -w net.ipv6.conf.ens18.ndisc_notify=1
        - sysctl -w net.ipv4.conf.all.arp_notify=1
        - sysctl -w net.ipv4.conf.default.arp_notify=1
        - sysctl -w net.ipv4.conf.ens18.arp_notify=1
    EOT

    file_name = "cloud-init-user-data-${each.value.name}.yml"
  }
}

# Custom cloud-init network configuration to assign multiple IPv6 addresses
# Proxmox's ipconfig only supports one IPv6 address, so we use custom user-data
# to configure both ULA and GUA addresses on the same interface
resource "proxmox_virtual_environment_file" "cloud_init_network_config" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  # Upload all cloud-init files to the primary node to avoid race conditions
  # The shared "resources" datastore makes files available to all nodes
  node_name = var.proxmox.node_primary

  source_raw {
    data = yamlencode({
      version = 1
      config = [
        {
          type = "physical"
          name = "ens18"  # Talos uses predictable interface naming, not eth0
          mtu = 1450  # VXLAN overhead (matches Proxmox VM network device and Talos config)
          subnets = concat(
            # IPv4 configuration
            [
              {
                type    = "static"
                address = each.value.public_ipv4
                netmask = "255.255.255.0"
                gateway = try(var.ip_config.public.ipv4_gateway, null)
              }
            ],
            # IPv6 ULA address + link-local default gateway (for installer reachability)
            [
              {
                type    = "static6"
                address = "${each.value.public_ipv6}/64"
                gateway = format("fe80::%d:fffe", var.cluster_id)
              }
            ],
            # IPv6 GUA address (if configured, no gateway - Talos machine config handles routing)
            each.value.gua_ipv6 != "" ? [
              {
                type    = "static6"
                address = "${each.value.gua_ipv6}/64"
              }
            ] : [],
            # IPv6 link-local (static for BGP peering)
            [
              {
                type    = "static6"
                address = "fe80::${var.cluster_id}:${each.value.ip_suffix}/64"
              }
            ]
          )
        },
        {
          type        = "nameserver"
          address     = var.ip_config.dns_servers
        }
      ]
    })

    file_name = "cloud-init-network-${each.value.name}.yml"
  }
}

resource "proxmox_virtual_environment_vm" "nodes" {
  for_each = local.nodes

  # Ensure cloud-init config files are fully uploaded before VM starts
  depends_on = [
    proxmox_virtual_environment_file.cloud_init_user_data,
    proxmox_virtual_environment_file.cloud_init_network_config
  ]

  vm_id = try(each.value.vm_id, null)
  name  = each.value.name
  node_name = coalesce(
    try(each.value.node_name, null),
    local.hypervisors[each.value.index % length(local.hypervisors)],
    var.proxmox.node_primary
  )

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf" # OVMF (UEFI) is the modern standard and preferred for Talos.

  # An EFI disk is required for UEFI boot. It stores the boot entries.
  # This disk should be on reliable, non-replicated storage if possible,
  # but using the same as the VM disk is also fine.
  efi_disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
  }

  cpu {
    sockets = 1
    cores   = coalesce(try(each.value.cpu_cores, null), var.vm_defaults.cpu_cores)
    type    = "host" # Pass through host CPU flags for best performance.
  }

  memory {
    dedicated = coalesce(try(each.value.memory_mb, null), var.vm_defaults.memory_mb)
  }

  # Boot disk that Talos will install to
  disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
    interface    = "scsi0"
    size         = coalesce(try(each.value.disk_gb, null), var.vm_defaults.disk_gb)
    cache        = "none"
    iothread     = true
    aio          = "io_uring"
  }

  # CD-ROM with Talos nocloud ISO
  cdrom {
    file_id   = var.talos_image_file_id
    interface = "ide0"
  }

  # net0 (ens18): Public/management network - used for Talos API and internet access
  # Uses SDN VNet bridge instead of VLAN-aware bridge
  network_device {
    bridge = coalesce(
      try(each.value.bridge_public, null),
      var.network.use_sdn ? "vnet${local.cluster_id}" : var.network.bridge_public
    )
    # No vlan_id when using SDN - VXLAN handles network segmentation
    vlan_id = var.network.use_sdn ? null : coalesce(try(each.value.vlan_public, null), var.network.vlan_public)
    # Reduced MTU to account for VXLAN overhead (50 bytes)
    mtu = var.network.use_sdn ? 1450 : try(each.value.public_mtu, var.network.public_mtu)
  }

  # REMOVED - mesh network no longer needed for link-local migration
  # net1 (ens19): Mesh network - used for internal cluster communication
  # network_device {
  #   bridge  = coalesce(try(each.value.bridge_mesh, null), var.network.bridge_mesh)
  #   vlan_id = coalesce(try(each.value.vlan_mesh, null), var.network.vlan_mesh)
  #   mtu     = try(each.value.mesh_mtu, var.network.mesh_mtu)
  # }


  # Use Cloud-Init to inject static IPs into the Talos installer environment.
  # This makes the node reachable at a predictable IP for `talosctl apply-config`.
  # Using custom network-config to support multiple IPv6 addresses (ULA + GUA + link-local)
  # since Proxmox's native ipconfig only supports one IPv6 address per interface.
  initialization {
    # Use the same datastore as the VM disk for Cloud-Init data.
    datastore_id = var.proxmox.vm_datastore

    # Reference the custom user-data and network configuration files
    user_data_file_id    = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id
    network_data_file_id = proxmox_virtual_environment_file.cloud_init_network_config[each.key].id
  }

  agent {
    # Enable QEMU Guest Agent for better VM management and monitoring
    enabled = true
    trim    = true
  }

  # VGA display for graphical console access via noVNC
  # Keep this as the default to maintain web UI console access
  vga {
    type = "std"
  }

  # GPU Passthrough (if configured for this node)
  # Using direct PCI ID instead of hardware mapping due to bpg/proxmox provider bug
  # with iommugroup parameter. This requires root PAM credentials (already configured).
  dynamic "hostpci" {
    for_each = each.value.gpu_passthrough != null ? [each.value.gpu_passthrough] : []
    content {
      device = "hostpci0"
      # Use raw PCI ID instead of mapping (requires root@pam credentials)
      id     = hostpci.value.pci_address
      pcie   = hostpci.value.pcie
      rombar = hostpci.value.rombar
      xvga   = hostpci.value.x_vga
    }
  }

  # Boot from disk first (Talos is installed), then CD-ROM
  boot_order = ["scsi0", "ide0"]
}

output "node_ips" {
  description = "Map of node names to their configured IP addresses"
  value = {
    for name, node in local.nodes : name => {
      # REMOVED - mesh network no longer needed for link-local migration
      # mesh_ipv4   = node.mesh_ipv4
      # mesh_ipv6   = node.mesh_ipv6
      public_ipv4 = node.public_ipv4
      public_ipv6 = node.public_ipv6
      ip_suffix   = node.ip_suffix
    }
  }
}

output "vm_names" {
  description = "List of VM names created"
  value       = keys(local.nodes)
}

output "talhelper_env" {
  description = "A map structured for generating a talenv.yaml file"
  value = { for n in local.nodes : n.name => {
    # Use the public network IP for Talos API and bootstrap access
    ipAddress    = n.public_ipv4
    hostname     = n.name
    publicIPv4   = n.public_ipv4
    publicIPv6   = n.public_ipv6
    # IPv4 gateway (static)
    publicGatewayIPv4 = try(var.ip_config.public.ipv4_gateway, null)
    # IPv6 gateway (link-local anycast per IP addressing documentation)
    # Format: fe80::<cluster_id>:fffe
    publicGatewayIPv6 = format("fe80::%d:fffe", var.cluster_id)
    publicMTU    = coalesce(try(n.public_mtu, null), var.network.public_mtu)
    endpoint     = "fd00:${var.cluster_id}::10" # Control Plane VIP (dual-stack with 10.${cluster_id}.0.10)
    # Determine the node role based on its name prefix
    controlPlane = substr(n.name, 4, 2) == "cp"
    # Node loopback addresses (VM identity per IP addressing documentation)
    # Format: 10.<TID>.254.<suffix> and fd00:<TID>:fe::<suffix>
    loopbackIPv4 = format("10.%d.254.%d", var.cluster_id, n.ip_suffix)
    loopbackIPv6 = format("fd00:%d:fe::%d", var.cluster_id, n.ip_suffix)
  } }
}

output "k8s_network_config" {
  description = "The Kubernetes network CIDRs for the current cluster."
  value       = local.k8s_network_config
}

output "talenv_yaml" {
  description = "YAML-formatted talenv configuration for talhelper"
  value = yamlencode(merge(
    {
      # Global cluster configuration
      clusterName       = "cluster-${var.cluster_id}"
      cluster_id        = var.cluster_id
      talosVersion      = var.talos_version
      kubernetesVersion = startswith(var.kubernetes_version, "v") ? var.kubernetes_version : "v${var.kubernetes_version}"
      endpoint          = "https://[fd00:${var.cluster_id}::10]:6443"

      # Network CIDRs from k8s_network_config
      pods_ipv4     = local.k8s_network_config.pods_ipv4
      pods_ipv6     = local.k8s_network_config.pods_ipv6
      services_ipv4 = local.k8s_network_config.services_ipv4
      services_ipv6 = local.k8s_network_config.services_ipv6

      # Gateway addresses
      # IPv4 gateway (static)
      public_gateway_ipv4 = var.ip_config.public.ipv4_gateway
      # IPv6 gateway (link-local anycast per IP addressing documentation)
      # Format: fe80::<cluster_id>:fffe
      public_gateway_ipv6 = format("fe80::%d:fffe", var.cluster_id)

      # DNS servers
      dns_server_ipv6 = length(var.ip_config.dns_servers) > 0 ? var.ip_config.dns_servers[0] : null
      dns_server_ipv4 = length(var.ip_config.dns_servers) > 1 ? var.ip_config.dns_servers[1] : null

      # Nodes array for talhelper template iteration
      nodes = [for n in local.nodes : {
        hostname         = n.name
        ipAddress        = n.public_ipv4
        controlPlane     = n.control_plane
        publicIPv4       = n.public_ipv4
        publicIPv6       = n.public_ipv6
        # IPv4 gateway (static)
        publicGatewayIPv4 = var.ip_config.public.ipv4_gateway
        # IPv6 gateway (link-local anycast per IP addressing documentation)
        publicGatewayIPv6 = format("fe80::%d:fffe", var.cluster_id)
        publicMTU        = coalesce(try(n.public_mtu, null), var.network.public_mtu)
        # Node loopback addresses (VM identity per IP addressing documentation)
        # Format: 10.<TID>.254.<suffix> and fd00:<TID>:fe::<suffix>
        loopbackIPv4     = format("10.%d.254.%d", var.cluster_id, n.ip_suffix)
        loopbackIPv6     = format("fd00:%d:fe::%d", var.cluster_id, n.ip_suffix)
      }]
    },
    # Flatten node properties as individual variables for envsubst
    # Use public IPs for bootstrap access (egress network is accessible)
    merge([for n in local.nodes : {
      "${replace(n.name, "-", "_")}_ipAddress"      = n.public_ipv4
      # REMOVED - mesh network no longer needed for link-local migration
      # "${replace(n.name, "-", "_")}_mesh_ipv4"      = n.mesh_ipv4
      # "${replace(n.name, "-", "_")}_mesh_ipv6"      = n.mesh_ipv6
      "${replace(n.name, "-", "_")}_public_ipv4"    = n.public_ipv4
      "${replace(n.name, "-", "_")}_public_ipv6"    = n.public_ipv6
    }]...)
  ))
}

output "talconfig_yaml" {
  description = "Complete talconfig.yaml for talhelper"
  value = yamlencode({
    clusterName = "cluster-${var.cluster_id}"
    talosVersion = var.talos_version
    kubernetesVersion = var.kubernetes_version
    endpoint = "https://[fd00:${var.cluster_id}::10]:6443"

    # Reference to secrets file
    secretsFile = "{{ .talos.env.dir }}/talsecret.sops.yaml"

    # Disable kube-proxy for Cilium
    proxy = {
      disabled = true
    }

    # Dual-stack networking
    clusterPodNets = [
      local.k8s_network_config.pods_ipv6,
      local.k8s_network_config.pods_ipv4
    ]
    clusterServiceNets = [
      local.k8s_network_config.services_ipv6,
      local.k8s_network_config.services_ipv4
    ]

    # Nodes - explicitly defined (no loops)
    nodes = [for n in local.nodes : {
      hostname = n.name
      ipAddress = n.public_ipv4
      controlPlane = n.control_plane
      installDisk = "/dev/sda"
      networkInterfaces = [{
        deviceSelector = {
          hardwareAddr = "*"
        }
        addresses = [
          "${n.public_ipv4}/24"
        ]
        routes = var.ip_config.public.ipv4_gateway != null ? [{
          network = "0.0.0.0/0"
          gateway = var.ip_config.public.ipv4_gateway
        }] : []
      }]
    }]

    # Machine-level configuration
    machine = {
      network = {
        nameservers = compact([
          length(var.ip_config.dns_servers) > 0 ? var.ip_config.dns_servers[0] : null,
          length(var.ip_config.dns_servers) > 1 ? var.ip_config.dns_servers[1] : null
        ])
      }
      kubelet = {
        extraArgs = {
          "eviction-hard" = "imagefs.available<5%,memory.available<500Mi,nodefs.available<5%"
        }
      }
      sysctls = {
        "fs.file-max" = "1000000"
        "fs.inotify.max_user_watches" = "524288"
        "net.netfilter.nf_conntrack_max" = "1048576"
        "net.core.somaxconn" = "32768"
        "net.ipv4.ip_forward" = "1"
        "net.ipv6.conf.all.forwarding" = "1"
      }
    }
  })
}
