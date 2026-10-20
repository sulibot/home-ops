include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Onward design review site for review.sulibot.com.
#
# Invited reviewers sign in with email and password, mark and rank design
# options and comment; most of them open it on a phone from a QR code. Auth
# and data are the Supabase project `onward-review`, whose auth settings live
# in services/supabase-onward-review.
#
# This unit owns the public DNS record and the Worker route. The site bundle is
# a static, assets-only Worker named `sulibot-design-review`, deployed with
# Wrangler from the Onward repo's `tools/design-review/` (its wrangler.jsonc);
# keeping the application artifact out of Terraform follows the same split as
# cloudflare-sulibot-www. The Worker must exist before this applies, because
# Cloudflare refuses a route to a missing script.
#
# There is deliberately no Cloudflare Access application for this hostname.
# It is a public sign-in site; the people reviewing are not in Access.
#
# Runbook: docs/runbooks/design-review-site.md

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
  zone_id  = data.sops_file.secrets.data["cloudflare_zone_id"]
  hostname = "review.sulibot.com"
  worker   = "sulibot-design-review"
}

# A Worker route needs a proxied DNS record to attach to. TEST-NET-1 is never
# contacted while the proxy and Worker route are active, and it cannot expose
# an accidental origin if the proxy is disabled.
resource "cloudflare_dns_record" "site" {
  zone_id = local.zone_id
  name    = local.hostname
  type    = "A"
  content = "192.0.2.1"
  ttl     = 1
  proxied = true
  comment = "Onward design review site. Managed by terragrunt: services/cloudflare-sulibot-review."
}

# The application bundle is deployed separately with Wrangler. This resource
# makes routing a reviewable infrastructure change instead of a side effect of
# an application deployment.
resource "cloudflare_workers_route" "site" {
  zone_id = local.zone_id
  pattern = "$${local.hostname}/*"
  script  = local.worker

  depends_on = [cloudflare_dns_record.site]
}

output "hostname" {
  value = local.hostname
}
EOF
}
