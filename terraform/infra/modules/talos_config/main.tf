
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
    }) },
    { for k, v in local.worker_nodes : k => merge(v, {
      machine_type = "worker"
      node_suffix  = v.ip_suffix
    }) }
  )

  # Read Cilium values from Flux config for inline manifests
  cilium_values_yaml = var.cilium_values_path != "" ? file(var.cilium_values_path) : ""

  # Read Gateway API CRDs (required before Cilium if gatewayAPI.enabled: true)
  gateway_api_crds_path = var.cilium_values_path != "" ? "${dirname(dirname(dirname(var.cilium_values_path)))}/crds/gateway-api-crds/gateway-api-crds-v1.3.0-experimental.yaml" : ""
  gateway_api_crds      = var.cilium_values_path != "" && fileexists(local.gateway_api_crds_path) ? file(local.gateway_api_crds_path) : ""

  # Path to FRR config template (native frr.conf format)
  # Template must be in module directory for Terraform to find it
  frr_template_path = "${path.module}/frr.conf.j2"
}

# Template Cilium Helm chart with values from Flux config
data "helm_template" "cilium" {
  name         = "cilium"
  repository   = "https://helm.cilium.io/"
  chart        = "cilium"
  version      = "1.18.4"
  namespace    = "kube-system"
  kube_version = var.kubernetes_version
  skip_crds    = false
  include_crds = true

  values = [
    local.cilium_values_yaml
  ]
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
          servers = [
            "fd00:${var.cluster_id}::ffff"  # DNS/NTP server on VLAN gateway (RouterOS)
          ]
        }
        sysctls = {
          "fs.inotify.max_user_watches"   = "1048576"
          "fs.inotify.max_user_instances" = "8192"
          "fs.file-max"                   = "1000000"
          "net.core.somaxconn"            = "32768"
          "net.ipv4.ip_forward"           = "1"
          "net.ipv6.conf.all.forwarding"  = "1"
          # Accept IPv6 RAs even with forwarding enabled (for SLAAC with PD)
          "net.ipv6.conf.all.accept_ra"   = "2"
          "net.ipv6.conf.default.accept_ra" = "2"
          # Disable sending RAs (nodes should not advertise themselves as routers)
          "net.ipv6.conf.all.accept_ra_rtr_pref" = "0"
        }
        features = {
          kubePrism = { enabled = true, port = 7445 }
          hostDNS = {
            enabled              = true  # Required for Talos Helm controller
            forwardKubeDNSToHost = false # Disable to allow Cilium bpf.masquerade=true
          }
        }
        kubelet = {
          nodeIP = {
            validSubnets = [
              "fd00:255:${var.cluster_id}::/64", # IPv6 loopback (preferred)
              "10.255.${var.cluster_id}.0/24"    # IPv4 loopback (for dual-stack endpoints)
            ]
          }
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        network = {
          cni            = { name = "none" }                              # Cilium installed via inline manifests
          podSubnets     = [var.pod_cidr_ipv6, var.pod_cidr_ipv4]         # IPv6 preferred
          serviceSubnets = [var.service_cidr_ipv6, var.service_cidr_ipv4] # IPv6 preferred, dual-stack enabled below
        }
        proxy = {
          disabled = true # Cilium kube-proxy replacement
        }
        apiServer = {
          certSANs = concat(
            [var.vip_ipv6, var.vip_ipv4],
            [for node in local.control_plane_nodes : node.public_ipv6],
            [for node in local.control_plane_nodes : node.public_ipv4]
          )
        }
        etcd = {
          advertisedSubnets = ["fd00:255:${var.cluster_id}::/64"] # Force etcd to use loopback IPs
        }
        # Install Gateway API CRDs and Cilium CNI via inline manifests
        # Gateway API CRDs must be installed first (if enabled in Cilium config)
        inlineManifests = concat(
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
        sysctls = {
          "fs.inotify.max_user_watches"   = "1048576"
          "fs.inotify.max_user_instances" = "8192"
          "fs.file-max"                   = "1000000"
          "net.core.somaxconn"            = "32768"
          "net.ipv4.ip_forward"           = "1"
          "net.ipv6.conf.all.forwarding"  = "1"
          # Accept IPv6 RAs even with forwarding enabled (for SLAAC with PD)
          "net.ipv6.conf.all.accept_ra"   = "2"
          "net.ipv6.conf.default.accept_ra" = "2"
          # Disable sending RAs (nodes should not advertise themselves as routers)
          "net.ipv6.conf.all.accept_ra_rtr_pref" = "0"
        }
        features = {
          kubePrism = { enabled = true, port = 7445 }
          hostDNS = {
            enabled              = true  # Required for Talos Helm controller
            forwardKubeDNSToHost = false # Disable to allow Cilium bpf.masquerade=true
          }
        }
        kubelet = {
          nodeIP = {
            validSubnets = [
              "fd00:255:${var.cluster_id}::/64", # IPv6 loopback (preferred)
              "10.255.${var.cluster_id}.0/24"    # IPv4 loopback (for dual-stack endpoints)
            ]
          }
          clusterDNS = [
            "fd00:${var.cluster_id}:96::a", # IPv6 DNS service IP (10th IP in service CIDR)
            "10.${var.cluster_id}.96.10"    # IPv4 DNS service IP (10th IP in service CIDR)
          ]
        }
        files = [
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
    })
  ]
}

