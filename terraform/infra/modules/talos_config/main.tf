
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

  # BGP ASN base for this cluster (used to calculate per-node ASN)
  # Format: 4210${cluster_id}${node_suffix} where node_suffix is 3 digits (zero-padded)
  # Example: cluster 101, node suffix 11 → 4210101011
  # Calculation: 4210000000 + (101 * 1000) + 11 = 4210101011
  frr_asn_base_cluster = var.bgp_asn_base + var.cluster_id * 1000

  # Cilium Cluster-wide ASN: 4220<cluster>000
  cilium_asn_cluster = 4220000000 + var.cluster_id * 1000

  # Combine all nodes with metadata (ip_suffix comes from input, rename to node_suffix for clarity)
  all_nodes = merge(
    { for k, v in local.control_plane_nodes : k => merge(v, {
      machine_type = "controlplane"
      node_suffix  = v.ip_suffix
      # Cilium/bird2 shared loopback (on dummy0) - uses fe and 254
      cilium_bgp_ipv6 = format("fd00:%d:fe::%d", var.cluster_id, v.ip_suffix)
      cilium_bgp_ipv4 = format("10.%d.254.%d", var.cluster_id, v.ip_suffix)
      # Per-node ASN: base + 3-digit node_suffix (e.g., 4210101011 for cluster 101, node 11)
      frr_asn = local.frr_asn_base_cluster + v.ip_suffix
    }) },
    { for k, v in local.worker_nodes : k => merge(v, {
      machine_type = "worker"
      node_suffix  = v.ip_suffix
      # Cilium/bird2 shared loopback (on dummy0) - uses fe and 254
      cilium_bgp_ipv6 = format("fd00:%d:fe::%d", var.cluster_id, v.ip_suffix)
      cilium_bgp_ipv4 = format("10.%d.254.%d", var.cluster_id, v.ip_suffix)
      # Per-node ASN: base + 3-digit node_suffix (e.g., 4210101021 for cluster 101, node 21)
      frr_asn = local.frr_asn_base_cluster + v.ip_suffix
    }) }
  )

  # Check if any worker nodes have GPU passthrough enabled
  has_gpu_nodes = anytrue([
    for name, node in local.worker_nodes :
    try(node.gpu_passthrough.enabled, false)
  ])

  # Read Cilium values from Flux config for inline manifests
  # Use fileexists() to safely handle file reading - prevents "open : no such file or directory" errors
  cilium_values_yaml = var.cilium_values_path != "" && try(fileexists(var.cilium_values_path), false) ? file(var.cilium_values_path) : ""

  # Read Gateway API CRDs (required before Cilium if gatewayAPI.enabled: true)
  gateway_api_crds_path = var.cilium_values_path != "" ? "${dirname(dirname(dirname(var.cilium_values_path)))}/crds/gateway-api-crds/gateway-api-crds-v1.3.0-experimental.yaml" : ""
  # Use fileexists() to safely handle file reading
  gateway_api_crds = local.gateway_api_crds_path != "" && try(fileexists(local.gateway_api_crds_path), false) ? file(local.gateway_api_crds_path) : ""

  # Read Cilium BGP configs from Flux directory (single source of truth)
  # These are applied as inline manifests so BGP is functional immediately at boot
  cilium_bgp_config_yaml = var.cilium_bgp_config_path != "" && try(fileexists(var.cilium_bgp_config_path), false) ? file(var.cilium_bgp_config_path) : ""
  cilium_lb_pool_yaml    = var.cilium_lb_pool_path != "" && try(fileexists(var.cilium_lb_pool_path), false) ? file(var.cilium_lb_pool_path) : ""

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
    "net.ipv6.conf.ens18.ndisc_notify"   = "1"
    "net.ipv6.conf.ens18.accept_ra"      = "2"
    "net.ipv4.conf.all.arp_notify"       = "1"
    "net.ipv4.conf.default.arp_notify"   = "1"
    "net.ipv4.conf.ens18.arp_notify"     = "1"
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
    ],
    # Cilium BGP configs - read from Flux directory for single source of truth
    # Applied after Cilium so CRDs are available
    local.cilium_bgp_config_yaml != "" ? [
      {
        name     = "cilium-bgp-config"
        contents = local.cilium_bgp_config_yaml
      }
    ] : [],
    local.cilium_lb_pool_yaml != "" ? [
      {
        name     = "cilium-lb-pool"
        contents = local.cilium_lb_pool_yaml
      }
    ] : [],
    # Per-node BGP configs (generated by Terraform based on cluster topology)
    [
      {
        name     = "cilium-bgp-node-configs"
        contents = local.cilium_bgp_node_configs_yaml
      },
      {
        name = "coredns-config"
        contents = yamlencode({
          apiVersion = "v1"
          kind       = "ConfigMap"
          metadata = {
            name      = "coredns"
            namespace = "kube-system"
          }
          data = {
            Corefile = <<-EOT
              .:53 {
                  errors
                  health {
                      lameduck 5s
                  }
                  ready
                  log . {
                      class error
                  }
                  prometheus :9153
                  kubernetes cluster.local in-addr.arpa ip6.arpa {
                      pods insecure
                      fallthrough in-addr.arpa ip6.arpa
                      ttl 30
                  }
                  forward . 169.254.116.108 {
                     max_concurrent 1000
                  }
                  cache 30 {
                      denial 9984 30
                  }
                  loop
                  reload
                  loadbalance
              }
            EOT
          }
        })
      }
    ]
  )

  reuse_machine_secrets          = var.machine_secrets != null && var.client_configuration != null
  generated_machine_secrets      = try(talos_machine_secrets.cluster[0].machine_secrets, null)
  generated_client_configuration = try(talos_machine_secrets.cluster[0].client_configuration, null)
  machine_secrets                = local.reuse_machine_secrets ? var.machine_secrets : local.generated_machine_secrets
  client_configuration           = local.reuse_machine_secrets ? var.client_configuration : local.generated_client_configuration
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
  count         = local.reuse_machine_secrets ? 0 : 1
  talos_version = var.talos_version
}

