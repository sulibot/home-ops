include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Email authentication DNS for sulibot.com.
#
# A separate unit from `cloudflare-access` on the one-unit-per-service
# convention, and for a reason beyond convention: that unit owns Zero Trust
# policies and tunnel ingress, and an email DNS change should not be able to
# churn an Access policy on the way past. Different concern, different blast
# radius, different reason to run an apply.
#
# WHY THESE RECORDS ARE NOT IN external-dns
#
# `sulibot.com` is otherwise managed by external-dns
# (kubernetes/apps/tier-1-infrastructure/cloudflare-dns), which runs with
# `--force-default-targets` -- documented as "Force the application of
# --default-targets, overriding any targets provided by the source". A
# DNSEndpoint CRD is a source, so an SPF or DMARC TXT declared that way would
# have its value replaced by the tunnel hostname: present, meaningless, and
# failing in a way that looks like a deliverability problem rather than a
# config error.
#
# They are safe from external-dns's `policy: sync` reaping, which only deletes
# records it owns via its `k8s.`-prefixed ownership TXTs. Do not create one for
# these.
#
# Runbook: docs/runbooks/plumb-email-dns.md

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

  # Where DMARC aggregate reports are sent.
  #
  # Deliberately on sulibot.com rather than an external inbox: a rua address on
  # a different domain requires THAT domain to publish an authorisation record
  # (<our-domain>._report._dmarc.<their-domain>), which we cannot create for
  # gmail.com. Same-domain needs no authorisation.
  #
  # This address must be routable, or reports go nowhere and p=none tells us
  # nothing. Cloudflare Email Routing handles inbound for this zone; the
  # forwarding rule is dashboard work, as the Zone.DNS token used here cannot
  # read or write Email Routing.
  dmarc_rua = "dmarc@sulibot.com"

  # p=none reports without quarantining, so a misconfigured DKIM shows up in
  # aggregate reports rather than by sending real password-reset emails to
  # spam. Move to quarantine once the reports are clean -- and only then, since
  # tightening ahead of the evidence is how legitimate mail gets dropped.
  dmarc_policy = "none"
}

# ---------------------------------------------------------------------------
# DMARC
# ---------------------------------------------------------------------------

resource "cloudflare_dns_record" "dmarc" {
  zone_id = local.zone_id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=$${local.dmarc_policy}; rua=mailto:$${local.dmarc_rua}; fo=1"
  ttl     = 1
  comment = "DMARC policy. Managed by terragrunt: services/cloudflare-email-dns."
}

# Adopts the record created by hand via the API on 2026-08-12 rather than
# failing the first apply with "record already exists". Safe to leave in place:
# an import block for a resource already in state is a no-op.
#
# nonsensitive() because the zone_id arrives from sops and OpenTofu refuses a
# sensitive import id. A Cloudflare zone ID is an account-scoped identifier,
# not a credential -- it appears in every API URL and grants nothing on its
# own. Unwrapping it here beats hardcoding it, which would put the same value
# in the file while also duplicating the source of truth.
import {
  to = cloudflare_dns_record.dmarc
  id = "$${nonsensitive(local.zone_id)}/4265e60c7adbe9d6bcf2e07873ababae"
}

# ---------------------------------------------------------------------------
# Sending domain
# ---------------------------------------------------------------------------
#
# NOT managed here yet, and deliberately so.
#
# Resend already has sulibot.com verified, with DKIM at
# resend._domainkey.sulibot.com and the return-path SPF at send.sulibot.com --
# both created outside Terraform before this unit existed. Importing them is
# worth doing, but it is a separate change from publishing DMARC, and adopting
# working mail records is the kind of thing to do deliberately rather than as a
# side effect.
#
# If Plumb's sending domain is later isolated to plumb.sulibot.com (see
# ENG-493), Resend will issue a DKIM record and a send.plumb SPF record. Those
# are new, so they should be authored here from the start rather than clicked
# in and imported afterwards.
EOF
}
