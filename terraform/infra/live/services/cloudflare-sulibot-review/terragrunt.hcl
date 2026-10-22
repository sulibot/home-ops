include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Podium, Sulibot's design review site, at podium.sulibot.com. The earlier names
# reviews.sulibot.com, review.sulibot.com and reviewer.sulibot.com redirect to it.
#
# Invited reviewers sign in with email and password, mark and rank design
# options and comment; most of them open it on a phone from a QR code. Auth
# and data are the Supabase project `onward-review`, whose auth settings live
# in services/supabase-onward-review.
#
# This unit owns the public DNS records and the Worker routes. The site bundle is
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
  zone_id = data.sops_file.secrets.data["cloudflare_zone_id"]
  # podium.sulibot.com is the public name (the product was renamed Podium on
  # 2026-10-21). The earlier names keep a proxied record so links and QR codes
  # already handed out still work: a redirect rule sends them to podium.sulibot.com
  # with the path and query kept. Only the public name routes to the Worker.
  canonical = "podium.sulibot.com"
  legacy    = toset(["reviews.sulibot.com", "review.sulibot.com", "reviewer.sulibot.com"])
  hostnames = setunion(toset([local.canonical]), local.legacy)
  worker    = "sulibot-design-review"
}

# A Worker route needs a proxied DNS record to attach to. TEST-NET-1 is never
# contacted while the proxy and Worker route are active, and it cannot expose
# an accidental origin if the proxy is disabled.
resource "cloudflare_dns_record" "site" {
  for_each = local.hostnames

  zone_id = local.zone_id
  name    = each.key
  type    = "A"
  content = "192.0.2.1"
  ttl     = 1
  proxied = true
  comment = "Podium (design review site). Managed by terragrunt: services/cloudflare-sulibot-review."
}

# The application bundle is deployed separately with Wrangler. This resource
# makes routing a reviewable infrastructure change instead of a side effect of
# an application deployment.
resource "cloudflare_workers_route" "site" {
  for_each = toset([local.canonical])

  zone_id = local.zone_id
  pattern = "$${each.key}/*"
  script  = local.worker

  depends_on = [cloudflare_dns_record.site]
}

# The earlier names redirect to the public one, keeping the path and query, so a
# share link such as https://reviews.sulibot.com/r/round-1 still opens the round.
# A zone has one ruleset per phase; this unit owns the dynamic-redirect phase.
resource "cloudflare_ruleset" "legacy_redirect" {
  zone_id = local.zone_id
  name    = "Podium: earlier hostnames redirect to podium.sulibot.com"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    description = "reviews, review and reviewer .sulibot.com -> podium.sulibot.com"
    expression  = format("(http.host in {%s})", join(" ", [for h in sort(tolist(local.legacy)) : format("%q", h)]))
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code = 301
        target_url = {
          expression = format("concat(%q, http.request.uri.path, if(len(http.request.uri.query) > 0, concat(\"?\", http.request.uri.query), \"\"))", format("https://%s", local.canonical))
        }
        preserve_query_string = false
      }
    }
    enabled = true
  }]

  depends_on = [cloudflare_dns_record.site]
}

# The unit started with one hostname and unkeyed resources.
moved {
  from = cloudflare_dns_record.site
  to   = cloudflare_dns_record.site["review.sulibot.com"]
}

moved {
  from = cloudflare_workers_route.site
  to   = cloudflare_workers_route.site["review.sulibot.com"]
}

output "hostnames" {
  value = local.hostnames
}
EOF
}
