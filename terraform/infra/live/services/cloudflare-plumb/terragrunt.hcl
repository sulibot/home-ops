include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Cloudflare configuration for Plumb (plumb.sulibot.com).
#
# Owns DNS and the Worker route. It does NOT own the Worker script — that is a
# build artifact produced by `pnpm cf:deploy` from the plumb repo, the same
# split already used for kabinett-edge in cloudflare-access-cos. Terraform
# managing a bundled JS artifact would mean rebuilding it on every plan and
# storing it in state; wrangler does that job properly.
#
# Plumb is a PUBLIC product, so unlike every other hostname in this zone there
# is deliberately no Cloudflare Access application in front of it. Its own
# Supabase auth is the gate. Adding Access here would lock out every user who
# is not in the Zero Trust directory — which is all of them.
#
# Runbook: docs/runbooks/plumb-deploy.md

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
  hostname = "plumb.sulibot.com"
  worker   = "plumb"
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

# A Worker route needs a DNS record to attach to, even though no origin is
# ever contacted. 192.0.2.1 is the RFC 5737 TEST-NET-1 documentation address
# and is Cloudflare's documented convention for exactly this: proxied, so the
# request terminates at the edge and is handled by the Worker, and pointing at
# an address that is guaranteed never to route anywhere if the proxy is ever
# turned off by mistake.
resource "cloudflare_dns_record" "plumb" {
  zone_id = local.zone_id
  name    = local.hostname
  type    = "A"
  content = "192.0.2.1"
  ttl     = 1
  proxied = true
  comment = "Plumb Worker. Managed by terragrunt: services/cloudflare-plumb."
}

# ---------------------------------------------------------------------------
# Worker route
# ---------------------------------------------------------------------------

# Binds every path on the hostname to the Worker. The script itself is
# deployed by wrangler from the plumb repo; this resource only says which
# requests reach it.
#
# The route is created here rather than by wrangler's `routes` config on
# purpose: a route is infrastructure with a blast radius across the zone, and
# it should be reviewable in a plan rather than applied as a side effect of a
# developer running a deploy.
resource "cloudflare_workers_route" "plumb" {
  zone_id = local.zone_id
  pattern = "$${local.hostname}/*"
  script  = local.worker

  depends_on = [cloudflare_dns_record.plumb]
}

output "hostname" {
  value = local.hostname
}
EOF
}
