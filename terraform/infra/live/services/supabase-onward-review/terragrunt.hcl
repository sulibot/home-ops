include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Auth settings for the Supabase project `onward-review` (ref
# tczhezpecxlqwchmyhaj, us-east-1), the backend of Reviewer, the design review
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
# (`plumb_smtp_password`, `plumb_smtp_sender`), and the Google OAuth client
# (`sulibot_reviews_google_client_id`, `sulibot_reviews_google_client_secret`),
# all in common/secrets.sops.yaml.
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

  # Auth mail: one sentence, one button, no images. Supabase fills in
  # {{ .ConfirmationURL }}; format() fills the sentence and the button label.
  mail_layout = <<-HTML
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;color:#1f2328;max-width:480px">
      <p style="margin:0 0 24px">%s</p>
      <p style="margin:0 0 24px"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 20px;border-radius:6px;background:#1f2328;color:#ffffff;text-decoration:none;font-weight:600">%s</a></p>
      <p style="margin:0;color:#59636e;font-size:14px">If you didn't ask for this, ignore it.</p>
    </div>
  HTML

  mail = {
    confirmation = {
      subject = "Confirm your email for Reviewer"
      body    = format(local.mail_layout, "Confirm this address to start reviewing designs with Reviewer.", "Confirm my email")
    }
    recovery = {
      subject = "Reset your Reviewer password"
      body    = format(local.mail_layout, "Choose a new password for your Reviewer account.", "Choose a new password")
    }
    email_change = {
      subject = "Confirm your new email"
      body    = format(local.mail_layout, "Confirm this is the new address for your Reviewer account.", "Confirm new email")
    }
  }
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

    # Open sign-up, validated by an email link: a new account gets a session
    # only after the reviewer clicks the confirmation mail. (Autoconfirm was on
    # at launch; the owner switched to email validation on 2026-10-19.)
    disable_signup     = false
    mailer_autoconfirm = false

    # Every emailed link (confirmation, recovery, email change, magic link)
    # stays valid for 24 hours, Supabase's maximum; reviewers often open the
    # mail long after signing up. There is no per-type setting.
    mailer_otp_exp = 86400

    password_min_length = 8
    # NOT SET: password_hibp_enabled (refuse passwords found in known breaches,
    # the one warning the security advisor raises here). The API answers 402
    # "available on Pro Plans and up" on this free project, so the advisor
    # warning stays until the plan changes.

    # Confirmation, password-reset and email-change mail go out through
    # Resend. Supabase's built-in sender delivers to the organisation's team
    # addresses alone, a few an hour. Same key and verified domain
    # (sulibot.com) as Plumb.
    smtp_admin_email      = data.sops_file.secrets.data["plumb_smtp_sender"]
    smtp_host             = "smtp.resend.com"
    smtp_port             = "587"
    smtp_user             = "resend"
    smtp_pass             = data.sops_file.secrets.data["plumb_smtp_password"]
    smtp_sender_name      = "Reviewer"
    rate_limit_email_sent = 100

    mailer_subjects_confirmation          = local.mail.confirmation.subject
    mailer_templates_confirmation_content = local.mail.confirmation.body
    mailer_subjects_recovery              = local.mail.recovery.subject
    mailer_templates_recovery_content     = local.mail.recovery.body
    mailer_subjects_email_change          = local.mail.email_change.subject
    mailer_templates_email_change_content = local.mail.email_change.body

    # Google sign-in beside email and password. The OAuth client
    # "sulibot-design-review" lives in Google Cloud; its id and secret are
    # also kept in 1Password (Kubernetes vault, item "Reviewer Google OAuth":
    # username = client id, credential = secret). Its authorised redirect URI is the
    # google_redirect_uri output below, its JavaScript origin
    # https://reviews.sulibot.com.
    external_google_enabled          = true
    external_google_client_id        = data.sops_file.secrets.data["sulibot_reviews_google_client_id"]
    external_google_secret           = data.sops_file.secrets.data["sulibot_reviews_google_client_secret"]
    external_google_skip_nonce_check = false
  })
}

output "project_ref" {
  value = local.project_ref
}

# The Google OAuth client must list this as an authorised redirect URI, or
# Google refuses the flow.
output "google_redirect_uri" {
  value = "https://$${local.project_ref}.supabase.co/auth/v1/callback"
}
EOF
}
