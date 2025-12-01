# live/golden/images/terragrunt.hcl

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  globals = read_terragrunt_config(find_in_parent_folders("common/globals.hcl")).locals
  secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/live/common/secrets.sops.yaml"))
  #  cluster = read_terragrunt_config(find_in_parent_folders("cluster.tfvars")).inputs

  images = {
    #    debian_12 = {
    #      path      = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    #      file_name = "debian-12-generic-amd64.img"
    ##      checksum  = "sha256:..."   # Replace with actual checksum if you have it
    #    }
    debian_12_backports = {
      path      = "https://cloud.debian.org/images/cloud/bookworm-backports/latest/debian-12-backports-generic-amd64.qcow2"
      file_name = "debian-12-backports-generic-amd64.img"
      #      checksum  = "sha256:..."   # Replace with actual checksum if you have it
    }
    debian_13 = {
      path      = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
      file_name = "debian-13-generic-amd64.img"
      #      checksum  = "sha256:..."   # Replace with actual checksum if you have it
    }
    #    debian_13_backports = {
    #      path      = "https://cloud.debian.org/images/cloud/trixie-backports/latest/debian-13-backports-generic-amd64.qcow2"
    #      file_name = "debian-13-backports-generic-amd64.img"
    ##      checksum  = "sha256:..."   # Replace with actual checksum if you have it
    #    }
    #    ubuntu_24 = {
    #      path      = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    #      file_name = "ubuntu-24-noble-cloudimg-amd64.img"
    ##      checksum  = "sha256:..."   # Replace with actual checksum if you have it
    #    }
    # Add more images as needed
  }
}

inputs = merge(
  local.globals,
  #  local.cluster,
  {
    pve_api_token_id     = local.secrets.pve_api_token_id
    pve_api_token_secret = local.secrets.pve_api_token_secret
    pve_endpoint         = local.secrets.pve_endpoint
    pve_username         = local.secrets.pve_username
    pve_password         = local.secrets.pve_password

    node_name    = "pve01"
    datastore_id = local.globals.snippet_datastore_id
    images       = local.images
  }
)
