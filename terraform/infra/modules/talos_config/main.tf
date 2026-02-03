
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
      machine_type      = "controlplane"
      node_suffix       = v.ip_suffix
      loopback_ipv6     = format("fd00:%d:fe::%d", var.cluster_id, v.ip_suffix)
      loopback_ipv4     = format("10.%d.254.%d", var.cluster_id, v.ip_suffix)
      bgp_loopback_ipv6 = format("fd00:%d:254::%d", var.cluster_id, v.ip_suffix) # Dedicated BGP peering loopback
      bgp_loopback_ipv4 = format("10.%d.255.%d", var.cluster_id, v.ip_suffix)    # Dedicated BGP peering loopback
      # Per-node ASN: base + 3-digit node_suffix (e.g., 4210101011 for cluster 101, node 11)
      frr_asn = local.frr_asn_base_cluster + v.ip_suffix
    }) },
    { for k, v in local.worker_nodes : k => merge(v, {
      machine_type      = "worker"
      node_suffix       = v.ip_suffix
      loopback_ipv6     = format("fd00:%d:fe::%d", var.cluster_id, v.ip_suffix)
      loopback_ipv4     = format("10.%d.254.%d", var.cluster_id, v.ip_suffix)
      bgp_loopback_ipv6 = format("fd00:%d:254::%d", var.cluster_id, v.ip_suffix) # Dedicated BGP peering loopback
      bgp_loopback_ipv4 = format("10.%d.255.%d", var.cluster_id, v.ip_suffix)    # Dedicated BGP peering loopback
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
  cilium_allowed_prefixes = {
    ipv4 = [for prefix in var.bgp_cilium_allowed_prefixes.ipv4 : prefix if prefix != ""]
    ipv6 = [for prefix in var.bgp_cilium_allowed_prefixes.ipv6 : prefix if prefix != ""]
  }
  frr_config_yamls = {
    for node_name, node in local.all_nodes : node_name => yamlencode({
      bgp = {
        cilium = {
          local_asn  = node.frr_asn             # FRR's ASN
          remote_asn = local.cilium_asn_cluster # Cilium's ASN (eBGP)
          peering = {
            ipv6 = {
              # Peer on localhost/loopback since we are in host netns
              local  = node.bgp_loopback_ipv6 # FRR binds to BGP loopback
              remote = node.loopback_ipv6     # Cilium connects from main loopback
              prefix = 126
            }
          }
          export_loopbacks = false
          allowed_prefixes = local.cilium_allowed_prefixes
        }
        upstream = {
          local_asn           = node.frr_asn
          router_id           = "10.${var.cluster_id}.254.${node.node_suffix}"
          router_id_v6        = "fd00:${var.cluster_id}:fe::${node.node_suffix}"
          update_source       = node.public_ipv6
          advertise_loopbacks = var.bgp_advertise_loopbacks
          loopbacks = {
            ipv4 = node.loopback_ipv4
            ipv6 = node.loopback_ipv6
          }
          loopback_addresses = {
            ipv4 = [node.loopback_ipv4]
            ipv6 = [node.loopback_ipv6]
          }
          peers = [
            {
              address                     = "fd00:${var.cluster_id}::fffe"
              remote_asn                  = var.bgp_remote_asn
              description                 = "PVE ULA Anycast Gateway"
              update_source               = node.public_ipv6
              address_family              = "ipv6"
              capability_extended_nexthop = true
              route_map_in_v4             = "IMPORT-DEFAULT-v4"
              route_map_in_v6             = "IMPORT-DEFAULT-v6"
              route_map_out               = "EXPORT-TO-UPSTREAM"
            }
          ]
        }
      }
      network = {
        interface_mtu = 1450
        veth_names = {
          frr_side    = "veth-frr"
          cilium_side = "veth-cilium"
        }
      }
      bfd = {
        profiles = {
          normal = {
            detect_multiplier = 3
            receive_interval  = 300
            transmit_interval = 300
          }
        }
        cilium_peering = {
          enabled = false
          profile = "normal"
        }
      }
      route_filters = {
        prefix_lists = {
          ipv4 = {
            "CILIUM-LB-v4" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = var.loadbalancers_ipv4
                  le     = 32
                }
              ]
            }
            "DEFAULT-ONLY-v4" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "0.0.0.0/0"
                }
              ]
            }
            "LOOPBACK-v4" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "10.${var.cluster_id}.254.0/24"
                  le     = 32
                }
              ]
            }
            "LOOPBACK-self-v4" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "10.${var.cluster_id}.254.0/24"
                  le     = 32
                },
                {
                  seq    = 20
                  action = "permit"
                  prefix = "10.${var.cluster_id}.255.0/24"
                  le     = 32
                }
              ]
            }
            "CILIUM-ALL-v4" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "0.0.0.0/0"
                  le     = 32
                }
              ]
            }
          }
          ipv6 = {
            "CILIUM-LB-v6" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = var.loadbalancers_ipv6
                  le     = 128
                }
              ]
            }
            "CILIUM-ALL-v6" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "::/0"
                  le     = 128
                }
              ]
            }
            "DEFAULT-ONLY-v6" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "::/0"
                }
              ]
            }
            "LOOPBACK-v6" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "fd00:${var.cluster_id}:fe::/48"
                  le     = 128
                }
              ]
            }
            "LOOPBACK-self-v6" = {
              rules = [
                {
                  seq    = 10
                  action = "permit"
                  prefix = "fd00:${var.cluster_id}:fe::/112"
                  le     = 128
                },
                {
                  seq    = 20
                  action = "permit"
                  prefix = "fd00:${var.cluster_id}:254::/112"
                  le     = 128
                }
              ]
            }
          }
        }
        route_maps = {
          "IMPORT-DEFAULT-v4" = {
            rules = [
              {
                seq    = 10
                action = "permit"
                match = {
                  address_family = "ipv4"
                  prefix_list    = "DEFAULT-ONLY-v4"
                }
              },
              {
                seq    = 90
                action = "deny"
              }
            ]
          }
          "IMPORT-DEFAULT-v6" = {
            rules = [
              {
                seq    = 10
                action = "permit"
                match = {
                  address_family = "ipv6"
                  prefix_list    = "DEFAULT-ONLY-v6"
                }
              },
              {
                seq    = 90
                action = "deny"
              }
            ]
          }
          "IMPORT-FROM-CILIUM-v4" = {
            rules = [
              {
                seq    = 10
                action = "permit"
                match = {
                  address_family = "ipv4"
                  prefix_list    = "CILIUM-ALL-v4"
                }
              }
            ]
          }
          "IMPORT-FROM-CILIUM-v6" = {
            rules = [
              {
                seq    = 10
                action = "permit"
                match = {
                  address_family = "ipv6"
                  prefix_list    = "CILIUM-ALL-v6"
                }
              }
            ]
          }
          "EXPORT-TO-UPSTREAM" = {
            rules = [
              {
                seq    = 10
                action = "permit"
                match = {
                  prefix_list = "CILIUM-LB-v4"
                }
              },
              {
                seq    = 12
                action = "permit"
                match = {
                  prefix_list = "LOOPBACK-self-v4"
                }
              },
              {
                seq    = 15
                action = "permit"
                match = {
                  address_family = "ipv6"
                  prefix_list    = "CILIUM-LB-v6"
                }
              },
              {
                seq    = 17
                action = "permit"
                match = {
                  address_family = "ipv6"
                  prefix_list    = "LOOPBACK-self-v6"
                }
              },
              {
                seq    = 20
                action = "permit"
                match = {
                  interface = "lo"
                }
              },
              {
                seq    = 25
                action = "permit"
                match = {
                  interface = "dummy0"
                }
              }
            ]
          }
        }
      }
    })
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
            name      = "local-frr"
            localPort = 1790 # Avoid port 179 conflict with FRR
            localASN  = local.cilium_asn_cluster
            # Use 10.101.255.x for Cilium router ID to avoid collision with FRR (10.101.254.x)
            routerID = replace(node.loopback_ipv4, "10.101.254.", "10.101.255.")
            peers = [
              {
                name         = "frr-local-ipv6"
                peerASN      = node.frr_asn
                peerAddress  = node.bgp_loopback_ipv6 # Connect to FRR on its BGP loopback IP
                localAddress = node.loopback_ipv6     # Use main loopback as source (for RFC5549 next-hop)
                peerConfigRef = {
                  name = "frr-local-mpbgp"
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
# Separate locals block to ensure frr_config_yamls is fully evaluated first
locals {
  extension_service_configs = {
    for node_name, node in local.all_nodes : node_name => templatefile("${path.module}/extension-service-config.yaml.tpl", {
      frr_config_yaml = local.frr_config_yamls[node_name]
      hostname        = node.hostname
      enable_bfd      = var.bgp_enable_bfd
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
${yamlencode(merge(
      {
        machine = {
          nodeLabels = merge(
            {
              "topology.kubernetes.io/region" = var.region
              "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
              "bgp.frr.asn"                   = tostring(node.frr_asn)
            },
            # Add GPU label if GPU passthrough is enabled for this node
            try(node.gpu_passthrough.enabled, false) ? {
              "gpu.passthrough.enabled" = "true"
              "gpu.driver"              = try(node.gpu_passthrough.driver, "i915")
              "gpu.pci.address"         = try(node.gpu_passthrough.pci_address, "")
            } : {}
          )
          network = {
            hostname = node.hostname
            interfaces = concat([
              {
                interface = var.bgp_interface
                mtu       = 1450 # Reduced for VXLAN overhead (SDN)
                addresses = concat(
                  [
                    "${node.public_ipv6}/64", # ULA: fd00:101::11/64
                    "${node.public_ipv4}/24", # IPv4: 10.0.101.11/24
                  ],
                  var.gua_prefix != "" ? ["${trimsuffix(var.gua_prefix, "::/64")}::${node.node_suffix}/64"] : [] # GUA: 2600:1700:ab1a:500e::11/64
                )
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
                    gateway = "fd00:${var.cluster_id}::fffe"
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
                  "fd00:${var.cluster_id}:fe::${node.node_suffix}/128",  # IPv6 loopback (main)
                  "10.${var.cluster_id}.254.${node.node_suffix}/32",     # IPv4 loopback (main)
                  "fd00:${var.cluster_id}:254::${node.node_suffix}/128", # IPv6 BGP loopback (for Cilium peering)
                  "10.${var.cluster_id}.255.${node.node_suffix}/32"      # IPv4 BGP loopback (for Cilium peering)
                ]
              }
              ], node.machine_type == "worker" ? [
              {
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
            nameservers = var.dns_servers
          }
          kubelet = {
            nodeIP = {
              validSubnets = ["fd00:${var.cluster_id}::${node.node_suffix}/128"]
            }
          }
        }
      },
      # Add GPU kernel module configuration if GPU passthrough is enabled
      try(node.gpu_passthrough.enabled, false) && node.machine_type == "worker" ? {
        machine = {
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
        }
      } : {}
))}
---
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
