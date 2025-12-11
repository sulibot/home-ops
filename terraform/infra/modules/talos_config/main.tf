
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

  # Combine all nodes with metadata
  all_nodes = merge(
    { for k, v in local.control_plane_nodes : k => merge(v, { machine_type = "controlplane" }) },
    { for k, v in local.worker_nodes : k => merge(v, { machine_type = "worker" }) }
  )

  # Read Cilium values from Flux config for inline manifests
  cilium_values_yaml = var.cilium_values_path != "" ? file(var.cilium_values_path) : ""

  # Read Gateway API CRDs (required before Cilium if gatewayAPI.enabled: true)
  gateway_api_crds_path = var.cilium_values_path != "" ? "${dirname(dirname(dirname(var.cilium_values_path)))}/crds/gateway-api-crds/gateway-api-crds-v1.3.0-experimental.yaml" : ""
  gateway_api_crds      = var.cilium_values_path != "" && fileexists(local.gateway_api_crds_path) ? file(local.gateway_api_crds_path) : ""
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
        sysctls = {
          "fs.inotify.max_user_watches"   = "1048576"
          "fs.inotify.max_user_instances" = "8192"
          "fs.file-max"                   = "1000000"
          "net.core.somaxconn"            = "32768"
          "net.ipv4.ip_forward"           = "1"
          "net.ipv6.conf.all.forwarding"  = "1"
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
  machine_configs = {
    for node_name, node in local.all_nodes : node_name => {
      machine_type = node.machine_type
      machine_configuration = tostring(
        node.machine_type == "controlplane" ?
        data.talos_machine_configuration.controlplane.machine_configuration :
        data.talos_machine_configuration.worker.machine_configuration
      )
      # Per-node network patch and BIRD2 ExtensionServiceConfig
      config_patch = join("\n---\n", [
        yamlencode({
          machine = {
            nodeLabels = {
              "topology.kubernetes.io/region" = "home-lab"
              "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
              "bgp.bird.asn"                  = tostring(4210000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3]))
              "bgp.cilium.asn"                = tostring(4220000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3]))
            }
            network = {
              hostname = node.hostname
              interfaces = [
                # Public network (ens18) - link-local only for BGP peering
                {
                  interface = "ens18"
                  mtu       = 1500
                  # Underlay addresses COMMENTED for rollback - link-local migration
                  # addresses = [
                  #   "${node.public_ipv6}/64",
                  #   "${node.public_ipv4}/24"
                  # ]
                  # Link-local fe80::/64 is automatic, no config needed
                  # Default routes will come from BGP
                  routes = []
                  vip = node.machine_type == "controlplane" ? {
                    ip = var.vip_ipv6
                  } : null
                },
                # REMOVED - mesh network no longer needed for link-local migration
                # {
                #   interface = "ens19"
                #   mtu       = 8930
                #   addresses = [
                #     "${node.mesh_ipv6}/64",
                #     "${node.mesh_ipv4}/24"
                #   ]
                #   routes = [
                #     {
                #       network = "fc00::/8"
                #       gateway = "fc00:${var.cluster_id}::fffe"
                #     },
                #     {
                #       network = "10.10.0.0/16"
                #       gateway = "10.10.${var.cluster_id}.254"
                #     }
                #   ]
                # },
                # Loopback interface for BIRD2 BGP peering
                {
                  interface = "lo"
                  addresses = [
                    "fd00:255:${var.cluster_id}::${split(".", node.public_ipv4)[3]}/128",
                    "10.255.${var.cluster_id}.${split(".", node.public_ipv4)[3]}/32"
                  ]
                }
              ]
              nameservers = var.dns_servers
            }
          }
        }),
        <<-EXTENSION_CONFIG
        apiVersion: v1alpha1
        kind: ExtensionServiceConfig
        name: bird2
        configFiles:
          - content: |
              # BIRD2 Configuration for ${node.hostname}
              # BGP Topology: RouterOS (AS 65000) ←eBGP→ BIRD2 (AS ${4210000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])}) ←eBGP→ Cilium (AS ${4220000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])})

              log stderr all;

              # Router ID from loopback IPv4
              router id 10.255.${var.cluster_id}.${split(".", node.public_ipv4)[3]};

              protocol device {
                  scan time 10;
              }

              protocol direct {
                  ipv4;
                  ipv6;
                  interface "lo";
              }

              protocol kernel kernel_v4 {
                  ipv4 {
                      import all;
                      export all;  # Allow BIRD2 to install routes from BGP into kernel
                  };
                  learn;
              }

              protocol kernel kernel_v6 {
                  ipv6 {
                      import all;
                      export all;  # Allow BIRD2 to install routes from BGP into kernel
                  };
                  learn;
              }

              filter export_to_pve {
                  # Export loopbacks and pod CIDRs (Cilium-learned routes)
                  # No next-hop rewriting needed - PVE will use link-local
                  if source ~ [RTS_DEVICE, RTS_INHERIT, RTS_STATIC] then accept;
                  reject;
              }

              filter import_from_pve {
                  # Accept default route and any other routes from PVE
                  accept;
              }

              filter export_to_cilium {
                  if source ~ [RTS_DEVICE, RTS_STATIC] then accept;
                  if source = RTS_BGP && proto = "pve_upstream" then accept;
                  reject;
              }

              filter import_from_cilium {
                  accept;
              }

              protocol bgp pve_upstream {
                  description "PVE FRR link-local (AS 4200001000)";
                  local as ${4210000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])};
                  neighbor fe80::%ens18 as 4200001000;
                  interface "ens18";
                  multihop 2;

                  ipv4 {
                      import filter import_from_pve;
                      export filter export_to_pve;
                      extended next hop on;  # Enable MP-BGP
                  };

                  ipv6 {
                      import filter import_from_pve;
                      export filter export_to_pve;
                  };

                  hold time 90;
                  keepalive time 30;
                  graceful restart on;
              }

              protocol bgp cilium_v4 {
                  description "Cilium BGP IPv4 (AS ${4220000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])})";
                  local as ${4210000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])};
                  neighbor 127.0.0.1 as ${4220000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])};
                  passive on;
                  multihop 2;
                  ipv4 {
                      import filter import_from_cilium;
                      export filter export_to_cilium;
                  };
                  hold time 90;
                  keepalive time 30;
                  graceful restart on;
              }

              protocol bgp cilium_v6 {
                  description "Cilium BGP IPv6 (AS ${4220000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])})";
                  local as ${4210000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])};
                  neighbor ::1 as ${4220000000 + (var.cluster_id * 1000) + tonumber(split(".", node.public_ipv4)[3])};
                  passive on;
                  multihop 2;
                  ipv6 {
                      import filter import_from_cilium;
                      export filter export_to_cilium;
                  };
                  hold time 90;
                  keepalive time 30;
                  graceful restart on;
              }
            mountPath: /usr/local/etc/bird.conf
        EXTENSION_CONFIG
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
