
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
  gateway_api_crds_path = var.cilium_values_path != "" ? "${dirname(dirname(dirname(var.cilium_values_path)))}/0-crds/gateway-api-crds/gateway-api-crds-v1.3.0-experimental.yaml" : ""
  gateway_api_crds      = var.cilium_values_path != "" && fileexists(local.gateway_api_crds_path) ? file(local.gateway_api_crds_path) : ""
}

# Template Cilium Helm chart with values from Flux config
data "helm_template" "cilium" {
  name              = "cilium"
  repository        = "https://helm.cilium.io/"
  chart             = "cilium"
  version           = "1.18.4"
  namespace         = "kube-system"
  kube_version      = var.kubernetes_version
  skip_crds         = false
  include_crds      = true

  values = [
    local.cilium_values_yaml
  ]
}

# Generate cluster secrets (CA, bootstrap token, etc.)
resource "talos_machine_secrets" "cluster" {
  talos_version = var.talos_version
}

# Common configuration patches for all machines
locals {
  common_machine_config = yamlencode({
    machine = {
      install = {
        disk  = var.install_disk
        image = var.installer_image
        wipe  = true
      }
      kernel = {
        modules = [
          { name = "zfs" }
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
        hostDNS   = { enabled = true, forwardKubeDNSToHost = true }
      }
      kubelet = {
        nodeIP = {
          validSubnets = ["fd00:${var.cluster_id}::/64"] # Force IPv6 node IPs
        }
        clusterDNS = [
          "fd00:${var.cluster_id}:96::a", # IPv6 DNS service IP (10th IP in service CIDR)
          "10.${var.cluster_id}.96.10"    # IPv4 DNS service IP (10th IP in service CIDR)
        ]
      }
      # CDI (Container Device Interface) configuration for GPU passthrough
      # Required for intel-gpu-resource-driver to access Intel GPUs via CDI
      # Reference: https://broersma.dev/talos-linux-and-dynamic-resource-allocation-beta/
      files = [
        {
          content = <<-EOT
            [plugins]
              [plugins."io.containerd.grpc.v1.cri"]
                device_ownership_from_security_context = true
                [plugins."io.containerd.grpc.v1.cri".cdi]
                  enabled = true
                  spec_dirs = ["/var/cdi/static", "/var/cdi/dynamic"]
          EOT
          path = "/etc/cri/conf.d/20-cdi.part"
          op   = "create"
        }
      ]
    }
  })

  controlplane_cluster_config = yamlencode({
    cluster = {
      allowSchedulingOnControlPlanes = false
      network = {
        cni            = { name = "none" } # Cilium installed via inline manifests
        podSubnets     = [var.pod_cidr_ipv6, var.pod_cidr_ipv4]
        serviceSubnets = [var.service_cidr_ipv6, var.service_cidr_ipv4]
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
        extraArgs = {
          "runtime-config" = "admissionregistration.k8s.io/v1beta1=true"
          "feature-gates"  = "MutatingAdmissionPolicy=true"
        }
      }
      etcd = {
        advertisedSubnets = ["fd00:${var.cluster_id}::/64"] # Force etcd to use IPv6
      }
      # Install Gateway API CRDs and Cilium CNI via inline manifests
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
  })
}

# Generate per-node control plane configurations
data "talos_machine_configuration" "controlplane" {
  for_each = local.control_plane_nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    local.common_machine_config,
    local.controlplane_cluster_config,
    yamlencode({
      machine = {
        nodeLabels = {
          "topology.kubernetes.io/region" = "home-lab"
          "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
        }
        network = {
          hostname = each.value.hostname
          nameservers = var.dns_servers
          interfaces = [
            # Public network (ens18)
            {
              interface = "ens18"
              mtu       = 1500
              addresses = [
                "${each.value.public_ipv6}/64",
                "${each.value.public_ipv4}/24"
              ]
              routes = [
                {
                  network = "::/0"
                  gateway = "fd00:${var.cluster_id}::fffe"
                },
                {
                  network = "0.0.0.0/0"
                  gateway = "10.0.${var.cluster_id}.254"
                }
              ]
              vip = {
                ip = var.vip_ipv6
              }
            },
            # Mesh network (ens19)
            {
              interface = "ens19"
              mtu       = 8930
              addresses = [
                "${each.value.mesh_ipv6}/64",
                "${each.value.mesh_ipv4}/24"
              ]
              routes = [
                {
                  network = "fc00::/8"
                  gateway = "fc00:${var.cluster_id}::fffe"
                },
                {
                  network = "10.10.0.0/16"
                  gateway = "10.10.${var.cluster_id}.254"
                }
              ]
            }
          ]
        }
      }
    })
  ]
}

# Generate per-node worker configurations
data "talos_machine_configuration" "worker" {
  for_each = local.worker_nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    local.common_machine_config,
    yamlencode({
      machine = {
        nodeLabels = {
          "topology.kubernetes.io/region" = "home-lab"
          "topology.kubernetes.io/zone"   = "cluster-${var.cluster_id}"
        }
        network = {
          hostname = each.value.hostname
          nameservers = var.dns_servers
          interfaces = [
            # Public network (ens18)
            {
              interface = "ens18"
              mtu       = 1500
              addresses = [
                "${each.value.public_ipv6}/64",
                "${each.value.public_ipv4}/24"
              ]
              routes = [
                {
                  network = "::/0"
                  gateway = "fd00:${var.cluster_id}::fffe"
                },
                {
                  network = "0.0.0.0/0"
                  gateway = "10.0.${var.cluster_id}.254"
                }
              ]
            },
            # Mesh network (ens19)
            {
              interface = "ens19"
              mtu       = 8930
              addresses = [
                "${each.value.mesh_ipv6}/64",
                "${each.value.mesh_ipv4}/24"
              ]
              routes = [
                {
                  network = "fc00::/8"
                  gateway = "fc00:${var.cluster_id}::fffe"
                },
                {
                  network = "10.10.0.0/16"
                  gateway = "10.10.${var.cluster_id}.254"
                }
              ]
            }
          ]
        }
      }
    })
  ]
}

# Combine all per-node configurations for output
locals {
  machine_configs = merge(
    {
      for node_name, config in data.talos_machine_configuration.controlplane : node_name => {
        machine_type          = "controlplane"
        machine_configuration = config.machine_configuration
      }
    },
    {
      for node_name, config in data.talos_machine_configuration.worker : node_name => {
        machine_type          = "worker"
        machine_configuration = config.machine_configuration
      }
    }
  )
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
