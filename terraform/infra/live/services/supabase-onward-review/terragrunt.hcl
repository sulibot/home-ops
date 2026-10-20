include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Auth settings for the Supabase project `onward-review` (ref
# tczhezpecxlqwchmyhaj, us-east-1), the backend of the Onward design review
# site at https://reviews.sulibot.com (services/cloudflare-sulibot-review).
#
# Site URL, redirect allow-list, sign-up behaviour and SMTP are reviewable in a
# plan here rather than clicked in the dashboard. Change them in this file: the
# next apply reverts anything set another way.
#
# WHAT THIS DOES NOT OWN, deliberately:
#
#   The project. It was created through the Supabase connector, not Terraform,
#   and is referenced by ref only. Unlike supabase-plumb there is no
#   supabase_project resource, so nothing here can replace or delete it.
#
#   Schema, RLS and rounds. Versioned SQL in the Onward repo
#   (tools/design-review/schema.sql), applied as migrations; rounds and options
#   are data the admin edits on the site itself.
#
# CREDENTIALS
#
# `supabase_access_token`, plus the Resend key and sender shared with Plumb
# (`plumb_smtp_password`, `plumb_smtp_sender`), all in common/secrets.sops.yaml.
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

provider "supabase" {
  access_token = data.sops_file.secrets.data["supabase_access_token"]
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
    supabase = { source = "supabase/supabase", version = "~> 1.10" }
    sops     = { source = "carlpett/sops",     version = "~> 1.4.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  project_ref = "tczhezpecxlqwchmyhaj"
  site_url    = "https://reviews.sulibot.com"
}

resource "supabase_settings" "review" {
  project_ref = local.project_ref

  auth = jsonencode({
    site_url = local.site_url
    # The site builds every auth redirect from window.location.origin, so this
    # is every served host plus local development on any port (the README uses
    # 4817). review.sulibot.com was the first name and still serves the site.
    uri_allow_list = join(",", [
      "$${local.site_url}/**",
      "https://review.sulibot.com/**",
      "http://localhost:*/**",
    ])

    jwt_exp = 3600

    refresh_token_rotation_enabled        = true
    security_refresh_token_reuse_interval = 10

    # Open sign-up with no confirmation mail: a reviewer lands in the open
    # round the moment the account exists. The owner chose convenience over
    # proof of email ownership for this low-stakes site; reviewers, often on a
    # phone, must not wait on a mailbox.
    disable_signup     = false
    mailer_autoconfirm = true

    password_min_length = 8
    # NOT SET: password_hibp_enabled (refuse passwords found in known breaches,
    # the one warning the security advisor raises here). The API answers 402
    # "available on Pro Plans and up" on this free project, so the advisor
    # warning stays until the plan changes.

    # Only password-reset mail goes out, through Resend. Supabase's built-in
    # sender delivers to the organisation's team addresses alone, a few an
    # hour. Same key and verified domain (sulibot.com) as Plumb.
    smtp_admin_email      = data.sops_file.secrets.data["plumb_smtp_sender"]
    smtp_host             = "smtp.resend.com"
    smtp_port             = "587"
    smtp_user             = "resend"
    smtp_pass             = data.sops_file.secrets.data["plumb_smtp_password"]
    smtp_sender_name      = "Onward design review"
    rate_limit_email_sent = 100

    # Email and password only: no external providers are enabled.
  })
}

output "project_ref" {
  value = local.project_ref
}
EOF
}
