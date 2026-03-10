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
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
    sops       = { source = "carlpett/sops",         version = "~> 1.4.0" }
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
  tunnel_hostnames = [
    "auth.sulibot.com",
    "atuin.sulibot.com",
    "immich.sulibot.com",
    "immich-app.sulibot.com",
    "ha-google.sulibot.com",
    "home-assistant.sulibot.com",
    "home-assistant-app.sulibot.com",
  ]
  browser_protected_hostnames = [
    "immich.sulibot.com",
    "home-assistant.sulibot.com",
  ]
  allowed_emails = split(" ", data.sops_file.secrets.data["cf_access_allowed_emails"])
  emergency_allowed_emails = [
    "bcwallace@gmail.com",
  ]
  effective_allowed_emails = distinct(concat(local.allowed_emails, local.emergency_allowed_emails))
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

# Explicit host CNAMEs → Cloudflare Tunnel.
resource "cloudflare_dns_record" "tunnel_host" {
  for_each = toset(local.tunnel_hostnames)

  zone_id = local.zone_id
  name    = each.value
  type    = "CNAME"
  content = "$${local.tunnel_id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# ---------------------------------------------------------------------------
# Identity Provider
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  account_id = local.account_id
  name       = "Authentik"
  type       = "oidc"
  config = {
    client_id     = data.sops_file.secrets.data["cf_access_client_id"]
    client_secret = data.sops_file.secrets.data["cf_access_client_secret"]
    auth_url      = "https://auth.sulibot.com/application/o/authorize/"
    token_url     = "https://auth.sulibot.com/application/o/token/"
    certs_url     = "https://auth.sulibot.com/application/o/cloudflare-access/jwks/"
    scopes = ["openid", "email", "profile"]
    claims = ["email", "preferred_username"]
  }
}

# Browser apps protected by Cloudflare Access (explicit hostnames only).
resource "cloudflare_zero_trust_access_application" "browser_protected" {
  for_each = toset(local.browser_protected_hostnames)

  account_id                = local.account_id
  name                      = "$${each.value} (protected)"
  domain                    = each.value
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  enable_binding_cookie     = false
  http_only_cookie_attribute = false
  options_preflight_bypass  = false
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.authentik.id]
  policies = [{
    name       = "Allow approved users"
    decision   = "allow"
    precedence = 1
    include = [
      for email in local.effective_allowed_emails : {
        email = {
          email = email
        }
      }
    ]
  }]
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
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  policies = [{
    name       = "Bypass"
    decision   = "bypass"
    precedence = 1
    include = [{
      everyone = {}
    }]
  }]
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
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  policies = [{
    name       = "Bypass"
    decision   = "bypass"
    precedence = 1
    include = [{
      everyone = {}
    }]
  }]
}

# ---------------------------------------------------------------------------
# Immich app access — require WARP, no device posture checks
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "immich_warp" {
  account_id       = local.account_id
  name             = "Immich (WARP required)"
  domain           = "immich-app.sulibot.com"
  type             = "self_hosted"
  session_duration = "24h"
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  policies = [{
    name       = "Allow via WARP"
    decision   = "allow"
    precedence = 1
    include = [{
      everyone = {}
    }]
    require = [{
      auth_method = {
        auth_method = "warp"
      }
    }]
  }]
}

# ---------------------------------------------------------------------------
# Home Assistant app access — require WARP, no device posture checks
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "home_assistant_warp" {
  account_id       = local.account_id
  name             = "Home Assistant (WARP required)"
  domain           = "home-assistant-app.sulibot.com"
  type             = "self_hosted"
  session_duration = "24h"
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  policies = [{
    name       = "Allow via WARP"
    decision   = "allow"
    precedence = 1
    include = [{
      everyone = {}
    }]
    require = [{
      auth_method = {
        auth_method = "warp"
      }
    }]
  }]
}

# ---------------------------------------------------------------------------
# Home Assistant Google endpoint — bypass Access, Google performs OAuth with HA
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "home_assistant_google_bypass" {
  account_id                 = local.account_id
  name                       = "Home Assistant Google (bypass)"
  domain                     = "ha-google.sulibot.com"
  type                       = "self_hosted"
  session_duration           = "24h"
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  policies = [{
    name       = "Bypass"
    decision   = "bypass"
    precedence = 1
    include = [{
      everyone = {}
    }]
  }]
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

output "browser_protected_app_ids" {
  value = { for k, v in cloudflare_zero_trust_access_application.browser_protected : k => v.id }
}

output "identity_provider_id" {
  value = cloudflare_zero_trust_access_identity_provider.authentik.id
}
EOF
}
