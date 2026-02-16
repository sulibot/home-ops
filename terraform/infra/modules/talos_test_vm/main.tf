locals {
  # GoBGP ASN: local_asn + 10000000 (simulates Cilium's ASN)
  gobgp_asn = var.bgp_config.local_asn + 10000000

  # LoadBalancer simulation prefixes (advertised by GoBGP to simulate Cilium LB-IPAM)
  # These are arbitrary prefixes - not assigned to any interface
  lb_ipv4 = replace(var.loopback.ipv4, ".254.", ".250.")
  lb_ipv6 = replace(var.loopback.ipv6, ":fe::", ":250::")

  # Pod CIDR simulation (matches production cluster pattern)
  # Extract last octet from loopback IPv4 (e.g., 10.101.254.41 -> 41)
  # Pod CIDR: fd00:101:224:<node_id>::/64 (matches production fd00:101:224::/60)
  node_id = split(".", var.loopback.ipv4)[3]
  pod_cidr_v6 = "${local.cluster_id}:224:${local.node_id}::/64"

  # Extract the ULA prefix from the node IPv6 (e.g., fd00:101::41 -> fd00:101)
  cluster_id = split("::", var.network.ipv6_address)[0]

  # BIRD2 configuration
  # GoBGP peering uses localhost (::1) matching the production Cilium pattern
  bird2_config = templatefile("${path.module}/templates/bird2-config.conf.tpl", {
    hostname        = var.vm_name
    router_id       = var.bgp_config.router_id
    local_asn       = var.bgp_config.local_asn
    gobgp_asn       = local.gobgp_asn
    upstream_peer   = var.bgp_config.upstream_peer
    upstream_asn    = var.bgp_config.upstream_asn
    source_ipv6     = var.network.ipv6_address
    local_subnet_v6 = "${local.cluster_id}::/64"
  })

  # BIRD2 ExtensionServiceConfig (same format as production talos_config module)
  bird2_extension_config = templatefile("${path.module}/templates/bird2-extension-service-config.yaml.tpl", {
    bird2_config_conf = local.bird2_config
    hostname          = var.vm_name
  })

  # GoBGP configuration (TOML)
  # Connects from ::1 to BIRD2's loopback IPv6 — matching how real Cilium peers with BIRD2
  gobgp_config = <<-EOT
    [global.config]
      as = ${local.gobgp_asn}
      router-id = "${var.bgp_config.router_id}"
      local-address-list = ["::1"]
      port = -1

    # GoBGP connects TO bird2 at loopback_ipv6:179 from ::1 (same as Cilium in production)

    [[neighbors]]
      [neighbors.config]
        neighbor-address = "${var.loopback.ipv6}"
        peer-as = ${var.bgp_config.local_asn}
      [neighbors.transport.config]
        local-address = "::1"
        remote-port = 179

    # Define large communities (matching production)
    [[defined-sets.bgp-defined-sets.community-sets]]
      community-set-name = "CL_K8S_INTERNAL"
      community-list = ["${var.bgp_config.upstream_asn}:0:100"]

    [[defined-sets.bgp-defined-sets.community-sets]]
      community-set-name = "CL_K8S_PUBLIC"
      community-list = ["${var.bgp_config.upstream_asn}:0:200"]

    # Advertise Pod CIDRs (simulates Cilium pod CIDR advertisements)
    [[defined-sets.prefix-sets]]
      prefix-set-name = "pod-cidrs"
      [[defined-sets.prefix-sets.prefix-list]]
        ip-prefix = "${local.pod_cidr_v6}"

    # Advertise LoadBalancer IPs (simulates Cilium LB-IPAM behavior)
    [[defined-sets.prefix-sets]]
      prefix-set-name = "lb-ipv4"
      [[defined-sets.prefix-sets.prefix-list]]
        ip-prefix = "${local.lb_ipv4}/32"

    [[defined-sets.prefix-sets]]
      prefix-set-name = "lb-ipv6"
      [[defined-sets.prefix-sets.prefix-list]]
        ip-prefix = "${local.lb_ipv6}/128"

    [[policy-definitions]]
      name = "advertise-routes"
      # Pod CIDRs with Internal community
      [[policy-definitions.statements]]
        name = "accept-pod-cidrs"
        [policy-definitions.statements.conditions.match-prefix-set]
          prefix-set = "pod-cidrs"
          match-set-options = "any"
        [policy-definitions.statements.actions]
          route-disposition = "accept-route"
          [policy-definitions.statements.actions.bgp-actions.set-community]
            options = "add"
            [policy-definitions.statements.actions.bgp-actions.set-community.set-community-method]
              communities-list = ["${var.bgp_config.upstream_asn}:0:100"]

      # LoadBalancer IPs with Public community
      [[policy-definitions.statements]]
        name = "accept-lb-ipv4"
        [policy-definitions.statements.conditions.match-prefix-set]
          prefix-set = "lb-ipv4"
          match-set-options = "any"
        [policy-definitions.statements.actions]
          route-disposition = "accept-route"
          [policy-definitions.statements.actions.bgp-actions.set-community]
            options = "add"
            [policy-definitions.statements.actions.bgp-actions.set-community.set-community-method]
              communities-list = ["${var.bgp_config.upstream_asn}:0:200"]

      [[policy-definitions.statements]]
        name = "accept-lb-ipv6"
        [policy-definitions.statements.conditions.match-prefix-set]
          prefix-set = "lb-ipv6"
          match-set-options = "any"
        [policy-definitions.statements.actions]
          route-disposition = "accept-route"
          [policy-definitions.statements.actions.bgp-actions.set-community]
            options = "add"
            [policy-definitions.statements.actions.bgp-actions.set-community.set-community-method]
              communities-list = ["${var.bgp_config.upstream_asn}:0:200"]

    [global.apply-policy.config]
      export-policy-list = ["advertise-routes"]
  EOT

  # GoBGP route injection script
  # Nexthop is the node loopback (BIRD2's router-id) so PVE can route back
  # Simulates Cilium advertising both pod CIDRs and LoadBalancer IPs
  gobgp_inject_script = <<-EOT
    #!/bin/sh
    # Wait for GoBGP to be ready
    sleep 10
    # Inject routes into GoBGP RIB (simulates Cilium pod CIDR + LB-IPAM)
    while true; do
      # Pod CIDR advertisement (matches production Cilium behavior)
      gobgp global rib add -a ipv6 ${local.pod_cidr_v6} nexthop ${var.loopback.ipv6} 2>/dev/null && \
      # LoadBalancer IP advertisements
      gobgp global rib add -a ipv4 ${local.lb_ipv4}/32 nexthop ${var.bgp_config.router_id} 2>/dev/null && \
      gobgp global rib add -a ipv6 ${local.lb_ipv6}/128 nexthop ${var.loopback.ipv6} 2>/dev/null && \
      break
      sleep 5
    done
    # Keep container alive
    sleep infinity
  EOT

  # GoBGP static pod definition (runs on host network)
  # Both containers share a single hostPath volume for /etc/gobgpd
  # which includes cilium.conf and the scripts/ subdirectory
  gobgp_pod = {
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = "gobgp-cilium-sim"
      namespace = "kube-system"
    }
    spec = {
      hostNetwork    = true
      restartPolicy  = "Always"
      containers = [
        {
          name  = "gobgpd"
          image = var.gobgp_image
          args  = ["-f", "/etc/gobgpd/cilium.conf", "--disable-stdlog", "--log-level=info"]
          volumeMounts = [
            {
              name      = "gobgp-data"
              mountPath = "/etc/gobgpd"
              readOnly  = true
            }
          ]
        },
        {
          name    = "route-injector"
          image   = var.gobgp_image
          command = ["/bin/sh", "/etc/gobgpd/scripts/inject-lb-routes.sh"]
          volumeMounts = [
            {
              name      = "gobgp-data"
              mountPath = "/etc/gobgpd"
              readOnly  = true
            }
          ]
        }
      ]
      volumes = [
        {
          name = "gobgp-data"
          hostPath = {
            path = "/etc/gobgpd"
            type = "Directory"
          }
        }
      ]
    }
  }

  # Cloud-init network config for initial Talos installer boot reachability
  cloud_init_network = yamlencode({
    version = 1
    config = [
      {
        type = "physical"
        name = "ens18"
        mtu  = var.network.mtu
        subnets = [
          {
            type    = "static"
            address = var.network.ipv4_address
            netmask = var.network.ipv4_netmask
            gateway = var.network.ipv4_gateway
          },
          {
            type    = "static6"
            address = "${var.network.ipv6_address}/${var.network.ipv6_prefix}"
            gateway = var.network.ipv6_gateway
          }
        ]
      },
      {
        type    = "nameserver"
        address = var.dns_servers
      }
    ]
  })

  # Cloud-init user-data for sysctls during install phase
  cloud_init_user_data = <<-EOT
    #cloud-config
    bootcmd:
      - sysctl -w net.ipv6.conf.all.accept_ra=0
      - sysctl -w net.ipv6.conf.default.accept_ra=0
      - sysctl -w net.ipv6.conf.ens18.accept_ra=0
      - sysctl -w net.ipv6.conf.all.ndisc_notify=1
      - sysctl -w net.ipv6.conf.default.ndisc_notify=1
      - sysctl -w net.ipv4.conf.all.arp_notify=1
      - sysctl -w net.ipv4.conf.default.arp_notify=1
  EOT
}

