
locals {
  # Separate control plane and worker nodes based on naming convention
  control_plane_nodes = {
    for name, ips in var.all_node_ips :
    name => merge(ips, { hostname = name }) if can(regex("cp[0-9]+$", name))
  }

  worker_nodes = {
    for name, ips in var.all_node_ips :
    name => merge(ips, { hostname = name }) if can(regex("wk[0-9]+$", name))
  }

  # Combine all nodes with metadata (ip_suffix comes from input, rename to node_suffix for clarity)
  all_nodes = merge(
    { for k, v in local.control_plane_nodes : k => merge(v, {
      machine_type = "controlplane"
      node_suffix  = v.ip_suffix
      # Centralize ASN calculation to avoid duplication and ensure consistency
      frr_asn      = var.bgp_asn_base + var.cluster_id * 1000 + v.ip_suffix
      cilium_asn   = 4220000000 + var.cluster_id * 1000 + v.ip_suffix
    }) },
    { for k, v in local.worker_nodes : k => merge(v, {
      machine_type = "worker"
      node_suffix  = v.ip_suffix
      frr_asn      = var.bgp_asn_base + var.cluster_id * 1000 + v.ip_suffix
      cilium_asn   = 4220000000 + var.cluster_id * 1000 + v.ip_suffix
    }) }
  )

  # Read Cilium values from Flux config for inline manifests
  # Use fileexists() to safely handle file reading - prevents "open : no such file or directory" errors
  cilium_values_yaml = var.cilium_values_path != "" && try(fileexists(var.cilium_values_path), false) ? file(var.cilium_values_path) : ""

  # Read Gateway API CRDs (required before Cilium if gatewayAPI.enabled: true)
  gateway_api_crds_path = var.cilium_values_path != "" ? "${dirname(dirname(dirname(var.cilium_values_path)))}/crds/gateway-api-crds/gateway-api-crds-v1.3.0-experimental.yaml" : ""
  # Use fileexists() to safely handle file reading
  gateway_api_crds      = local.gateway_api_crds_path != "" && try(fileexists(local.gateway_api_crds_path), false) ? file(local.gateway_api_crds_path) : ""

  # Common configuration to avoid repetition
  common_install = merge(
    {
      disk = var.install_disk
      wipe = false
    },
    var.installer_image != "" ? { image = var.installer_image } : {}
  )

  common_sysctls = {
    "fs.inotify.max_user_watches"   = "1048576"
    "fs.inotify.max_user_instances" = "8192"
    "fs.file-max"                   = "1000000"
    "net.core.somaxconn"            = "32768"
    "net.ipv4.ip_forward"           = "1"
    "net.ipv6.conf.all.forwarding"  = "1"
    # Neighbor Discovery and ARP notifications for faster network convergence
    "net.ipv6.conf.all.ndisc_notify"     = "1"
    "net.ipv6.conf.default.ndisc_notify" = "1"
    "net.ipv6.conf.ens18.ndisc_notify"  = "1"
    "net.ipv4.conf.all.arp_notify"       = "1"
    "net.ipv4.conf.default.arp_notify"   = "1"
    "net.ipv4.conf.ens18.arp_notify"    = "1"
  }

  common_features = {
    kubePrism = { enabled = true, port = 7445 }
    hostDNS = {
      enabled              = true # Required for Talos Helm controller
      forwardKubeDNSToHost = true # Enable with Cilium hostLegacyRouting for proper DNS integration
    }
  }

  common_cluster_network = {
    cni            = { name = "none" }                              # Cilium installed via inline manifests
    podSubnets     = [var.pod_cidr_ipv6, var.pod_cidr_ipv4]         # IPv6 preferred
    serviceSubnets = [var.service_cidr_ipv6, var.service_cidr_ipv4] # IPv6 preferred, dual-stack enabled below
  }

  # Control Plane specific configuration
  api_server_cert_sans = distinct(concat(
    [var.vip_ipv6, var.vip_ipv4],
    [for node in local.control_plane_nodes : node.public_ipv6],
    [for node in local.control_plane_nodes : node.public_ipv4],
    [for node in local.control_plane_nodes : "fd00:${var.cluster_id}:fe::${node.ip_suffix}"],
    [for node in local.control_plane_nodes : "10.${var.cluster_id}.254.${node.ip_suffix}"]
  ))

  controlplane_inline_manifests = concat(
    local.gateway_api_crds != "" ? [
      {
        name     = "gateway-api-crds"
        contents = local.gateway_api_crds
      }
    ] : [],
    [
      {
        name     = "cilium"
        contents = data.helm_template.cilium.manifest
      }
    ]
  )
}

