terraform {
  source = "../../../modules/proxmox_backup_jobs"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "versions" {
  path = find_in_parent_folders("common/versions.hcl")
}

include "credentials" {
  path = find_in_parent_folders("common/credentials.hcl")
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
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
}
EOF
}

inputs = {
  backup_jobs = {
    "daily-all-guests" = {
      enabled          = true
      storage          = "config"
      schedule         = "*-*-* 03:15"
      mode             = "snapshot"
      compress         = "zstd"
      mailnotification = "failure"
      mailto           = ["sulibot@gmail.com"]
      repeat_missed    = true
      stdexcludes      = true
      vmid = [
        "10212",
        "30253",
        "100061",
        "100062",
        "100063",
        "100064",
        "100065",
        "100066",
        "101011",
        "101012",
        "101013",
        "101021",
        "101022",
        "101023",
        "200051",
        "200052",
      ]
      notes_template   = "{{guestname}}"
      prune_backups = {
        "keep-daily"   = "7"
        "keep-weekly"  = "4"
        "keep-monthly" = "3"
      }
      performance = {
        max_workers = 1
      }
    }
  }
}
