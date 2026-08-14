include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Supabase Cloud project for Plumb.
#
# Replaces most of what was a dashboard checklist in
# docs/runbooks/onward-deploy.md. The official provider
# (supabase/terraform-provider-supabase) creates the project and manages its
# auth configuration, so site URL, redirect allow-list, SMTP, the Google
# provider and the before_user_created hook are all reviewable in a plan
# rather than clicked and forgotten.
#
# WHAT THIS DOES NOT OWN, deliberately:
#
#   Migrations. `supabase db push` from the plumb repo. Schema is versioned SQL
#   in that repo and belongs with the code; Terraform holding it would mean two
#   sources of truth for the same tables.
#
#   Email templates. The auth API takes them as inline strings, and the five
#   templates live in plumb/supabase/templates/*.html. Inlining ~9KB of HTML
#   into terragrunt.hcl to satisfy a principle would make both the templates
#   and this file worse. Pushed with the migrations instead.
#
# CREDENTIALS
#
# Needs `supabase_access_token` (a personal access token from
# supabase.com/dashboard/account/tokens) and `supabase_organization_id` in
# common/secrets.sops.yaml. Neither exists yet — see the runbook.
#
# Runbook: docs/runbooks/onward-deploy.md

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
  org_id   = data.sops_file.secrets.data["supabase_organization_id"]
  db_pass  = data.sops_file.secrets.data["supabase_plumb_db_password"]
  site_url = "https://onward.jobs"
}

resource "supabase_project" "plumb" {
  organization_id   = local.org_id
  name              = "plumb"
  database_password = local.db_pass
  # eu-west-2 (London): the users are UK-based and this is where the latency
  # that matters lives. Anthropic calls dominate wall-clock either way, but
  # every Server Component render round-trips to Postgres.
  region = "eu-west-2"

  lifecycle {
    # A project holds every user's evidence. Terraform should never be able to
    # replace it because an immutable attribute drifted.
    prevent_destroy = true
  }
}

resource "supabase_settings" "plumb" {
  project_ref = supabase_project.plumb.id

  auth = jsonencode({
    site_url = local.site_url
    # Wildcards, and every origin the app is actually served from. This drifted
    # once already: production was cut over to onward.jobs through the
    # Management API while this file still said plumb.sulibot.com, so the next
    # apply here would have rolled sign-in back to a host that no longer
    # exists. Terragrunt owns this setting; anything that writes it another way
    # is drift waiting to be reverted.
    uri_allow_list = join(",", [
      "$${local.site_url}/**",
      "https://www.onward.jobs/**",
      # Local development signs in against the hosted project.
      "http://localhost:3000/**",
    ])

    # One hour, matching supabase/config.toml. Deliberately NOT lengthened to
    # paper over session refresh: a long-lived access token cannot be revoked
    # before it expires, and ADR-028 established that the short one is handled
    # correctly without middleware.
    jwt_exp = 3600

    refresh_token_rotation_enabled = true
    security_refresh_token_reuse_interval = 10

    # ENABLED, but not open. The gate is the hook below, which refuses
    # provider=email while allowing OAuth. Setting this false would also block
    # Google sign-in for new users, which is the opposite of its purpose
    # (ADR-025).
    disable_signup = false
    mailer_autoconfirm = false

    # ENG-491. Without this the public /auth/v1/signup endpoint is open and
    # the account-enumeration oracle is back. It is the single most
    # consequential line in this file.
    hook_before_user_created_enabled = true
    hook_before_user_created_uri     = "pg-functions://postgres/public/before_user_created_gate"

    # ENG-493. Supabase's built-in sender only delivers to project team
    # members and caps near 2 messages an hour, so custom SMTP is not optional
    # for a product with users.
    smtp_admin_email = data.sops_file.secrets.data["plumb_smtp_sender"]
    smtp_host        = "smtp.resend.com"
    smtp_port        = "587"
    smtp_user        = "resend"
    smtp_pass        = data.sops_file.secrets.data["plumb_smtp_password"]
    # The From name on every auth email. It said "Plumb" in production long
    # after the rename, because it lives in Supabase's config rather than the
    # repo — no build, test, or grep over the codebase could have found it.
    smtp_sender_name = "Onward"
    rate_limit_email_sent = 100

    external_google_enabled       = true
    external_google_client_id     = data.sops_file.secrets.data["plumb_google_client_id"]
    external_google_secret        = data.sops_file.secrets.data["plumb_google_client_secret"]
    external_google_skip_nonce_check = false

    # ENG-505. Supabase calls this provider linkedin_oidc; the older `linkedin`
    # provider used LinkedIn's pre-OIDC API and is not what a new app gets.
    #
    # Scopes are openid/profile/email and that is all LinkedIn will grant
    # without partner approval — name, picture, locale, email. No work history.
    # The button copy says so, because on a job-search product "continue with
    # LinkedIn" otherwise reads as "import my career".
    external_linkedin_oidc_enabled   = true
    external_linkedin_oidc_client_id = data.sops_file.secrets.data["plumb_linkedin_client_id"]
    external_linkedin_oidc_secret    = data.sops_file.secrets.data["plumb_linkedin_client_secret"]

    password_min_length = 12
  })
}

output "project_ref" {
  value = supabase_project.plumb.id
}

# The Google OAuth client must list this as an authorised redirect URI, or
# Google refuses the flow. It is not knowable until the project exists, which
# is why it is an output rather than a hardcoded value in the runbook.
output "google_redirect_uri" {
  value = "https://$${supabase_project.plumb.id}.supabase.co/auth/v1/callback"
}
EOF
}
