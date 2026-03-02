include "root" {
  path = find_in_parent_folders("root.hcl")
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

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "cloudflare" {
  api_token = data.sops_file.secrets.data["cloudflare_api_token"]
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
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
    sops       = { source = "carlpett/sops",         version = "~> 1.3.0" }
    null       = { source = "hashicorp/null",         version = "~> 3.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  account_id     = data.sops_file.secrets.data["cloudflare_account_id"]
  zone_id        = data.sops_file.secrets.data["cloudflare_zone_id"]
  tunnel_id      = data.sops_file.secrets.data["cloudflare_tunnel_id"]
  allowed_emails = split(" ", data.sops_file.secrets.data["cf_access_allowed_emails"])
  emergency_allowed_emails = [
    "bcwallace@gmail.com",
  ]
  effective_allowed_emails = distinct(concat(local.allowed_emails, local.emergency_allowed_emails))
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

# Wildcard CNAME → Cloudflare Tunnel.
# One record covers all *.sulibot.com — new apps need no DNS change.
resource "cloudflare_record" "wildcard_tunnel" {
  zone_id = local.zone_id
  name    = "*"
  type    = "CNAME"
  content = "$${local.tunnel_id}.cfargotunnel.com"
  proxied = true
}

# ---------------------------------------------------------------------------
# Identity Provider
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  account_id = local.account_id
  name       = "Authentik"
  type       = "oidc"
  config {
    client_id     = data.sops_file.secrets.data["cf_access_client_id"]
    client_secret = data.sops_file.secrets.data["cf_access_client_secret"]
    auth_url      = "https://auth.sulibot.com/application/o/authorize/"
    token_url     = "https://auth.sulibot.com/application/o/token/"
    certs_url     = "https://auth.sulibot.com/application/o/cloudflare-access/jwks/"
    scopes = ["openid", "email", "profile"]
    claims = ["email", "preferred_username"]
  }
}

# ---------------------------------------------------------------------------
# Wildcard application — all *.sulibot.com
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "wildcard" {
  account_id                = local.account_id
  name                      = "sulibot.com (*)"
  domain                    = "*.sulibot.com"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.authentik.id]
}

resource "cloudflare_zero_trust_access_policy" "wildcard_allow" {
  account_id     = local.account_id
  application_id = cloudflare_zero_trust_access_application.wildcard.id
  name           = "Allow approved users"
  decision       = "allow"
  precedence     = 1
  include {
    email = local.effective_allowed_emails
  }
}

# ---------------------------------------------------------------------------
# Bypass — auth.sulibot.com (Authentik must be reachable for OIDC callbacks)
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "authentik_bypass" {
  account_id       = local.account_id
  name             = "Authentik (bypass)"
  domain           = "auth.sulibot.com"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "authentik_bypass" {
  account_id     = local.account_id
  application_id = cloudflare_zero_trust_access_application.authentik_bypass.id
  name           = "Bypass"
  decision       = "bypass"
  precedence     = 1
  include {
    everyone = true
  }
}

# ---------------------------------------------------------------------------
# Bypass — atuin.sulibot.com (CLI sync tool, owns its own auth)
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "atuin_bypass" {
  account_id       = local.account_id
  name             = "Atuin (bypass)"
  domain           = "atuin.sulibot.com"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "atuin_bypass" {
  account_id     = local.account_id
  application_id = cloudflare_zero_trust_access_application.atuin_bypass.id
  name           = "Bypass"
  decision       = "bypass"
  precedence     = 1
  include {
    everyone = true
  }
}

# ---------------------------------------------------------------------------
# Bypass — immich.sulibot.com (mobile clients and app-native auth)
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "immich_bypass" {
  account_id       = local.account_id
  name             = "Immich (bypass)"
  domain           = "immich.sulibot.com"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "immich_bypass" {
  account_id     = local.account_id
  application_id = cloudflare_zero_trust_access_application.immich_bypass.id
  name           = "Bypass"
  decision       = "bypass"
  precedence     = 1
  include {
    everyone = true
  }
}

# ---------------------------------------------------------------------------
# 1Password sync — write CF Access credentials to the "authentik" item so
# the existing Authentik ExternalSecret picks them up automatically
# ---------------------------------------------------------------------------

resource "null_resource" "cf_access_1password_sync" {
  triggers = {
    client_id         = data.sops_file.secrets.data["cf_access_client_id"]
    client_secret_sha = sha256(data.sops_file.secrets.data["cf_access_client_secret"])
  }

  provisioner "local-exec" {
    command = <<-OPCMD
      op item edit authentik \
        --vault=Kubernetes \
        "CF_ACCESS_CLIENT_ID[text]=$${data.sops_file.secrets.data["cf_access_client_id"]}" \
        "CF_ACCESS_CLIENT_SECRET[password]=$${data.sops_file.secrets.data["cf_access_client_secret"]}" \
        "CF_ACCESS_CALLBACK_URL[text]=https://sulibot.cloudflareaccess.com/cdn-cgi/access/callback"
    OPCMD
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "wildcard_app_id" {
  value = cloudflare_zero_trust_access_application.wildcard.id
}

output "identity_provider_id" {
  value = cloudflare_zero_trust_access_identity_provider.authentik.id
}
EOF
}