# Template Cilium Helm chart with values from Flux config
data "helm_template" "cilium" {
  name         = "cilium"
  repository   = "https://helm.cilium.io/"
  chart        = "cilium"
  version      = var.cilium_version
  namespace    = "kube-system"
  kube_version = var.kubernetes_version
  skip_crds    = false
  include_crds = true

  # Only include values if cilium_values_yaml is not empty
  # This prevents Talos provider 0.10.0 validation errors
  values = local.cilium_values_yaml != "" ? [local.cilium_values_yaml] : []
}

# Generate cluster secrets (CA, bootstrap token, etc.)
resource "talos_machine_secrets" "cluster" {
  talos_version = var.talos_version
}

# Generate control plane machine configuration
data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = var.install_disk
          image = var.installer_image
          wipe  = false
        }
        kernel = {
          modules = []
        }
        time = {
          servers = var.ntp_servers
        }
        sysctls  = local.common_sysctls
        features = local.common_features
        kubelet = {
          resolvConf = "/etc/resolv.conf.kubelet"
        }
        files = [
          {
            content = "nameserver 169.254.116.108\n"
            path    = "/etc/resolv.conf.kubelet"
            op      = "create"
          }
        ]
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        network = local.common_cluster_network
        proxy = {
          disabled = true # Cilium kube-proxy replacement
        }
        apiServer = {
          certSANs = local.api_server_cert_sans
        }
        etcd = {
          advertisedSubnets = [
            "fd00:${var.cluster_id}:fe::/64",
            "fd00:${var.cluster_id}::/64"
          ] # Force etcd to use loopback IPs
        }
        # Install Gateway API CRDs and Cilium CNI via inline manifests
        # Gateway API CRDs must be installed first (if enabled in Cilium config)
        inlineManifests = local.controlplane_inline_manifests
      }
    }),
    # Separate patch for API server extraArgs (must be separate to work with Talos provider)
    yamlencode({
      cluster = {
        apiServer = {
          extraArgs = {
            "runtime-config"           = "admissionregistration.k8s.io/v1beta1=true"
            "feature-gates"            = "MutatingAdmissionPolicy=true"
            "service-cluster-ip-range" = "${var.service_cidr_ipv6},${var.service_cidr_ipv4}" # Explicit dual-stack
          }
        }
      }
    })
  ]
}

# Generate worker machine configuration
data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = var.install_disk
          image = var.installer_image
          wipe  = false
        }
        kernel = {
          modules = [
            { name = "i915" } # load Intel GPU driver when present
          ]
        }
        time = {
          servers = var.ntp_servers
        }
        sysctls  = local.common_sysctls
        features = local.common_features
        kubelet = {
          clusterDNS = [
            "fd00:${var.cluster_id}:96::a", # IPv6 DNS service IP (10th IP in service CIDR)
            "10.${var.cluster_id}.96.10"    # IPv4 DNS service IP (10th IP in service CIDR)
          ]
          resolvConf = "/etc/resolv.conf.kubelet"
        }
        files = [
          {
            content = "nameserver 169.254.116.108\n"
            path    = "/etc/resolv.conf.kubelet"
            op      = "create"
          },
          {
            op      = "create"
            path    = "/etc/cri/conf.d/20-customization.part"
            content = <<EOF
[plugins."io.containerd.cri.v1.runtime"]
  cdi_spec_dirs = ["/var/cdi/static", "/var/cdi/dynamic"]
EOF
          }
        ]
      }
      cluster = {
        network = local.common_cluster_network
        proxy = {
          disabled = true # Cilium kube-proxy replacement
        }
      }
    })
  ]
}