# ----- Talos Machine Secrets -----

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# ----- Cloud-Init Files for Proxmox -----

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  node_name    = var.proxmox.node_name

  source_raw {
    data      = local.cloud_init_user_data
    file_name = "cloud-init-user-data-${var.vm_name}.yml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_network" {
  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  node_name    = var.proxmox.node_name

  source_raw {
    data      = local.cloud_init_network
    file_name = "cloud-init-network-${var.vm_name}.yml"
  }
}

# ----- Proxmox VM -----

resource "proxmox_virtual_environment_vm" "talos" {
  depends_on = [
    proxmox_virtual_environment_file.cloud_init_user_data,
    proxmox_virtual_environment_file.cloud_init_network
  ]

  vm_id     = var.vm_id
  name      = var.vm_name
  node_name = var.proxmox.node_name

  started         = true
  stop_on_destroy = true
  on_boot         = true
  reboot          = false

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf"

  efi_disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
  }

  cpu {
    sockets = 1
    cores   = var.vm_resources.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = var.vm_resources.memory_mb
  }

  # Boot disk for Talos installation
  disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.vm_resources.disk_gb
    cache        = "none"
    iothread     = true
    aio          = "io_uring"
  }

  # CD-ROM with Talos nocloud ISO
  cdrom {
    file_id   = var.talos_image_file_id
    interface = "ide0"
  }

  # Network interface on SDN VNet
  network_device {
    bridge = var.network.bridge
    mtu    = var.network.mtu
  }

  # Cloud-init for initial network during Talos installer boot
  initialization {
    datastore_id         = var.proxmox.vm_datastore
    user_data_file_id    = proxmox_virtual_environment_file.cloud_init_user_data.id
    network_data_file_id = proxmox_virtual_environment_file.cloud_init_network.id
  }

  agent {
    enabled = true
    trim    = true
  }

  vga {
    type = "std"
  }
}

