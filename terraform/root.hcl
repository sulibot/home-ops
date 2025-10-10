# Terragrunt configuration for provider and required_providers file generation
remote_state {
  backend = "local"
  config = { path = "${path_relative_to_include()}/terraform.tfstate" }
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  backend "local" {}
}
EOF
}

locals {
  # Optional toggles (handy for CI / one-off runs)
  tg_generate_provider        = get_env("TG_GENERATE_PROVIDER", "true") == "true"
  tg_generate_required        = get_env("TG_GENERATE_REQUIRED_PROVIDERS", "true") == "true"
  tg_enable_routeros_provider = get_env("TG_ENABLE_ROUTEROS", "false") == "true"
}

# --- Provider file ---
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"  # <— overwrite so the root-generated provider is used
  contents  = local.tg_generate_provider ? (
    local.tg_enable_routeros_provider ? <<-EOF
      locals {
        use_token = trimspace(var.pve_api_token_id) != "" && trimspace(var.pve_api_token_secret) != ""
      }

      provider "proxmox" {
        endpoint  = var.pve_endpoint
        api_token = local.use_token ? "$${var.pve_api_token_id}=$${var.pve_api_token_secret}" : null
        username  = local.use_token ? null : var.pve_username
        password  = local.use_token ? null : var.pve_password
        insecure  = true

        # ---- SSH config used for uploading snippets/files to nodes ----
        ssh {
          username    = coalesce(var.pve_ssh_user, "root")
          agent       = var.pve_ssh_agent
          private_key = var.pve_ssh_private_key  # leave null to rely on ssh-agent
          # NOTE: host is not supported here; use PROXMOX_SSH_HOST env var if needed
        }
      }

      provider "routeros" {
        hosturl  = var.routeros_hosturl
        username = var.routeros_username
        password = var.routeros_password
        insecure = true
      }

      provider "external" {}
      provider "sops" {}
    EOF
    :
    <<-EOF
      locals {
        use_token = length(trimspace(var.pve_api_token_id)) > 0 && length(trimspace(var.pve_api_token_secret)) > 0
      }
      provider "proxmox" {
        endpoint  = var.pve_endpoint
        api_token = local.use_token ? "$${var.pve_api_token_id}=$${var.pve_api_token_secret}" : null
        username  = local.use_token ? null : var.pve_username
        password  = local.use_token ? null : var.pve_password
        insecure  = true   # <-- was 'nsecure'; fixed

        # ---- SSH config used for uploading snippets/files to nodes ----
        ssh {
          username    = coalesce(var.pve_ssh_user, "root")
          agent       = var.pve_ssh_agent
          private_key = var.pve_ssh_private_key  # leave null to rely on ssh-agent
          # NOTE: host is not supported here; use PROXMOX_SSH_HOST env var if needed
        }
      }

      provider "external" {}
      provider "sops" {}
    EOF
  ) : ""
}

# --- required_providers file ---
generate "required_providers" {
  path      = "required_providers.tf"
  # Also skip if a hand-written file exists in the module
  if_exists = "skip"
  contents  = local.tg_generate_required ? (
    local.tg_enable_routeros_provider ? <<-EOF
      terraform {
        required_providers {
          external = { source = "hashicorp/external",          version = "~> 2.2" }
          proxmox  = { source = "bpg/proxmox",                 version = "~> 0.83.0" }
          routeros = { source = "terraform-routeros/routeros", version = "~> 1.86.3" }
          sops     = { source = "carlpett/sops",               version = "~> 1.2.1" }
        }
      }
    EOF
    :
    <<-EOF
      terraform {
        required_providers {
          external = { source = "hashicorp/external",          version = "~> 2.2" }
          proxmox  = { source = "bpg/proxmox",                 version = "~> 0.83.0" }
          sops     = { source = "carlpett/sops",               version = "~> 1.2.1" }
        }
      }
    EOF
  ) : ""
}
