include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "image" {
  config_path = "../../artifacts/registry"

  mock_outputs = {
    talos_image_file_ids = {
      "pve01" = "resources:iso/mock-talos-image.iso"
      "pve02" = "resources:iso/mock-talos-image.iso"
      "pve03" = "resources:iso/mock-talos-image.iso"
    }
    talos_image_file_name  = "mock-talos-image.iso"
    talos_image_id         = "mock-schematic-id"
    talos_version          = "v1.12.1"
    kubernetes_version     = "1.34.1"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

locals {
  # Read centralized infrastructure configurations
  proxmox_infra    = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra    = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  credentials      = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file     = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals

  # Test environment configuration
  tenant_id      = 101
  bgp_asn_base   = local.network_infra.bgp.asn_base  # 4210000000
  bgp_remote_asn = local.network_infra.bgp.remote_asn # 4200001000

  # Test VM definitions
  test_vms = {
    debtest01 = {
      vm_id     = 10141
      ip_suffix = 41
      node_name = "pve01"
    }
    debtest02 = {
      vm_id     = 10142
      ip_suffix = 42
      node_name = "pve02"
    }
  }
}

# Generate provider configuration
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

# Generate main.tf with module calls for each VM
generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {}

  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.89.0" }
    sops    = { source = "carlpett/sops", version = "~> 1.3.0" }
    talos   = { source = "siderolabs/talos", version = "~> 0.9.0" }
  }
}

variable "region" {
  type        = string
  description = "Region identifier (injected by root terragrunt)"
  default     = "home-lab"
}

%{ for name, vm in local.test_vms ~}
module "${name}" {
  source = "../../../modules/talos_test_vm"

  vm_name = "${name}"
  vm_id   = ${vm.vm_id}

  proxmox = {
    node_name    = "${vm.node_name}"
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.proxmox_infra.storage.vm_datastore}"
  }

  vm_resources = {
    cpu_cores = 2
    memory_mb = 2048
    disk_gb   = 20
  }

  network = {
    bridge       = "vnet${local.tenant_id}"
    mtu          = 1450
    ipv4_address = "10.${local.tenant_id}.0.${vm.ip_suffix}"
    ipv4_netmask = "255.255.255.0"
    ipv4_gateway = "10.${local.tenant_id}.0.254"
    ipv6_address = "fd00:${local.tenant_id}::${vm.ip_suffix}"
    ipv6_prefix  = 64
    ipv6_gateway = "fd00:${local.tenant_id}::fffe"
  }

  loopback = {
    ipv4 = "10.${local.tenant_id}.254.${vm.ip_suffix}"
    ipv6 = "fd00:${local.tenant_id}:fe::${vm.ip_suffix}"
  }

  dns_servers = [
    "${local.network_infra.dns_servers.ipv6}",
    "${local.network_infra.dns_servers.ipv4}"
  ]

  bgp_config = {
    local_asn     = ${local.bgp_asn_base + local.tenant_id * 1000 + vm.ip_suffix}
    router_id     = "10.${local.tenant_id}.254.${vm.ip_suffix}"
    upstream_peer = "fd00:${local.tenant_id}::fffe"
    upstream_asn  = ${local.bgp_remote_asn}
  }

  # Talos image and configuration
  talos_image_file_id = "${dependency.image.outputs.talos_image_file_ids[vm.node_name]}"
  talos_version       = "${dependency.image.outputs.talos_version}"
  kubernetes_version  = "${dependency.image.outputs.kubernetes_version}"

  # System extensions (same as production cluster)
  system_extensions = ${jsonencode(concat(
    local.install_schematic.install_system_extensions,
    local.install_schematic.install_custom_extensions
  ))}

  kernel_args = ${jsonencode(local.install_schematic.install_kernel_args)}
}

output "${name}_info" {
  value = {
    vm_id          = module.${name}.vm_id
    vm_name        = module.${name}.vm_name
    ipv4_address   = module.${name}.ipv4_address
    ipv6_address   = module.${name}.ipv6_address
    bgp_asn        = module.${name}.bgp_asn
    talosctl_cmd   = module.${name}.talosctl_command
  }
}

%{ endfor ~}
EOF
}