# ----- Talos Machine Configuration -----

data "talos_machine_configuration" "this" {
  cluster_name     = var.vm_name
  cluster_endpoint = "https://${var.network.ipv4_address}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = [
    # Base machine config
    yamlencode({
      machine = {
        install = merge(
          {
            disk  = var.install_disk
            wipe  = false
            extensions = [
              for ext in var.system_extensions : { image = ext }
            ]
            extraKernelArgs = var.kernel_args
          },
          # Only include image if a custom installer is specified
          var.installer_image != "" ? { image = var.installer_image } : {}
        )
        time = {
          servers = ["time.cloudflare.com"]
        }
        sysctls = {
          "net.ipv6.conf.all.ndisc_notify"     = "1"
          "net.ipv6.conf.default.ndisc_notify"  = "1"
          "net.ipv4.conf.all.arp_notify"        = "1"
          "net.ipv4.conf.default.arp_notify"    = "1"
          "net.ipv4.ip_forward"                 = "1"
          "net.ipv6.conf.all.forwarding"        = "1"
          "net.ipv6.conf.all.accept_ra"         = "0"
          "net.ipv6.conf.default.accept_ra"     = "0"
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        network = {
          hostname = var.vm_name
          interfaces = [
            {
              interface = "ens18"
              mtu       = var.network.mtu
              addresses = [
                "${var.network.ipv6_address}/${var.network.ipv6_prefix}",
                "${var.network.ipv4_address}/24",
              ]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.network.ipv4_gateway
                  metric  = 2048
                },
                {
                  network = "::/0"
                  gateway = var.network.ipv6_gateway
                  metric  = 150
                },
              ]
            },
            {
              # Loopback for BIRD2 BGP identity — one address per IP family
              interface = "dummy0"
              addresses = [
                "${var.loopback.ipv6}/128",
                "${var.loopback.ipv4}/32",
              ]
            }
          ]
          nameservers = var.dns_servers
        }
        nodeLabels = {
          "bgp.bird2.asn"   = tostring(var.bgp_config.local_asn)
          "test.role"        = "bgp-test"
        }
        # GoBGP config files written to Talos ephemeral filesystem
        files = [
          {
            op          = "create"
            path        = "/etc/gobgpd/cilium.conf"
            content     = local.gobgp_config
            permissions = 420  # 0644
          },
          {
            op          = "create"
            path        = "/etc/gobgpd/scripts/inject-lb-routes.sh"
            content     = local.gobgp_inject_script
            permissions = 493  # 0755
          },
        ]
        # GoBGP static pod (simulates Cilium BGP control plane)
        pods = [
          local.gobgp_pod
        ]
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
        network = {
          cni = {
            name = "none" # No CNI needed for standalone BGP test
          }
        }
        proxy = {
          disabled = true
        }
      }
    }),
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.vm_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.network.ipv4_address]
  nodes                = [var.network.ipv4_address]
}

# ----- Apply Config and Bootstrap -----

# Wait for VM to be network reachable before applying Talos config
resource "null_resource" "wait_for_vm" {
  depends_on = [proxmox_virtual_environment_vm.talos]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ${var.vm_name} to be network reachable..."
      for i in $(seq 1 30); do
        if ping -c 1 -W 2 "${var.network.ipv4_address}" >/dev/null 2>&1; then
          echo "Node ${var.vm_name} is reachable"
          exit 0
        fi
        echo "  ... attempt $i/30, waiting 5s"
        sleep 5
      done
      echo "WARNING: ${var.vm_name} not reachable after 150s, proceeding anyway"
    EOT
  }
}

resource "talos_machine_configuration_apply" "this" {
  depends_on = [null_resource.wait_for_vm]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = var.network.ipv4_address
  endpoint                    = var.network.ipv4_address

  config_patches = [
    # BIRD2 ExtensionServiceConfig as a separate YAML document
    local.bird2_extension_config
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.network.ipv4_address
  endpoint             = var.network.ipv4_address
}