# Generate control plane machine configuration
data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = local.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk            = var.install_disk
          image           = var.installer_image
          wipe            = false
          extensions      = [for ext in var.system_extensions : { image = ext }]
          extraKernelArgs = var.kernel_args
        }
        kernel = {
          modules = []
        }
        time = {
          servers = var.ntp_servers
        }
        sysctls  = local.common_sysctls
        features = local.common_features
        kubelet  = {}
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        network                        = local.common_cluster_network
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
    }),
    # Separate patch for controller-manager extraArgs
    # Configure node CIDR mask sizes - /80 per node is standard for IPv6
    # /80 from /64 allows 65,536 nodes (2^16) with 2^48 IPs per node
    yamlencode({
      cluster = {
        controllerManager = {
          extraArgs = {
            "node-cidr-mask-size-ipv4" = "24"  # Each node gets /24 from IPv4 pod CIDR
            "node-cidr-mask-size-ipv6" = "80"  # Standard IPv6 mask - 65k nodes max
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
  machine_secrets  = local.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk            = var.install_disk
          image           = var.installer_image
          wipe            = false
          extensions      = [for ext in var.system_extensions : { image = ext }]
          extraKernelArgs = var.kernel_args
        }
        kernel = {
          # GPU kernel modules are configured per-node in config_patch
          # This keeps the base worker config generic
          modules = []
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
        }
        files = concat(
          [
            {
              op      = "create"
              path    = "/etc/cri/conf.d/20-customization.part"
              content = <<EOF
[plugins."io.containerd.cri.v1.runtime"]
  cdi_spec_dirs = ["/var/cdi/static", "/var/cdi/dynamic"]
EOF
            }
          ]
        )
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

# Generate per-node FRR config YAML for the extension
# Split into separate locals blocks to avoid circular dependencies with Talos provider 0.10.0+
locals {
  # Generate per-node bird2 configuration files
  bird2_config_confs = {
    for node_name, node in local.all_nodes : node_name => <<-EOT
      # bird2 BGP daemon configuration
      # Router ID uses the shared Cilium/bird2 loopback (.254)
      router id ${node.cilium_bgp_ipv4};

      # Logging
      log syslog all;

      # Device protocol - learns about network interfaces
      protocol device {
        scan time 10;
      }

      # Direct protocol - imports directly connected routes
      protocol direct {
        interface "dummy0", "lo";
        ipv4;
        ipv6;
      }

      # Kernel protocol for IPv4 - imports/exports routes from/to kernel
      protocol kernel {
        ipv4 {
          import none;
          export filter {
            # Don't export routes learned from Cilium or loopback back to kernel
            if proto = "cilium" then reject;
            if proto = "loopback" then reject;
            accept;
          };
        };
        merge paths on;
      }

      # Kernel protocol for IPv6
      protocol kernel {
        ipv6 {
          import none;
          export filter {
            # Don't export routes learned from Cilium or loopback back to kernel
            if proto = "cilium" then reject;
            if proto = "loopback" then reject;
            accept;
          };
        };
        merge paths on;
      }

      # BGP - Cilium Peering via localhost
      # bird2 listens on 179 (default), Cilium connects from localhost
      protocol bgp cilium {
        description "Cilium BGP Control Plane";
        passive on;
        multihop 2;
        local as ${node.frr_asn};
        neighbor 127.0.0.1 as ${local.cilium_asn_cluster};

        ipv4 {
          import all;
          export none;  # One-way: Cilium → bird2
        };

        ipv6 {
          import all;
          export none;  # One-way: Cilium → bird2
          extended next hop on;  # Cilium sends IPv6 routes with IPv4 next hop
        };
      }

      # BGP - Upstream Peering (same as FRR - ULA addresses)
      protocol bgp upstream {
        description "PVE ULA Anycast Gateway";
        local as ${node.frr_asn};
        source address ${node.public_ipv6};  # Use node's public IPv6 (fd00:101::X)
        neighbor fd00:${var.cluster_id}::fffe as ${var.bgp_remote_asn};

        ipv4 {
          import all;
          export all;
          next hop self;
        };

        ipv6 {
          import all;
          export all;
          next hop self;
          extended next hop on;  # MP-BGP over IPv6 for IPv4 routes
        };
      }
    EOT
  }
}

locals {
  cilium_bgp_node_configs_yaml = join("\n---\n", [
    for node_name, node in local.all_nodes : yamlencode({
      apiVersion = "cilium.io/v2"
      kind       = "CiliumBGPNodeConfig"
      metadata = {
        name = node_name
      }
      spec = {
        bgpInstances = [
          {
            name      = "local-bird2"
            localPort = 1790 # Listen on 1790 to avoid conflict with bird2 on 179; actively connects to bird2 via localhost
            localASN  = local.cilium_asn_cluster
            # Use Cilium BGP IP for router ID
            routerID = node.cilium_bgp_ipv4
            peers = [
              {
                name         = "bird2-local"
                peerASN      = node.frr_asn
                peerAddress  = "127.0.0.1"     # Connect TO bird2 via localhost (port 179)
                localAddress = "127.0.0.1"     # Connect FROM localhost
                peerConfigRef = {
                  name = "frr-local-mpbgp"     # Reuse existing peer config
                }
              }
            ]
          }
        ]
      }
    })
  ])
}

# Pre-render extension service configs per node for use in config patches
# This is required for Talos provider 0.10.0+ which validates config patches early
# Separate locals block to ensure bird2_config_confs is fully evaluated first
locals {
  extension_service_configs = {
    for node_name, node in local.all_nodes : node_name => templatefile("${path.module}/bird2-extension-service-config.yaml.tpl", {
      bird2_config_conf = local.bird2_config_confs[node_name]
      hostname          = node.hostname
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
      # Per-node network patch and bird2 ExtensionServiceConfig
      # Using heredoc to create proper multi-document YAML for Talos config_patch
      # Per-Node Configuration Patch (Multi-Document YAML)
      #
      # This patch contains TWO YAML documents separated by '---':
      # 1. Machine config patch (nodeLabels, network, kubelet, kernel)
      # 2. ExtensionServiceConfig patch (bird2 BGP daemon configuration)
      #
      # Both documents are per-node and both update safely via patch/ stage.
      #
      # Config Organization:
      # - TRULY PER-NODE: hostname, IPs, node-specific labels → Use patch/ stage
      # - TEMPLATED CLUSTER STANDARDS: MTU, DNS, route patterns → Use apply/ stage when changing cluster-wide
      #
      # Decision Rule: "Does this change require re-templating for ALL nodes?"
      # - YES (MTU, DNS, VLANs) → Edit here, then use apply/ stage
      # - NO (single node's IP/label) → Edit here, then use patch/ stage
      config_patch = <<-EOT
${yamlencode({
        machine = merge(
          {
            nodeLabels = merge(
              {
                # Templated cluster-wide labels (same pattern for all nodes)
                "topology.kubernetes.io/region" = var.region
                "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
                # Per-node label (unique per node)
                "bgp.frr.asn"                   = tostring(node.frr_asn)
              },
              # Add GPU label if GPU passthrough is enabled for this node
              try(node.gpu_passthrough.enabled, false) ? {
                "gpu.passthrough.enabled" = "true"
                "gpu.driver"              = try(node.gpu_passthrough.driver, "i915")
                "gpu.pci.address"         = replace(try(node.gpu_passthrough.pci_address, ""), ":", "-")
              } : {},
              # Add USB label if USB devices are passed through to this node
              try(length(node.usb), 0) > 0 ? {
                "usb-zigbee"        = "true"
                "home-assistant"    = "true"
              } : {}
            )
            network = {
              # Per-node: unique hostname for each node
              hostname = node.hostname
              interfaces = concat([
                {
                  interface = var.bgp_interface
                  # Templated cluster standard: All nodes use same MTU for VXLAN
                  # Change via apply/ stage when updating cluster-wide
                  mtu       = 1450 # Reduced for VXLAN overhead (SDN)
                  # Per-node: unique IP addresses for each node
                  addresses = concat(
                    var.gua_prefix != "" ? ["${trimsuffix(var.gua_prefix, "::/64")}::${node.node_suffix}/64"] : [], # GUA: 2600:1700:ab1a:500e::11/64
                    [
                      "${node.public_ipv6}/64", # ULA: fd00:101::11/64
                      "${node.public_ipv4}/24", # IPv4: 10.0.101.11/24
                    ]
                  )
                  # Templated cluster standard: Default route pattern uses cluster_id
                  # Change via apply/ stage when updating gateway pattern cluster-wide
                  routes = [
                    # IPv4: static route (no RA for IPv4) - will be overridden by BGP
                    {
                      network = "0.0.0.0/0"
                      gateway = "10.${var.cluster_id}.0.254"
                      metric  = 2048
                    },
                    # IPv6: default route via global unicast anycast gateway
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
                  # Per-node: unique loopback address for Cilium/bird2 BGP identity
                  interface = "dummy0"
                  addresses = [
                    "${node.cilium_bgp_ipv6}/128",  # Cilium/bird2 fe - FIRST for nodeIP
                    "${node.cilium_bgp_ipv4}/32",   # Cilium/bird2 254
                  ]
                }
                ], node.machine_type == "worker" ? [
                {
                  # Templated role-wide standard: All workers have same VLAN config
                  # Change via apply/ stage when updating VLAN IDs cluster-wide
                  interface = "ens19"
                  dhcp      = false
                  mtu       = 1500
                  vlans = [
                    {
                      vlanId = 30
                      mtu    = 1500
                    },
                    {
                      vlanId = 31
                      mtu    = 1500
                    }
                  ]
                }
              ] : [])
              # Templated cluster standard: All nodes use same DNS servers
              # Change via apply/ stage when updating DNS servers cluster-wide
              nameservers = var.dns_servers
            }
            kubelet = {
              nodeIP = {
                validSubnets = ["fd00:${var.cluster_id}::${node.node_suffix}/128"]
              }
            }
          },
          # Add GPU kernel module configuration if GPU passthrough is enabled
          # This is merged INTO the machine block to avoid shallow merge overwriting nodeLabels
          try(node.gpu_passthrough.enabled, false) && node.machine_type == "worker" ? {
            kernel = {
              modules = [
                {
                  name = try(node.gpu_passthrough.driver, "i915")
                  parameters = [
                    for k, v in try(node.gpu_passthrough.driver_params, {}) :
                    "${k}=${v}"
                  ]
                }
              ]
            }
          } : {}
        )
      })}
---
${"# YAML Document 2: ExtensionServiceConfig for FRR BGP daemon"}
${"# Per-node FRR configuration (peers, ASN, route filters)"}
${"# Updates safely via patch/ stage along with machine config above"}
${local.extension_service_configs[node_name]}
EOT
}
}
}

# Generate client configuration (talosconfig)
data "talos_client_configuration" "cluster" {
  cluster_name         = var.cluster_name
  client_configuration = local.client_configuration
  endpoints            = [for node in local.control_plane_nodes : node.public_ipv6]
  nodes = concat(
    [for node in local.control_plane_nodes : node.public_ipv6],
    [for node in local.worker_nodes : node.public_ipv6]
  )
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.cluster.talos_config
  filename = "${path.root}/talosconfig"
}

resource "local_file" "machine_config_patches" {
  for_each = local.machine_configs
  content  = each.value.config_patch
  filename = "${path.root}/${each.key}.patch.yaml"
}

resource "local_file" "cilium_bgp_node_configs" {
  content  = local.cilium_bgp_node_configs_yaml
  filename = "${path.root}/cilium-bgp-node-configs.yaml"
}

resource "terraform_data" "talos_secrets" {
  triggers_replace = [
    sha256(yamlencode(local.machine_secrets))
  ]

  provisioner "local-exec" {
    command = "printf '%s' \"$SECRETS\" | sops --encrypt --input-type yaml --output-type yaml --filename-override talsecret.sops.yaml /dev/stdin > \"${path.root}/talsecret.sops.yaml\""
    environment = {
      SECRETS = yamlencode(local.machine_secrets)
    }
  }
}