# Generate per-node configurations with network settings
# Split into separate locals blocks to avoid circular dependencies with Talos provider 0.10.0+
locals {
  # Render FRR config per node using native frr.conf template
  frr_configs = {
    for node_name, node in local.all_nodes : node_name => templatefile("${path.module}/frr.conf.j2", {
      # Node identity
      hostname   = node.hostname
      router_id  = "10.255.${var.cluster_id}.${node.node_suffix}"

      # BGP ASN configuration (4-byte ASN pattern: base + cluster_id * 1000 + suffix)
      # Example: base=4210000000, cluster 101, node 11 -> 4210101011
      # Formula: bgp_asn_base + (cluster_id * 1000) + (node_suffix)
      # Supports cluster IDs 000-999 and node suffixes 00-99
      local_asn  = node.frr_asn
      gw_asn     = var.bgp_remote_asn
      gw_ipv6    = "fe80::${var.cluster_id}:fffe"  # Link-local anycast gateway

      # Network configuration
      interface        = var.bgp_interface
      cluster_id       = var.cluster_id
      node_suffix      = node.node_suffix
      node_ipv6        = node.public_ipv6                                      # Node's primary IPv6 for BGP update-source
      loopback_ipv4    = "10.255.${var.cluster_id}.${node.node_suffix}"       # OLD pattern
      loopback_ipv6    = "fd00:255:${var.cluster_id}::${node.node_suffix}"    # OLD pattern
      bgp_loopback_ipv4 = "10.${var.cluster_id}.254.${node.node_suffix}"      # NEW pattern
      bgp_loopback_ipv6 = "fd00:${var.cluster_id}:fe::${node.node_suffix}"    # NEW pattern

      # Feature flags
      enable_bfd               = var.bgp_enable_bfd
      advertise_loopbacks      = var.bgp_advertise_loopbacks
    })
  }
}

# Pre-render extension service configs per node for use in config patches
# This is required for Talos provider 0.10.0+ which validates config patches early
# Separate locals block to ensure frr_configs is fully evaluated first
locals {
  extension_service_configs = {
    for node_name, node in local.all_nodes : node_name => templatefile("${path.module}/extension-service-config.yaml.tpl", {
      frr_conf_content = local.frr_configs[node_name]
      hostname         = node.hostname
      enable_bfd       = var.bgp_enable_bfd
    })
  }
}

# Generate machine configs with per-node patches
locals {
  machine_configs = {
    for node_name, node in local.all_nodes : node_name => {
      machine_type = node.machine_type
      machine_configuration = tostring(
        node.machine_type == "controlplane" ?
        data.talos_machine_configuration.controlplane.machine_configuration :
        data.talos_machine_configuration.worker.machine_configuration
      )
      # Per-node network patch and FRR ExtensionServiceConfig
      # Using heredoc to create proper multi-document YAML for Talos config_patch
      config_patch = <<-EOT
---
${yamlencode({
  machine = {
    nodeLabels = {
      "topology.kubernetes.io/region" = var.region
      "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
      "bgp.frr.asn"                   = tostring(node.frr_asn)
      "bgp.cilium.asn"                = tostring(node.cilium_asn)
    }
    network = {
      hostname = node.hostname
      interfaces = concat([
        {
          interface = var.bgp_interface
          mtu       = 1450  # Reduced for VXLAN overhead (SDN)
          addresses = concat(
            [
              "${node.public_ipv6}/64",    # ULA: fd00:101::11/64
              "${node.public_ipv4}/24",    # IPv4: 10.0.101.11/24
            ],
            var.gua_prefix != "" ? ["${trimsuffix(var.gua_prefix, "::/64")}::${node.node_suffix}/64"] : []  # GUA: 2600:1700:ab1a:500e::11/64
          )
          routes = [
            # IPv4: static route (no RA for IPv4) - will be overridden by BGP
            {
              network = "0.0.0.0/0"
              gateway = "10.${var.cluster_id}.0.254"
              metric  = 2048
            },
            # IPv6: default route via link-local anycast gateway
            {
              network = "::/0"
              gateway = "fe80::${var.cluster_id}:fffe"
              metric  = 150
            },
          ]
          vip = node.machine_type == "controlplane" ? {
            ip = var.vip_ipv6
          } : null
        },
        {
          interface = "lo"
          addresses = [
            "fd00:${var.cluster_id}:fe::${node.node_suffix}/128",        # IPv6 loopback
            "10.${var.cluster_id}.254.${node.node_suffix}/32"            # IPv4 loopback
          ]
        }
      ], [])
      nameservers = var.dns_servers
    }
    kubelet = {
      nodeIP = {
        validSubnets = [
          "fd00:${var.cluster_id}:fe::${node.node_suffix}/128",
          "fd00:${var.cluster_id}::${node.node_suffix}/128",
        ]
      }
    }
  }
})}
---
${local.extension_service_configs[node_name]}
EOT
    }
  }
}

# Generate client configuration (talosconfig)
data "talos_client_configuration" "cluster" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [for node in local.control_plane_nodes : node.public_ipv6]
  nodes = concat(
    [for node in local.control_plane_nodes : node.public_ipv6],
    [for node in local.worker_nodes : node.public_ipv6]
  )
}
