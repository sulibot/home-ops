include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Cloudflare Access for chief-of-staff-mcp (chief-of-staff repo, Cloudflare
# Worker). Sibling unit to the existing 880-line `cloudflare-access` unit
# rather than folded in -- same one-unit-per-service convention already
# used elsewhere (kanidm, smallstep-lxc, etc). Reuses the same sops
# secrets file / GCS backend pattern already established there.
#
# Deliberately NOT using cloudflare_zero_trust_access_mcp_server_portal
# (task 8a's working name, cloudflare_zero_trust_access_ai_controls_mcp_
# portal, was wrong -- corrected here via a fresh docs check). The portal
# resource requires a CNAME to Cloudflare's own shared gateway
# (gateway.agents.cloudflare.com) and is built for aggregating many MCP
# servers behind one browsable portal for a team -- more machinery than a
# single-user, single-server setup needs, and it routes every call through
# an extra Cloudflare-operated hop instead of straight to this Worker.
#
# Using the same pattern already proven for every other app in the
# sibling cloudflare-access unit instead: a plain `self_hosted` Access
# application on the Worker's own hostname, gated by a Service Auth
# policy (decision = "non_identity") tied to a service token -- confirmed
# via developers.cloudflare.com/cloudflare-one/access-controls/ai-controls/
# secure-mcp-servers/ ("Customer-managed... MCP server" section) and
# .../access-controls/service-credentials/service-tokens/ as the
# documented way for a non-interactive MCP client to authenticate with
# CF-Access-Client-Id / CF-Access-Client-Secret headers -- no browser
# OAuth flow, matching what task 8a actually needed.
#
# NOT verified live -- this environment has no reach to the GCS backend's
# impersonated service account or the real Cloudflare account, same limit
# as npm install/wrangler dev this session. Run `terragrunt plan` here
# yourself before applying.

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
  source_file = "$${path.module}/../../common/secrets.sops.yaml"
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
  backend "gcs" {}

  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
    sops       = { source = "carlpett/sops",         version = "~> 1.4.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  account_id = data.sops_file.secrets.data["cloudflare_account_id"]

  # Must match whatever custom domain task 8c attaches to the deployed
  # Worker (via wrangler, not Terraform -- Terragrunt owns the Access
  # policy, wrangler owns the code push and the Worker's own custom-domain
  # route/DNS record, same GitOps/Terraform split as the rest of this
  # infra). Update this if the actual chosen hostname ends up different.
  hostname = "chief-of-staff-mcp.sulibot.com"
}

# Long-lived (1 year) credential for the MCP client(s) calling this
# Worker -- an AI agent session, not a human browser, so there's no IdP
# login to redirect to. client_id/client_secret are Terraform outputs
# below (client_secret marked sensitive); read them with `terragrunt
# output` after apply and store them yourself -- this Terraform code has
# no capability to write to 1Password, same limit noted throughout
# chief-of-staff's own docs.
resource "cloudflare_zero_trust_access_service_token" "chief_of_staff_mcp" {
  account_id = local.account_id
  name       = "chief-of-staff-mcp"
  duration   = "8760h"

  lifecycle {
    create_before_destroy = true
  }
}

# Plain self_hosted app, same pattern as every other app in the sibling
# cloudflare-access unit -- not the AI Controls MCP portal/gateway
# resource (see file header for why). auto_redirect_to_identity is false
# and no allowed_idps are set: this app is Service-Auth-only, no human
# ever logs into it via browser.
resource "cloudflare_zero_trust_access_application" "chief_of_staff_mcp" {
  account_id                 = local.account_id
  name                       = "chief-of-staff-mcp"
  domain                     = local.hostname
  type                       = "self_hosted"
  session_duration           = "24h"
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false

  policies = [{
    name       = "Service token"
    decision   = "non_identity"
    precedence = 1
    include = [{
      service_token = {
        token_id = cloudflare_zero_trust_access_service_token.chief_of_staff_mcp.id
      }
    }]
  }]
}

# ENG-459: Slack's slash-command POSTs to /slack/capture on this same
# Worker/hostname, but Slack can't present the service token above (it
# authenticates the request itself via X-Slack-Signature, verified in
# the Worker -- see apps/edge/src/slack.ts in kabinett). Access resolves
# overlapping applications on one hostname by most-specific-path-first,
# so this narrower app takes precedence over the broader one above for
# exactly this one path, leaving the MCP endpoint's auth untouched.
resource "cloudflare_zero_trust_access_application" "chief_of_staff_mcp_slack_capture" {
  account_id                 = local.account_id
  name                       = "chief-of-staff-mcp-slack-capture"
  domain                     = "$${local.hostname}/slack/capture"
  type                       = "self_hosted"
  session_duration           = "24h"
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false

  policies = [{
    name       = "Bypass for Slack signature verification"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}

output "service_token_client_id" {
  value = cloudflare_zero_trust_access_service_token.chief_of_staff_mcp.client_id
}

output "service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.chief_of_staff_mcp.client_secret
  sensitive = true
}

output "access_application_id" {
  value = cloudflare_zero_trust_access_application.chief_of_staff_mcp.id
}
EOF
}
