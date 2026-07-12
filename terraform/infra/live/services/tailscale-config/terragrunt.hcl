include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Tailnet control-plane configuration (ACL policy, route auto-approval, DNS).
#
# Why this unit exists: every Tailscale outage so far came from console-only
# state drifting from reality -- a split-DNS entry pointing at the NTP address
# instead of the resolver, and subnet routes waiting on manual approval. This
# unit codifies that state and derives route auto-approval directly from the
# same catalog entry that tail01/tail02 advertise from, so a route change in
# common/lxc-service-catalog.hcl is approved the moment the LXCs advertise it.
#
# CREDENTIALS: the existing `tailscale_oauth_client_*` sops keys are an
# auth-keys-only client (used by tailscale-lxc provisioning) and CANNOT manage
# ACLs or DNS. Create a second OAuth client at
# https://login.tailscale.com/admin/settings/oauth with scopes:
#   - policy_file (read/write)  -> ACL + autoApprovers
#   - dns (read/write)          -> split DNS / nameservers
# and add to common/secrets.sops.yaml as:
#   tailscale_config_oauth_client_id: ...
#   tailscale_config_oauth_client_secret: tskey-client-...
#
# FIRST APPLY: tailscale_acl replaces the ENTIRE tailnet policy file. Compare
# the policy below against https://login.tailscale.com/admin/acls before the
# first apply and fold in anything the console has that this file lacks.

locals {
  versions     = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  lxc_catalog  = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  tail_class   = local.lxc_catalog.services.tail
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  tailscale_tag    = local.tail_class.tailscale.tag
  advertise_routes = local.tail_class.tailscale.advertise_routes

  # Internal resolvers (single source of truth: network-infrastructure.hcl)
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  dns_ipv4      = local.network_infra.dns_servers.ipv4
  dns_ipv6      = local.network_infra.dns_servers.ipv6
  base_domain   = local.network_infra.base_domain
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
provider "sops" {}

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "tailscale" {
  oauth_client_id     = data.sops_file.secrets.data["tailscale_config_oauth_client_id"]
  oauth_client_secret = data.sops_file.secrets.data["tailscale_config_oauth_client_secret"]
  tailnet             = "-"
}
EOF2
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
terraform {
  backend "local" {}

  required_providers {
    tailscale = { source = "tailscale/tailscale", version = "${local.versions.provider_versions.tailscale}" }
    sops      = { source = "carlpett/sops", version = "~> 1.4.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  tailscale_tag    = "${local.tailscale_tag}"
  advertise_routes = ${jsonencode(local.advertise_routes)}
}

# Whole-tailnet policy file. Routes advertised by the tail LXCs (from the
# shared catalog) are auto-approved for their tag, as is exit-node offering.
resource "tailscale_acl" "this" {
  acl = jsonencode({
    tagOwners = {
      (local.tailscale_tag) = ["autogroup:admin"]
    }

    acls = [
      { action = "accept", src = ["*"], dst = ["*:*"] },
    ]

    ssh = [
      {
        action = "check"
        src    = ["autogroup:member"]
        dst    = ["autogroup:self"]
        users  = ["autogroup:nonroot", "root"]
      },
      {
        action = "accept"
        src    = ["autogroup:admin"]
        dst    = [local.tailscale_tag]
        users  = ["root"]
      },
    ]

    autoApprovers = {
      routes   = { for route in local.advertise_routes : route => [local.tailscale_tag] }
      exitNode = [local.tailscale_tag]
    }
  })
}

# Split DNS: sulibot.com resolves via the internal resolvers from anywhere on
# the tailnet (they are reachable through the advertised infra routes). This
# codifies the console fix that replaced the dead 10.255.255.254 entry.
resource "tailscale_dns_split_nameservers" "internal" {
  domain      = "${local.base_domain}"
  nameservers = ["${local.dns_ipv4}", "${local.dns_ipv6}"]
}

# Global nameserver so DNS keeps working when a tailscale exit node is
# selected (the client's LAN resolver becomes unreachable in that mode).
# override_local_dns stays false: only exit-node users need it, and MagicDNS
# prefers these resolvers automatically when set.
resource "tailscale_dns_nameservers" "global" {
  nameservers = ["${local.dns_ipv4}", "${local.dns_ipv6}"]
}

resource "tailscale_dns_preferences" "this" {
  magic_dns = true
}
EOF2
}
