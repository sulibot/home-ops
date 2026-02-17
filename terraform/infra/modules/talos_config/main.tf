
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
  gateway_api_crds_path = var.cilium_values_path != "" ? "${dirname(dirname(dirname(var.cilium_values_path)))}/crds/gateway-api-crds/gateway-api-crds-v1.4.0-experimental.yaml" : ""
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
      forwardKubeDNSToHost = true # Enabled (Compatible with Cilium Legacy Host Routing)
    }
  }

  common_cluster_network = {
    cni            = { name = "none" }                              # Cilium installed via inline manifests
    podSubnets     = [var.pod_cidr_ipv6, var.pod_cidr_ipv4]         # IPv6 first-class
    serviceSubnets = [var.service_cidr_ipv6, var.service_cidr_ipv4] # IPv6 first-class, dual-stack enabled
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
        registries = {
          mirrors = {
            "docker.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
            "ghcr.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
            "registry.k8s.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
            "quay.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
          }
        }
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
          # Explicitly define initial cluster members via extraArgs so all control planes know about each other
          # This prevents learner promotion timing issues where only 1/3 nodes join
          # Per-node advertisedSubnets with /128 ensures only static IPv6 is used (not SLAAC)
          extraArgs = {
            "initial-cluster-state" = "new"
            "initial-cluster" = join(",", [
              for name, node in local.control_plane_nodes :
              format("%s=https://[%s]:2380", node.hostname, node.public_ipv6)
            ])
          }
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
            "service-cluster-ip-range" = "${var.service_cidr_ipv6},${var.service_cidr_ipv4}" # IPv6 first-class, dual-stack
          }
        }
      }
    }),
    # Separate patch for controller-manager extraArgs
    # Configure node CIDR mask sizes
    # /64 per node is the IPv6 standard - from /60 pod CIDR allows 16 nodes (2^4)
    yamlencode({
      cluster = {
        controllerManager = {
          extraArgs = {
            "node-cidr-mask-size-ipv4" = "24"  # Each node gets /24 from IPv4 pod CIDR (/20 → 16 nodes)
            "node-cidr-mask-size-ipv6" = "64"  # Standard /64 per node - from /60 allows 16 nodes
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
        registries = {
          mirrors = {
            "docker.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
            "ghcr.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
            "registry.k8s.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
            "quay.io" = {
              endpoints    = ["http://localhost:29999"]
              overridePath = true
            }
          }
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
      protocol direct direct_routes {
        interface "dummy0", "lo", "ens18";
        ipv4 {
          import all;
        };
        ipv6 {
          import all;
        };
      }

      # Kernel protocol for IPv4 - imports/exports routes from/to kernel
      protocol kernel kernel_v4 {
        ipv4 {
          import none;
          export filter {
            # Never install Kubernetes Service CIDR routes in kernel.
            # ClusterIP is virtual and must be handled by Cilium eBPF service LB.
            if net ~ [10.${var.cluster_id}.96.0/24{24,32}] then reject;
            # Only export routes learned from upstream (FRR) to kernel
            if proto = "upstream" then accept;
            reject;
          };
        };
        merge paths on;
      }

      # Kernel protocol for IPv6
      protocol kernel kernel_v6 {
        ipv6 {
          import none;
          export filter {
            # Never install Kubernetes Service CIDR routes in kernel.
            # ClusterIP is virtual and must be handled by Cilium eBPF service LB.
            if net ~ [fd00:${var.cluster_id}:96::/112{112,128}] then reject;
            # Only export routes learned from upstream (FRR) to kernel
            if proto = "upstream" then accept;
            reject;
          };
        };
        merge paths on;
      }

      # BFD protocol
      protocol bfd {
        interface "*" { multiplier 3; interval 300 ms; };
      }

      # BGP - Cilium Peering via localhost
      # bird2 listens on 179 (default), Cilium connects from localhost
      protocol bgp cilium {
        description "Cilium BGP Control Plane";
        passive on;
        multihop 2;
        local as ${node.frr_asn};
        neighbor ::1 as ${local.cilium_asn_cluster};

        ipv4 {
          import all;
          export none;  # One-way: Cilium → bird2
          extended next hop on;  # MP-BGP: IPv4 routes over IPv6 session
        };

        ipv6 {
          import all;
          export none;  # One-way: Cilium → bird2
        };
      }

      # BGP - Upstream Peering (same as FRR - ULA addresses)
      protocol bgp upstream {
        description "PVE ULA Anycast Gateway";
        local as ${node.frr_asn};
        source address ${node.public_ipv6};  # Use node's public IPv6 (fd00:101::X)
        neighbor fd00:${var.cluster_id}::fffe as ${var.bgp_remote_asn};
        bfd on;

        ipv4 {
          import filter {
            # Do not learn Kubernetes Service CIDR from upstream.
            if net ~ [10.${var.cluster_id}.96.0/24{24,32}] then reject;
            accept;
          };
          export filter {
            # Tag Loopbacks (protocol direct_routes) as Public (Community :200) so PVE exports them to Edge
            if proto = "direct_routes" then {
              bgp_large_community.add((${var.bgp_remote_asn}, 0, 200));
              accept;
            }
            # Pass through other routes (e.g. from Cilium)
            accept;
          };
          next hop self;
          extended next hop on;
        };

        ipv6 {
          import filter {
            # Reject the local node subnet - nodes use direct kernel routes
            # Importing this from gateway creates lower-metric route that breaks Cilium
            if net = fd00:${var.cluster_id}::/64 then reject;
            # Do not learn Kubernetes Service CIDR from upstream.
            if net ~ [fd00:${var.cluster_id}:96::/112{112,128}] then reject;
            accept;
          };
          export filter {
            # Tag Loopbacks (protocol direct_routes) as Public (Community :200) so PVE exports them to Edge
            if proto = "direct_routes" then {
              bgp_large_community.add((${var.bgp_remote_asn}, 0, 200));
              accept;
            }
            # Pass through other routes (e.g. from Cilium)
            accept;
          };
          next hop self;
          missing lladdr ignore;  # Allow exporting routes without link-local addresses
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
                peerAddress  = "::1"           # Connect TO bird2 via localhost (port 179)
                localAddress = "::1"           # Connect FROM localhost
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

# Helper: Calculate per-node machine config patches (separated from extension config)
locals {
  node_config_patches = {
    for node_name, node in local.all_nodes : node_name => {
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
              "usb-zigbee"     = "true"
              "home-assistant" = "true"
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
                mtu = 1450 # Reduced for VXLAN overhead (SDN)
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
                  "${node.cilium_bgp_ipv6}/128", # Cilium/bird2 fe - FIRST for nodeIP
                  "${node.cilium_bgp_ipv4}/32",  # Cilium/bird2 254
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
      # Per-node etcd configuration (control plane only)
      cluster = node.machine_type == "controlplane" ? {
        etcd = {
          # Advertise only this node's specific IPv6 address (not SLAAC)
          advertisedSubnets = ["${node.public_ipv6}/128"]
        }
      } : {}
    }
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

      # New fields for cleaner separation
      machine_config_patch = yamlencode(local.node_config_patches[node_name])
      extension_config     = local.extension_service_configs[node_name]

      # Legacy combined field for backward compatibility with apply/ stage
      config_patch = <<-EOT
${yamlencode(local.node_config_patches[node_name])}
---
${"# YAML Document 2: ExtensionServiceConfig for FRR BGP daemon"}
${local.extension_service_configs[node_name]}
EOT
}
}
}

# Generate client configuration (talosconfig)
data "talos_client_configuration" "cluster" {
  cluster_name         = var.cluster_name
  client_configuration = local.client_configuration
  endpoints            = [for node in local.control_plane_nodes : node.public_ipv4]
  nodes = concat(
    [for node in local.control_plane_nodes : node.public_ipv4],
    [for node in local.worker_nodes : node.public_ipv4]
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
