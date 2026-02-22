include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  chr_version = "7.17.2"
  chr_vm_id   = 9900
  chr_node    = "pve01"
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
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

# RouterOS CHR test VM — VLAN 200 (same network as zot VM at 10.200.0.51)
#
# Pre-requisite: upload chr-${local.chr_version}.qcow2 to resources:import/
#   ssh root@10.10.0.1
#   IMPORT_DIR=$(pvesm path resources:import/debian-trixie-cloud-amd64.qcow2 | xargs dirname)
#   wget https://download.mikrotik.com/routeros/${local.chr_version}/chr-${local.chr_version}.img.zip
#   unzip chr-${local.chr_version}.img.zip
#   qemu-img convert -f raw -O qcow2 chr-${local.chr_version}.img chr-${local.chr_version}.qcow2
#   mv chr-${local.chr_version}.qcow2 $$IMPORT_DIR/
#
# First-boot setup (Proxmox console):
#   /ip/address/add address=10.200.0.250/24 interface=ether1
#   /ip/route/add gateway=10.200.0.254
#   /user/set admin password=<routeros_test_password from secrets.sops.yaml>
#   /ip/service/set [find name=www-ssl] disabled=no
resource "proxmox_virtual_environment_vm" "routeros_chr" {
  vm_id     = ${local.chr_vm_id}
  name      = "routeros-chr-test"
  node_name = "${local.chr_node}"
  started   = true
  stop_on_destroy = true
  on_boot   = false

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "${local.proxmox_infra.storage.vm_datastore}"
    file_id      = "resources:import/chr-${local.chr_version}.qcow2"
    interface    = "virtio0"
    size         = 1
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 200
    model   = "virtio"
  }

  boot_order = ["virtio0"]

  vga {
    type = "std"
  }
}

output "chr_vm_id" {
  value = proxmox_virtual_environment_vm.routeros_chr.vm_id
}

output "chr_instructions" {
  value = "First-boot: open Proxmox console, set IP 10.200.0.250/24, gateway 10.200.0.254, admin password, enable www-ssl service"
}
EOF
}
