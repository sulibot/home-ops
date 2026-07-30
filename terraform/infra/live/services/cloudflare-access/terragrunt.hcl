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
    null       = { source = "hashicorp/null",         version = "~> 3.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  account_id = data.sops_file.secrets.data["cloudflare_account_id"]
  zone_id    = data.sops_file.secrets.data["cloudflare_zone_id"]
  tunnel_id  = data.sops_file.secrets.data["cloudflare_tunnel_id"]
  cluster_104_tunnel_id = data.sops_file.secrets.data["cloudflare_tunnel_id_cluster_104"]

  bypass_apps = {
    "auth.sulibot.com"     = "Authentik"
    "idm.sulibot.com"      = "Kanidm"
    "plex.sulibot.com"     = "Plex"
    "seerr.sulibot.com"    = "Seerr"
    "requests.sulibot.com" = "Seerr"
  }

  email_only_apps = {}

  # Native-auth apps that used to sit here unauthenticated by Cloudflare (relying
  # solely on their own Authentik OIDC login) now all require WARP -- see
  # warp_only_apps below. Kept as an empty map for the pattern's sake.
  public_native_auth_apps = {}

  # Browser endpoints approved for Application Security mTLS. Keep the cutover
  # set empty until a client certificate is installed and the positive and
  # negative probes in docs/runbooks/cloudflare-application-mtls.md pass.
  main_tunnel_mtls_candidates = {
    "actual.sulibot.com"      = "Actual Budget"
    "filebrowser.sulibot.com" = "FileBrowser"
    "freshrss.sulibot.com"    = "FreshRSS"
    "immich.sulibot.com"      = "Immich"
    "karakeep.sulibot.com"    = "Karakeep"
    "paperless.sulibot.com"   = "Paperless"
  }

  cluster_104_mtls_candidates = {
    "hass.sulibot.com" = "Home Assistant Browser"
  }

  # Move one hostname at a time into this set only after certificate
  # distribution and monitoring are ready. Terraform then associates the
  # hostname with Cloudflare's managed CA, enforces mTLS at the WAF, removes
  # the old Access application, and narrows the WARP split-tunnel host list.
  application_mtls_cutover_hostnames = toset([
    "freshrss.sulibot.com",
    "immich.sulibot.com",
  ])

  main_tunnel_mtls_apps = {
    for hostname, name in local.main_tunnel_mtls_candidates : hostname => name
    if contains(local.application_mtls_cutover_hostnames, hostname)
  }

  cluster_104_mtls_apps = {
    for hostname, name in local.cluster_104_mtls_candidates : hostname => name
    if contains(local.application_mtls_cutover_hostnames, hostname)
  }

  application_mtls_apps = merge(
    local.main_tunnel_mtls_apps,
    local.cluster_104_mtls_apps,
  )

  # Apps whose origin is cluster-104's own Cloudflare Tunnel (separate tunnel
  # ID from the main cluster-101 tunnel) and still require WARP.
  cluster_104_warp_only_apps = merge({
    "music-assistant.sulibot.com" = "Music Assistant"
    "ma.sulibot.com"              = "Music Assistant"
    "music.sulibot.com"           = "Music Assistant"
  }, {
    for hostname, name in local.cluster_104_mtls_candidates : hostname => name
    if !contains(local.application_mtls_cutover_hostnames, hostname)
  })

  cluster_104_tunnel_apps = merge(
    local.cluster_104_warp_only_apps,
    local.cluster_104_mtls_apps,
  )

  home_assistant_google_hostname = "ha-google.sulibot.com"
  home_assistant_google_paths = [
    "/auth/*",
    "/frontend_latest/*",
    "/static/*",
    "/manifest.json",
    "/api/google_assistant",
  ]

  # Public endpoints that remain WARP-only because their native clients cannot
  # reliably present an Application Security client certificate.
  warp_only_apps = merge({
    "atuin.sulibot.com"       = "Atuin"
    "opencloud.sulibot.com"   = "OpenCloud"
  }, {
    for hostname, name in local.main_tunnel_mtls_candidates : hostname => name
    if hostname != "immich.sulibot.com" && !contains(local.application_mtls_cutover_hostnames, hostname)
  })

  # Immich keeps its existing WARP + email Access application until its mTLS
  # cutover. No email policy remains once the hostname enters the cutover set.
  warp_email_apps = {
    for hostname, name in { "immich.sulibot.com" = "Immich" } : hostname => name
    if !contains(local.application_mtls_cutover_hostnames, hostname)
  }

  app_private_dns_overrides = {
    "hass-app.sulibot.com" = {
      ips        = ["10.104.250.11", "fd00:104:250::11"]
      precedence = 100
    }
    # gateway-internal only (.11): the -app HTTPRoutes do not attach to
    # gateway-tunnel (.12), so pointing clients there would 404.
    "immich-app.sulibot.com" = {
      ips        = ["10.101.250.11", "fd00:101:250::11"]
      precedence = 101
    }
    "freshrss-app.sulibot.com" = {
      ips        = ["10.101.250.11", "fd00:101:250::11"]
      precedence = 102
    }
    "vikunja-app.sulibot.com" = {
      ips        = ["10.101.250.11", "fd00:101:250::11"]
      precedence = 103
    }
    # Same cluster-104 gateway-internal destination as hass-app.sulibot.com,
    # by convention with that entry - NOT independently confirmed live (no
    # WARP-connected access to cluster-104 at the time this was added). If
    # Music Assistant's own -app HTTPRoute attaches to a different gateway,
    # update these two entries together.
    "music-assistant-app.sulibot.com" = {
      ips        = ["10.104.250.11", "fd00:104:250::11"]
      precedence = 104
    }
    "music-app.sulibot.com" = {
      ips        = ["10.104.250.11", "fd00:104:250::11"]
      precedence = 105
    }
  }

  warp_private_routes = {
    "cluster-101-gateway-ipv4" = {
      network   = "10.101.250.0/24"
      tunnel_id = local.tunnel_id
    }
    "cluster-101-gateway-ipv6" = {
      network   = "fd00:101:250::/64"
      tunnel_id = local.tunnel_id
    }
    "cluster-104-gateway-ipv4" = {
      network   = "10.104.250.0/24"
      tunnel_id = local.cluster_104_tunnel_id
    }
    "cluster-104-gateway-ipv6" = {
      network   = "fd00:104:250::/64"
      tunnel_id = local.cluster_104_tunnel_id
    }

    # Full infra access via WARP, mirroring every range the Tailscale subnet
    # router (tailscale-lxc tail01/tail02) advertises today - replacing
    # reliance on that single router pair, which went offline entirely on
    # 2026-07-24 (both nodes simultaneously) and blocked all SSH/kubectl/
    # talosctl/MinIO access with no fallback path. All routed via cluster-101's
    # tunnel connector: it already proves out for the gateway/node ranges
    # above via standard pod->node fabric reachability. Reachability into the
    # non-tenant-101 ranges below (tenant 100/200, the infra loopback range)
    # depends on the tenant VRF's default-route leak (RM_GLOBAL_TO_VRF_V6
    # permit 10, PL_DEFAULT_V6 = ::/0) rather than an explicit PL_TENANT_V6
    # entry - plausible given that mechanism, but UNVERIFIED until tested
    # live post-apply. Test each one; do not assume the whole set works
    # because one range does.
    "cluster-101-nodes-ipv4" = {
      network   = "10.101.0.0/24"
      tunnel_id = local.tunnel_id
    }
    "cluster-101-nodes-ipv6" = {
      network   = "fd00:101::/64"
      tunnel_id = local.tunnel_id
    }
    "pve-mgmt-ipv4" = {
      network   = "10.10.0.0/24"
      tunnel_id = local.tunnel_id
    }
    "pve-mgmt-ipv6" = {
      network   = "fd00:10::/64"
      tunnel_id = local.tunnel_id
    }
    "tenant-100-ipv4" = {
      network   = "10.100.0.0/24"
      tunnel_id = local.tunnel_id
    }
    "tenant-100-ipv6" = {
      network   = "fd00:100::/64"
      tunnel_id = local.tunnel_id
    }
    "openbao-vip-ipv4" = {
      network   = "10.100.240.67/32"
      tunnel_id = local.tunnel_id
    }
    "openbao-vip-ipv6" = {
      network   = "fd00:100:0:240::67/128"
      tunnel_id = local.tunnel_id
    }
    "tenant-200-ipv4" = { # MinIO / s3.sulibot.com (Terraform state backend)
      network   = "10.200.0.0/24"
      tunnel_id = local.tunnel_id
    }
    "tenant-200-ipv6" = {
      network   = "fd00:200::/64"
      tunnel_id = local.tunnel_id
    }
    "infra-loopback-ipv4" = {
      network   = "10.255.0.0/24"
      tunnel_id = local.tunnel_id
    }
    "infra-loopback-ipv6" = {
      network   = "fd00:0:0:ffff::/64"
      tunnel_id = local.tunnel_id
    }
    "cluster-101-extra-ipv4" = {
      network   = "10.101.254.0/24"
      tunnel_id = local.tunnel_id
    }
    "cluster-104-extra-ipv4" = {
      network   = "10.104.254.0/24"
      tunnel_id = local.cluster_104_tunnel_id
    }
  }

  tunnel_hostnames = distinct(concat(
    keys(local.bypass_apps),
    keys(local.email_only_apps),
    keys(local.public_native_auth_apps),
    keys(local.warp_only_apps),
    keys(local.warp_email_apps),
    keys(local.main_tunnel_mtls_apps),
  ))

  allowed_emails = split(" ", data.sops_file.secrets.data["cf_access_allowed_emails"])
  emergency_allowed_emails = [
    "bcwallace@gmail.com",
    "sulibot@gmail.com",
    "bodawee@gmail.com",
    "sarah.kalas@gmail.com",
    "munirah.ahmad1@gmail.com",
    "leon.mccaughan@gmail.com",
    "barb.nykoruk@gmail.com",
    "safiyazc@gmail.com",
  ]
  effective_allowed_emails = distinct(concat(local.allowed_emails, local.emergency_allowed_emails))
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

# Explicit host CNAMEs → Cloudflare Tunnel.
resource "cloudflare_dns_record" "tunnel_host" {
  for_each = toset([
    for hostname in local.tunnel_hostnames : hostname
    if !startswith(hostname, "*.")
  ])

  zone_id = local.zone_id
  name    = each.value
  type    = "CNAME"
  content = "$${local.tunnel_id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# Home Assistant and Music Assistant run on cluster-104 and use the
# cluster-104 tunnel origin (a separate tunnel ID from cluster-101's).
resource "cloudflare_dns_record" "cluster_104_tunnel_host" {
  for_each = merge(
    local.cluster_104_tunnel_apps,
    { (local.home_assistant_google_hostname) = "Home Assistant Google" },
  )

  zone_id = local.zone_id
  name    = each.key
  type    = "CNAME"
  content = "$${local.cluster_104_tunnel_id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# The main tunnel is remotely managed by Cloudflare. Its pushed ingress
# configuration overrides the connector's local config file, so public origin
# rules must be owned here as well as mirrored in the Kubernetes bootstrap
# secret. Specific infrastructure hostnames precede the wildcard app gateway.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = local.account_id
  tunnel_id  = local.tunnel_id
  source     = "cloudflare"

  config = {
    ingress = [
      {
        hostname = "idm.sulibot.com"
        service  = "https://10.100.0.60:443"
        origin_request = {
          http2_origin       = true
          origin_server_name = "idm.sulibot.com"
        }
      },
      {
        hostname = "openbao.sulibot.com"
        service  = "http_status:404"
      },
      {
        hostname = "*.sulibot.com"
        service  = "https://cilium-gateway-gateway-tunnel.network.svc.cluster.local:443"
        origin_request = {
          http2_origin       = true
          no_tls_verify      = true
          origin_server_name = "sulibot.com"
        }
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

# WARP private app endpoints are not published as public DNS records and do
# not use Cloudflare Access. WARP clients resolve them to private gateway IPs
# and then route that private traffic through the matching Cloudflare Tunnel.
resource "cloudflare_zero_trust_gateway_policy" "app_private_dns_override" {
  for_each = local.app_private_dns_overrides

  account_id  = local.account_id
  name        = "Private app DNS: $${each.key}"
  description = "Resolve $${each.key} to the private Gateway endpoint for WARP clients."
  action      = "override"
  enabled     = true
  filters     = ["dns"]
  traffic     = format("dns.fqdn == %s", jsonencode(each.key))
  precedence  = each.value.precedence

  rule_settings = {
    override_ips = each.value.ips
  }
}

# Internal DNS for the -app hostnames is deliberately NOT managed here: each
# cluster's external-dns-mikrotik publishes them to RouterOS from the
# HTTPRoutes (with its TXT ownership registry), so internal records track the
# real gateway addresses automatically. This block only manages the WARP-side
# Gateway overrides. Do not add static RouterOS records for these names --
# unowned records block external-dns from writing its own (owner-id mismatch).
resource "cloudflare_zero_trust_tunnel_cloudflared_route" "app_private_route" {
  for_each = local.warp_private_routes

  account_id = local.account_id
  tunnel_id  = each.value.tunnel_id
  network    = each.value.network
  comment    = "Private app endpoint route for $${each.key}"
}

# ---------------------------------------------------------------------------
# Application Security mTLS
# ---------------------------------------------------------------------------

# Disable automatic WARP device-certificate provisioning. This is retained as
# an explicit false setting because Cloudflare's API exposes an editable
# singleton rather than a deletable resource.
resource "cloudflare_zero_trust_device_default_profile_certificates" "application_mtls" {
  zone_id = local.zone_id
  enabled = false
}

# Omitting mtls_certificate_id selects the account's active Cloudflare-managed
# CA. This resource owns the complete managed-CA hostname association set for
# this zone; import/reconcile any out-of-band associations before applying.
resource "cloudflare_certificate_authorities_hostname_associations" "application_mtls" {
  zone_id   = local.zone_id
  hostnames = sort(tolist(local.application_mtls_cutover_hostnames))
}

# There is currently no other zone entrypoint ruleset in this phase. If a
# custom-rule entrypoint is added out of band, import and merge it here before
# applying so this remains the single source of truth.
resource "cloudflare_ruleset" "application_mtls" {
  count = length(local.application_mtls_cutover_hostnames) > 0 ? 1 : 0

  zone_id     = local.zone_id
  name        = "Application Security mTLS"
  description = "Block selected browser endpoints unless Cloudflare verifies a non-revoked client certificate."
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [{
    action      = "block"
    description = "Require a valid Application Security client certificate"
    enabled     = true
    ref         = "require_application_mtls"
    expression = format(
      "(http.host in {%s} and ((not cf.tls_client_auth.cert_verified) or cf.tls_client_auth.cert_revoked))",
      join(" ", [for hostname in sort(tolist(local.application_mtls_cutover_hostnames)) : jsonencode(hostname)]),
    )
  }]

  depends_on = [
    cloudflare_certificate_authorities_hostname_associations.application_mtls,
  ]
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

resource "cloudflare_zero_trust_organization" "this" {
  account_id                  = local.account_id
  name                        = "sulibot.cloudflareaccess.com"
  auth_domain                 = "sulibot.cloudflareaccess.com"
  allow_authenticate_via_warp = true
}

# ---------------------------------------------------------------------------
# Device enrollment
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_policy" "warp_enrollment" {
  account_id = local.account_id
  name       = "WARP device enrollment"
  decision   = "allow"
  include = concat(
    [{
      email_domain = {
        domain = "sulibot.com"
      }
    }],
    [
      for email in local.effective_allowed_emails : {
        email = {
          email = email
        }
      }
    ]
  )
}

resource "cloudflare_zero_trust_access_application" "warp_enrollment" {
  account_id                = local.account_id
  type                      = "warp"
  # Cloudflare force-renames warp-type apps to "Warp Login App" server-side;
  # any other name here just produces perpetual plan drift.
  name                      = "Warp Login App"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.authentik.id]
  auto_redirect_to_identity = true
  policies = [{
    id         = cloudflare_zero_trust_access_policy.warp_enrollment.id
    precedence = 1
  }]
}

# ---------------------------------------------------------------------------
# Bypass apps
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "bypass" {
  for_each = local.bypass_apps

  account_id                 = local.account_id
  name                       = "$${each.value} (bypass)"
  domain                     = each.key
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
# Email-only apps
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "email_only" {
  for_each = local.email_only_apps

  account_id                 = local.account_id
  name                       = "$${each.value} (email)"
  domain                     = each.key
  type                       = "self_hosted"
  session_duration           = "24h"
  auto_redirect_to_identity  = true
  allow_authenticate_via_warp = true
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  allowed_idps               = [cloudflare_zero_trust_access_identity_provider.authentik.id]
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
# Cluster-104 WARP-only apps (Home Assistant, Music Assistant)
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "cluster_104_warp_only" {
  for_each = local.cluster_104_warp_only_apps

  account_id                 = local.account_id
  name                       = "$${each.value} (WARP only)"
  domain                     = each.key
  type                       = "self_hosted"
  session_duration           = "24h"
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

  depends_on = [cloudflare_ruleset.application_mtls]
}

# Google Assistant cloud-to-cloud needs unauthenticated access to Home
# Assistant's account-linking UI, the frontend assets it loads, and smart-home
# fulfillment. Keep this app path-scoped so the rest of the HA UI is not exposed
# through this hostname.
resource "cloudflare_zero_trust_access_application" "home_assistant_google_bypass" {
  account_id                 = local.account_id
  name                       = "Home Assistant Google (path bypass)"
  type                       = "self_hosted"
  session_duration           = "1h"
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = true
  destinations = [
    for path in local.home_assistant_google_paths : {
      type = "public"
      uri  = "https://$${local.home_assistant_google_hostname}$${path}"
    }
  ]
  policies = [{
    name       = "Bypass Google Assistant endpoints"
    decision   = "bypass"
    precedence = 1
    include = [{
      everyone = {}
    }]
  }]
}

# ---------------------------------------------------------------------------
# WARP-only apps
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "warp_only" {
  for_each = local.warp_only_apps

  account_id                 = local.account_id
  name                       = "$${each.value} (WARP only)"
  domain                     = each.key
  type                       = "self_hosted"
  session_duration           = "24h"
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

  depends_on = [cloudflare_ruleset.application_mtls]
}

# ---------------------------------------------------------------------------
# WARP + email apps
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "warp_email" {
  for_each = local.warp_email_apps

  account_id                 = local.account_id
  name                       = "$${each.value} (WARP + email)"
  domain                     = each.key
  type                       = "self_hosted"
  session_duration           = "24h"
  auto_redirect_to_identity  = true
  allow_authenticate_via_warp = true
  enable_binding_cookie      = false
  http_only_cookie_attribute = false
  options_preflight_bypass   = false
  allowed_idps               = [cloudflare_zero_trust_access_identity_provider.authentik.id]
  policies = [{
    name       = "Allow approved users via WARP"
    decision   = "allow"
    precedence = 1
    include = [
      for email in local.effective_allowed_emails : {
        email = {
          email = email
        }
      }
    ]
    require = [{
      auth_method = {
        auth_method = "warp"
      }
    }]
  }]

  depends_on = [cloudflare_ruleset.application_mtls]
}

# The single WARP profile applies on every network. Split Tunnel Include mode
# restricts the tunnel to WARP-dependent destinations and private app routes.
# General browsing and mTLS browser endpoints do not transit WARP. The user
# controls the unlocked switch; Cloudflare has no non-posture managed-network
# profile that automatically turns the iOS tunnel off.
resource "cloudflare_zero_trust_device_default_profile" "external" {
  account_id = local.account_id

  service_mode_v2   = { mode = "warp" }
  tunnel_protocol   = "masque"
  allow_mode_switch = false
  switch_locked     = false
  auto_connect      = 0

  include = concat(
    [
      { host = "sulibot.cloudflareaccess.com", description = "Zero Trust Access auth domain -- required in Include mode" },
      { address = "162.159.36.12/32", description = "Cloudflare Gateway block page" },
      { address = "162.159.46.12/32", description = "Cloudflare Gateway block page" },
    ],
    [
      for hostname, name in merge(
        local.cluster_104_warp_only_apps,
        local.warp_only_apps,
        local.warp_email_apps,
      ) : {
        host        = hostname
        description = "$${name}: WARP-dependent public endpoint"
      }
    ],
    [
      for name, route in local.warp_private_routes : {
        address     = route.network
        description = "Private app endpoint route: $${name}"
      }
    ]
  )
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

output "access_application_ids" {
  value = merge(
    { for k, v in cloudflare_zero_trust_access_application.bypass : k => v.id },
    { for k, v in cloudflare_zero_trust_access_application.email_only : k => v.id },
    { for k, v in cloudflare_zero_trust_access_application.cluster_104_warp_only : k => v.id },
    { (local.home_assistant_google_hostname) = cloudflare_zero_trust_access_application.home_assistant_google_bypass.id },
    { for k, v in cloudflare_zero_trust_access_application.warp_only : k => v.id },
    { for k, v in cloudflare_zero_trust_access_application.warp_email : k => v.id },
  )
}

output "identity_provider_id" {
  value = cloudflare_zero_trust_access_identity_provider.authentik.id
}

output "application_mtls_cutover_hostnames" {
  value = sort(tolist(local.application_mtls_cutover_hostnames))
}

# ---------------------------------------------------------------------------
# State-safe renames
# ---------------------------------------------------------------------------

moved {
  from = cloudflare_zero_trust_access_application.home_assistant_warp_only
  to   = cloudflare_zero_trust_access_application.cluster_104_warp_only
}
EOF
}
