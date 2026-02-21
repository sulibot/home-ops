include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  dir           = get_terragrunt_dir()
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {}

  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.89.0" }
    sops    = { source = "carlpett/sops", version = "~> 1.3.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

# Injected by root.hcl extra_arguments
variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  ssh_public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))

  user_data = templatefile("${local.dir}/files/cloud-init-user-data.yaml.tpl", {
    ssh_public_key = local.ssh_public_key
  })

  network_config = <<-NETCFG
    version: 1
    config:
      - type: physical
        name: ens18
        mtu: 1500
        subnets:
          - type: static
            address: 10.200.0.51
            netmask: 255.255.255.0
            gateway: 10.200.0.254
          - type: static6
            address: fd00:200::51/64
            gateway: fd00:200::fffe
      - type: nameserver
        address:
          - ${local.network_infra.dns_servers.ipv6}
          - ${local.network_infra.dns_servers.ipv4}
  NETCFG
}

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = "${local.proxmox_infra.storage.datastore_id}"
  node_name    = "pve02"

  source_raw {
    data      = local.user_data
    file_name = "cloud-init-user-data-zot01.yml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_network" {
  content_type = "snippets"
  datastore_id = "${local.proxmox_infra.storage.datastore_id}"
  node_name    = "pve02"

  source_raw {
    data      = local.network_config
    file_name = "cloud-init-network-zot01.yml"
  }
}

resource "proxmox_virtual_environment_vm" "zot01" {
  depends_on = [
    proxmox_virtual_environment_file.cloud_init_user_data,
    proxmox_virtual_environment_file.cloud_init_network,
  ]

  vm_id     = 200015
  name      = "zot01"
  node_name = "pve02"

  started         = true
  stop_on_destroy = true
  on_boot         = true

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf"

  efi_disk {
    datastore_id = "${local.proxmox_infra.storage.vm_datastore}"
    file_format  = "raw"
  }

  cpu {
    sockets = 1
    cores   = 2
    type    = "host"
  }

  memory {
    dedicated = 2048
  }

  # Boot disk - reference existing cloud image on pve02 (managed by debtest02 state)
  disk {
    datastore_id = "${local.proxmox_infra.storage.vm_datastore}"
    file_id      = "resources:import/debian-trixie-cloud-amd64.qcow2"
    interface    = "scsi0"
    size         = 50
    cache        = "none"
    iothread     = true
    aio          = "io_uring"
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 200
    mtu     = 1500
  }

  initialization {
    datastore_id         = "${local.proxmox_infra.storage.vm_datastore}"
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

  boot_order = ["scsi0"]
}

resource "null_resource" "zot_install" {
  depends_on = [proxmox_virtual_environment_vm.zot01]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.zot01.id
    zot_config  = filemd5("${local.dir}/files/config.json")
    zot_service = filemd5("${local.dir}/files/zot.service")
  }

  connection {
    type        = "ssh"
    user        = "debian"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "10.200.0.51"
  }

  provisioner "file" {
    source      = "${local.dir}/files/config.json"
    destination = "/tmp/zot-config.json"
  }

  provisioner "file" {
    source      = "${local.dir}/files/zot.service"
    destination = "/tmp/zot.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "curl -fsSL -o /tmp/zot https://github.com/project-zot/zot/releases/download/v2.1.2/zot-linux-amd64",
      "sudo install -m 755 /tmp/zot /usr/local/bin/zot",
      "sudo useradd -r -s /usr/sbin/nologin zot || true",
      "sudo mkdir -p /var/lib/zot /etc/zot",
      "sudo chown zot:zot /var/lib/zot",
      "sudo install -m 644 /tmp/zot-config.json /etc/zot/config.json",
      "sudo install -m 644 /tmp/zot.service /etc/systemd/system/zot.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now zot",
      "sleep 3 && sudo systemctl is-active zot",
      "curl -sf http://localhost:5000/v2/ && echo Zot API OK",
    ]
  }
}

output "zot01_info" {
  value = {
    vm_id        = proxmox_virtual_environment_vm.zot01.id
    vm_name      = proxmox_virtual_environment_vm.zot01.name
    ipv4_address = "10.200.0.51"
    ipv6_address = "fd00:200::51"
  }
}

output "zot_endpoint" {
  value = "http://[fd00:200::51]:5000"
}
EOF
}
