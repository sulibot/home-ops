include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Authoritative DNS delegation for onward.jobs.
#
# Cloudflare owns the DNS zone. Porkbun remains the registrar and is managed
# only far enough to delegate the domain to the nameservers Cloudflare assigns.
# Porkbun credentials are injected at runtime by ./run.sh from 1Password; they
# are never rendered into generated Terraform files or stored in state.

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

provider "porkbun" {}
EOF
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "gcs" {}

  required_providers {
    cloudflare = { source = "cloudflare/cloudflare",   version = "~> 5.0" }
    porkbun    = { source = "marcfrederick/porkbun",  version = "~> 1.3.3" }
    sops       = { source = "carlpett/sops",           version = "~> 1.4.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  account_id = data.sops_file.secrets.data["cloudflare_account_id"]
  domain     = "onward.jobs"
}

resource "cloudflare_zone" "onward_jobs" {
  account = {
    id = local.account_id
  }
  name = local.domain
  type = "full"
}

resource "porkbun_nameservers" "onward_jobs" {
  domain      = local.domain
  # Porkbun returns the pair in reverse order. Match its canonical response so
  # refreshes do not produce an order-only diff for this list-valued resource.
  nameservers = reverse(cloudflare_zone.onward_jobs.name_servers)
}

# ---------------------------------------------------------------------------
# The Worker, at the apex and at www
# ---------------------------------------------------------------------------
#
# A proxied placeholder A record so the hostname exists in DNS, then a Workers
# route that intercepts it before anything is ever sent to 192.0.2.1. That
# address is TEST-NET-1 and deliberately unroutable — if the route were ever
# removed the request would fail rather than reach a stranger's server.
#
# Cloudflare has no rename for a Worker: changing the name in wrangler.jsonc
# deploys a second script and leaves this route pointed at the first. So the
# move from `plumb` to `onward` was ordered — deploy under the new name, push
# its secrets (a fresh Worker has none, so a route repointed first would serve
# 500s), then change this, then delete the old script.

locals {
  worker = "onward"
}

resource "cloudflare_dns_record" "apex" {
  zone_id = cloudflare_zone.onward_jobs.id
  name    = local.domain
  type    = "A"
  content = "192.0.2.1"
  ttl     = 1
  proxied = true
  comment = "Onward Worker. Managed by terragrunt: services/cloudflare-onward-jobs."
}

resource "cloudflare_dns_record" "www" {
  zone_id = cloudflare_zone.onward_jobs.id
  name    = "www.$${local.domain}"
  type    = "A"
  content = "192.0.2.1"
  ttl     = 1
  proxied = true
  comment = "Onward Worker. Managed by terragrunt: services/cloudflare-onward-jobs."
}

resource "cloudflare_workers_route" "apex" {
  zone_id    = cloudflare_zone.onward_jobs.id
  pattern    = "$${local.domain}/*"
  script     = local.worker
  depends_on = [cloudflare_dns_record.apex]
}

resource "cloudflare_workers_route" "www" {
  zone_id    = cloudflare_zone.onward_jobs.id
  pattern    = "www.$${local.domain}/*"
  script     = local.worker
  depends_on = [cloudflare_dns_record.www]
}

output "hostname" {
  value = local.domain
}

output "zone_id" {
  value = cloudflare_zone.onward_jobs.id
}

output "cloudflare_nameservers" {
  value = cloudflare_zone.onward_jobs.name_servers
}

output "zone_status" {
  value = cloudflare_zone.onward_jobs.status
}
EOF
}