# Generate per-node configurations with network settings
locals {
  # Render FRR config per node using native frr.conf template
  frr_configs = {
    for node_name, node in local.all_nodes : node_name => templatefile(local.frr_template_path, {
      # Node identity
      hostname   = node.hostname
      router_id  = "10.255.${var.cluster_id}.${node.node_suffix}"

      # BGP ASN configuration (4-byte ASN pattern: 4210<cluster_id>0<suffix>)
      # Example: cluster 101, node 11 -> 4210101011
      # Formula: 4210000000 + (cluster_id * 1000) + (node_suffix)
      # Supports cluster IDs 000-999 and node suffixes 00-99
      local_asn  = 4210000000 + var.cluster_id * 1000 + node.node_suffix
      remote_asn = var.bgp_remote_asn

      # Network configuration
      interface        = var.bgp_interface
      cluster_id       = var.cluster_id
      node_suffix      = node.node_suffix
      loopback_ipv4    = "10.255.${var.cluster_id}.${node.node_suffix}"
      loopback_ipv6    = "fd00:255:${var.cluster_id}::${node.node_suffix}"

      # Feature flags
      enable_bfd               = var.bgp_enable_bfd
      advertise_loopbacks      = var.bgp_advertise_loopbacks
    })
  }

  machine_configs = {
    for node_name, node in local.all_nodes : node_name => {
      machine_type = node.machine_type
      machine_configuration = tostring(
        node.machine_type == "controlplane" ?
        data.talos_machine_configuration.controlplane.machine_configuration :
        data.talos_machine_configuration.worker.machine_configuration
      )
      # Per-node network patch and FRR ExtensionServiceConfig
      config_patch = join("\n---\n", [
        yamlencode({
          machine = {
            nodeLabels = {
              "topology.kubernetes.io/region" = var.region
              "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
              # 4-byte ASN pattern: 4210<cluster_id>0<suffix>
              # Formula: 4210000000 + (cluster_id * 1000) + node_suffix
              "bgp.frr.asn"                   = tostring(4210000000 + var.cluster_id * 1000 + node.node_suffix)
              # Cilium ASN: 4220<cluster_id>0<suffix>
              "bgp.cilium.asn"                = tostring(4220000000 + var.cluster_id * 1000 + node.node_suffix)
            }
            network = {
              hostname = node.hostname
              interfaces = concat([
                {
                  interface = "ens18"
                  mtu       = 1500
                  addresses = [
                    "${node.public_ipv6}/64",
                    "${node.public_ipv4}/24",
                    "fe80::${var.cluster_id}:${node.node_suffix}/64"
                  ]
                  routes = [
                    # IPv4: static route (no RA for IPv4) - will be overridden by BGP
                    {
                      network = "0.0.0.0/0"
                      gateway = "10.0.${var.cluster_id}.254"
                      metric  = 1024
                    },
                    # IPv6: backup route for internal ULA networks in case PD fails
                    # PD default route (metric 256) wins when available
                    # This static route (metric 1024) provides failover for internal access
                    {
                      network = "fc00::/7"
                      gateway = "fd00:${var.cluster_id}::ffff"
                      metric  = 1024
                    }
                  ]
                  vip = node.machine_type == "controlplane" ? {
                    ip = var.vip_ipv6
                  } : null
                },
                {
                  interface = "lo"
                  addresses = [
                    "fd00:255:${var.cluster_id}::${node.node_suffix}/128",
                    "10.255.${var.cluster_id}.${node.node_suffix}/32"
                  ]
                }
              ], [])
              nameservers = var.dns_servers
            }
          }
        }),
        # ExtensionServiceConfig as raw YAML to avoid JSON-quoted strings from yamlencode
        templatefile("${path.module}/extension-service-config.yaml.tpl", {
          frr_conf_content = local.frr_configs[node_name]
          hostname         = node.hostname
          enable_bfd       = var.bgp_enable_bfd
        })
      ])
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
