terraform {
  backend "local" {}

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "output_dir" {
  description = "Directory where generated PXE assets should be written."
  type        = string
}

variable "cluster_name" {
  description = "Name of the target cluster."
  type        = string
}

variable "region" {
  description = "Region injected by the shared Terragrunt root configuration."
  type        = string
  default     = ""
}

variable "talos_boot_entry_url" {
  description = "Stage-2 URL or script target for the Talos network boot entry."
  type        = string
}

variable "proxmox_boot_entry_url" {
  description = "Optional stage-2 HTTP(S) URL or script target for a Proxmox installer entry."
  type        = string
  default     = ""
}

variable "host_profiles" {
  description = "PXE host profiles keyed by host name."
  type = map(object({
    hostname        = string
    script_name     = string
    description     = string
    mac_address     = optional(string, "")
    talos_enabled   = bool
    proxmox_enabled = optional(bool, false)
  }))
}

locals {
  host_profile_names = sort(keys(var.host_profiles))
  host_menu_items = join("\n", [
    for name in local.host_profile_names :
    format("item %-20s %s", trimsuffix(var.host_profiles[name].script_name, ".ipxe"), var.host_profiles[name].description)
  ])
  host_menu_targets = join("\n\n", [
    for name in local.host_profile_names : <<-EOT
:${trimsuffix(var.host_profiles[name].script_name, ".ipxe")}
chain ${var.host_profiles[name].script_name}
    EOT
  ])
  host_auto_targets = join("\n", [
    for name in local.host_profile_names :
    trimspace(var.host_profiles[name].mac_address) != "" ?
    format("iseq $${net0/mac} %s && goto %s", upper(var.host_profiles[name].mac_address), trimsuffix(var.host_profiles[name].script_name, ".ipxe")) :
    ""
  ])

  boot_script = <<-EOT
    #!ipxe
    menu ${var.cluster_name} network boot
    item --gap --             ---------------- ${upper(var.cluster_name)} ----------------
    ${local.host_menu_items}
    ${var.proxmox_boot_entry_url != "" ? "item proxmox              Boot Proxmox installer" : ""}
    item --gap --             ---------------- Tools ----------------
    item shell                Drop to iPXE shell
    choose --default ${trimsuffix(var.host_profiles[local.host_profile_names[0]].script_name, ".ipxe")} --timeout 5000 target && goto ${"$"}{target}

    ${local.host_menu_targets}

    ${var.proxmox_boot_entry_url != "" ? ":proxmox\nchain ${var.proxmox_boot_entry_url}\n" : ""}

    :shell
    shell
  EOT

  autoexec_script = <<-EOT
    #!ipxe
    ${local.host_auto_targets}
    chain boot.ipxe
  EOT

  host_scripts = {
    for name, profile in var.host_profiles :
    profile.script_name => <<-EOT
      #!ipxe
      echo Boot profile: ${profile.hostname}
      echo Fetching stage-2 boot assets from ${profile.talos_enabled ? var.talos_boot_entry_url : "disabled"}
      ${profile.talos_enabled ? "chain ${var.talos_boot_entry_url}" : "echo Talos entry disabled && shell"}
    EOT
  }
}

resource "terraform_data" "output_dir" {
  provisioner "local-exec" {
    command = "mkdir -p '${var.output_dir}'"
  }
}

resource "local_file" "menu" {
  content  = local.boot_script
  filename = "${var.output_dir}/boot.ipxe"

  depends_on = [terraform_data.output_dir]
}

resource "local_file" "autoexec" {
  content  = local.autoexec_script
  filename = "${var.output_dir}/autoexec.ipxe"

  depends_on = [terraform_data.output_dir]
}

resource "local_file" "host_scripts" {
  for_each = local.host_scripts

  content  = each.value
  filename = "${var.output_dir}/${each.key}"

  depends_on = [terraform_data.output_dir]
}

resource "local_file" "host_profiles" {
  content  = jsonencode(var.host_profiles)
  filename = "${var.output_dir}/host-profiles.json"

  depends_on = [terraform_data.output_dir]
}

output "asset_dir" {
  description = "Directory containing generated PXE assets."
  value       = var.output_dir
}
