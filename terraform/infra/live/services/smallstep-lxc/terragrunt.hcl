include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  versions      = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  kanidm_auth   = read_terragrunt_config(find_in_parent_folders("common/lxc-kanidm-auth.hcl")).locals
  pki_class     = local.lxc_catalog.services.pki
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  secrets       = yamldecode(sops_decrypt_file(local.secrets_file))

  onepassword_vault      = try(local.secrets.smallstep_onepassword_vault, "Kubernetes")
  onepassword_item_title = try(local.secrets.smallstep_onepassword_item, "smallstep-pki")
  ca_password_op = trimspace(run_cmd(
    "sh",
    "-lc",
    "timeout 10 op item get '${local.onepassword_item_title}' --vault '${local.onepassword_vault}' --fields label=ca_password --reveal 2>/dev/null || true",
  ))
  provisioner_password_op = trimspace(run_cmd(
    "sh",
    "-lc",
    "timeout 10 op item get '${local.onepassword_item_title}' --vault '${local.onepassword_vault}' --fields label=provisioner_password --reveal 2>/dev/null || true",
  ))
  ca_password          = length(local.ca_password_op) > 0 ? local.ca_password_op : try(local.secrets.smallstep_ca_password, local.secrets.minio_root_password)
  provisioner_password = length(local.provisioner_password_op) > 0 ? local.provisioner_password_op : try(local.secrets.smallstep_provisioner_password, local.secrets.minio_root_password)
  service_domain       = "pki.sulibot.com"
  host_domain          = "${local.pki_class.hostname}.sulibot.com"
  step_cli_version     = "0.30.1"
  step_ca_version      = "0.30.1"
  caddy_frontend_commands = [
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends caddy curl openssl >/dev/null",
    "mkdir -p /etc/caddy/certs /etc/systemd/system/caddy.service.d /root/.acme.sh /var/www/pki",
    "cat > /etc/systemd/system/caddy.service.d/override.conf <<'UNIT'\n[Service]\nPrivateTmp=false\nPrivateDevices=false\nProtectSystem=no\nProtectHome=false\nNoNewPrivileges=false\nUNIT",
    "if [ ! -x /root/.acme.sh/acme.sh ]; then curl -fsSL https://get.acme.sh | sh -s email=admin@sulibot.com >/dev/null; fi",
    "set -a && . /root/cloudflare.env && set +a",
    "/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null",
    "/root/.acme.sh/acme.sh --issue --dns dns_cf -d ${local.service_domain} --keylength ec-256 --force",
    "/root/.acme.sh/acme.sh --install-cert -d ${local.service_domain} --ecc --fullchain-file /etc/caddy/certs/${local.service_domain}.crt --key-file /etc/caddy/certs/${local.service_domain}.key",
    "shred -u /root/cloudflare.env || rm -f /root/cloudflare.env",
    "chown root:caddy /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key",
    "chmod 640 /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key",
    "FINGERPRINT=$(step certificate fingerprint /etc/step-ca/certs/root_ca.crt)",
    "cat > /var/www/pki/index.html <<HTML\n<!doctype html>\n<html lang=\"en\" data-theme=\"slate\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>Sulibot PKI</title>\n  <link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.slate.min.css\">\n  <style>\n    :root {\n      --page-width: 1160px;\n      --surface-border: rgba(148, 163, 184, 0.18);\n      --surface-soft: #111c34;\n      --text-soft: #cbd5e1;\n      --text-dim: #94a3b8;\n      --success-bg: rgba(34, 197, 94, 0.14);\n      --success-border: rgba(34, 197, 94, 0.28);\n      --warning-bg: rgba(245, 158, 11, 0.14);\n      --warning-border: rgba(245, 158, 11, 0.3);\n    }\n    body {\n      background: linear-gradient(180deg, #0b1120 0%, #0f172a 100%);\n      color: #e5edf7;\n    }\n    nav {\n      position: sticky;\n      top: 0;\n      z-index: 10;\n      backdrop-filter: blur(14px);\n      background: rgba(11, 17, 32, 0.82);\n      border-bottom: 1px solid rgba(148, 163, 184, 0.12);\n    }\n    nav .container,\n    main.container,\n    footer .container {\n      max-width: var(--page-width);\n    }\n    nav a {\n      color: var(--text-dim);\n      text-decoration: none;\n    }\n    nav a:hover {\n      color: #f8fafc;\n    }\n    main.container {\n      padding-top: 2rem;\n      padding-bottom: 4rem;\n    }\n    header.hero {\n      padding: 2rem;\n      margin-bottom: 1.25rem;\n      border: 1px solid var(--surface-border);\n      border-radius: 24px;\n      background: linear-gradient(135deg, rgba(14, 165, 233, 0.08), rgba(15, 23, 42, 0.96) 35%, rgba(15, 23, 42, 0.98) 100%);\n      box-shadow: 0 18px 40px rgba(2, 8, 23, 0.26);\n    }\n    header.hero h1 {\n      margin-bottom: 0.25rem;\n      color: #f8fafc;\n      letter-spacing: -0.03em;\n    }\n    header.hero p {\n      max-width: 78ch;\n      color: var(--text-soft);\n      margin-bottom: 0;\n    }\n    .hero-actions {\n      display: flex;\n      gap: 0.75rem;\n      flex-wrap: wrap;\n      margin-top: 1.25rem;\n    }\n    .hero-actions a[role=\"button\"] {\n      margin-bottom: 0;\n    }\n    .grid.stats {\n      margin-bottom: 1.25rem;\n    }\n    .stat,\n    article,\n    .command-card {\n      background: rgba(15, 23, 42, 0.84);\n      border: 1px solid var(--surface-border);\n      border-radius: 20px;\n      box-shadow: 0 16px 36px rgba(2, 8, 23, 0.18);\n    }\n    .stat {\n      padding: 1rem 1.1rem;\n      min-height: 100%;\n    }\n    .stat label {\n      display: block;\n      margin-bottom: 0.35rem;\n      color: var(--text-dim);\n      font-size: 0.78rem;\n      text-transform: uppercase;\n      letter-spacing: 0.08em;\n    }\n    .stat strong,\n    .stat a {\n      color: #f8fafc;\n      word-break: break-word;\n      text-decoration: none;\n    }\n    article {\n      padding: 1.35rem;\n      margin-bottom: 1.25rem;\n    }\n    article > header {\n      margin-bottom: 1rem;\n      padding-bottom: 0.9rem;\n      border-bottom: 1px solid rgba(148, 163, 184, 0.12);\n    }\n    article > header h2 {\n      margin-bottom: 0.2rem;\n      color: #f8fafc;\n    }\n    article > header p,\n    article p,\n    article li {\n      color: var(--text-soft);\n    }\n    .command-grid {\n      display: grid;\n      grid-template-columns: repeat(2, minmax(0, 1fr));\n      gap: 1rem;\n    }\n    .command-card {\n      padding: 1rem;\n    }\n    .command-card h3 {\n      margin-bottom: 0.25rem;\n      font-size: 1rem;\n      color: #f8fafc;\n    }\n    .command-card p {\n      margin-bottom: 0.8rem;\n      color: var(--text-dim);\n      font-size: 0.96rem;\n    }\n    .command-head {\n      display: flex;\n      justify-content: space-between;\n      align-items: start;\n      gap: 0.75rem;\n      margin-bottom: 0.75rem;\n    }\n    pre {\n      margin: 0;\n      padding: 1rem;\n      overflow-x: auto;\n      border: 1px solid rgba(148, 163, 184, 0.14);\n      border-radius: 16px;\n      background: #020817;\n      color: #dbeafe;\n      font-size: 0.92rem;\n      line-height: 1.55;\n    }\n    code {\n      color: #e2e8f0;\n    }\n    .endpoint-list {\n      display: grid;\n      grid-template-columns: repeat(3, minmax(0, 1fr));\n      gap: 0.9rem;\n    }\n    .endpoint {\n      padding: 1rem;\n      border: 1px solid rgba(148, 163, 184, 0.12);\n      border-radius: 16px;\n      background: var(--surface-soft);\n    }\n    .endpoint strong {\n      display: block;\n      margin-bottom: 0.35rem;\n      color: #f8fafc;\n    }\n    .endpoint a {\n      text-decoration: none;\n      word-break: break-word;\n    }\n    .callout {\n      padding: 1rem 1.05rem;\n      border-radius: 16px;\n      margin-bottom: 1rem;\n    }\n    .callout.success {\n      background: var(--success-bg);\n      border: 1px solid var(--success-border);\n    }\n    .callout.warning {\n      background: var(--warning-bg);\n      border: 1px solid var(--warning-border);\n    }\n    .callout p:last-child {\n      margin-bottom: 0;\n    }\n    .field {\n      margin-bottom: 0.9rem;\n    }\n    .field label {\n      display: block;\n      margin-bottom: 0.35rem;\n      color: var(--text-dim);\n      font-size: 0.84rem;\n      text-transform: uppercase;\n      letter-spacing: 0.07em;\n    }\n    .field input {\n      font-family: var(--pico-font-family-monospace);\n    }\n    footer {\n      border-top: 1px solid rgba(148, 163, 184, 0.12);\n      background: rgba(11, 17, 32, 0.6);\n    }\n    footer .container {\n      padding-block: 1.2rem 1.6rem;\n      color: var(--text-dim);\n    }\n    @media (max-width: 900px) {\n      .command-grid,\n      .endpoint-list {\n        grid-template-columns: 1fr;\n      }\n    }\n    @media (max-width: 720px) {\n      nav .container {\n        display: block;\n      }\n      nav ul:last-child {\n        margin-top: 0.5rem;\n        flex-wrap: wrap;\n      }\n      header.hero {\n        padding: 1.3rem;\n      }\n      article {\n        padding: 1rem;\n      }\n    }\n  </style>\n</head>\n<body>\n  <nav>\n    <div class=\"container\">\n      <ul>\n        <li><strong>Sulibot PKI</strong></li>\n      </ul>\n      <ul>\n        <li><a href=\"#quickstart\">Quick Start</a></li>\n        <li><a href=\"#operations\">Operations</a></li>\n        <li><a href=\"#oidc\">OIDC</a></li>\n        <li><a href=\"#client-certs\">Client Certs</a></li>\n      </ul>\n    </div>\n  </nav>\n\n  <main class=\"container\">\n    <header class=\"hero\">\n      <hgroup>\n        <h1>Sulibot PKI</h1>\n        <p>Smallstep CA endpoint for homelab certificate issuance, client identity certificates, and ACME automation.</p>\n      </hgroup>\n      <p>Use the fields below to copy the CA URL, verify the root fingerprint, and run the commands you actually need without reading through vendor docs first.</p>\n      <div class=\"hero-actions\">\n        <a href=\"/roots.pem\" role=\"button\" class=\"secondary\">Download Roots</a>\n        <a href=\"/acme/acme/directory\" role=\"button\" class=\"secondary\">Open ACME Directory</a>\n        <a href=\"/health\" role=\"button\" class=\"secondary\">Check Health</a>\n      </div>\n    </header>\n\n    <div class=\"grid stats\">\n      <div class=\"stat\">\n        <label>CA URL</label>\n        <strong>https://${local.service_domain}</strong>\n      </div>\n      <div class=\"stat\">\n        <label>Root Fingerprint</label>\n        <strong>$FINGERPRINT</strong>\n      </div>\n      <div class=\"stat\">\n        <label>Default Provisioner</label>\n        <strong>admin@sulibot.com</strong>\n      </div>\n      <div class=\"stat\">\n        <label>ACME Provisioner</label>\n        <strong>acme</strong>\n      </div>\n    </div>\n\n    <article id=\"quickstart\">\n      <header>\n        <hgroup>\n          <h2>Quick Start</h2>\n          <p>The top two values most clients need, followed by the first bootstrap command.</p>\n        </hgroup>\n      </header>\n      <div class=\"callout success\">\n        <p><strong>Expected behavior:</strong> this page is the operator landing page. API endpoints like <code>/roots.pem</code>, <code>/health</code>, and the ACME directory stay live behind the same hostname.</p>\n      </div>\n      <div class=\"field\">\n        <label for=\"ca-url\">CA URL</label>\n        <input id=\"ca-url\" value=\"https://${local.service_domain}\" readonly>\n      </div>\n      <div class=\"field\">\n        <label for=\"root-fingerprint\">Root Fingerprint</label>\n        <input id=\"root-fingerprint\" value=\"$FINGERPRINT\" readonly>\n      </div>\n      <div class=\"command-grid\">\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Bootstrap a workstation</h3>\n              <p>Run once on any machine that will use the <code>step</code> CLI against this CA.</p>\n            </div>\n          </div>\n          <pre><code>step ca bootstrap \\\n  --ca-url https://${local.service_domain} \\\n  --fingerprint $FINGERPRINT</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Set ACME directory</h3>\n              <p>Useful for Caddy, Traefik, cert-manager testing, or shell-based clients.</p>\n            </div>\n          </div>\n          <pre><code>ACME_DIRECTORY=https://${local.service_domain}/acme/acme/directory</code></pre>\n        </section>\n      </div>\n    </article>\n\n    <article>\n      <header>\n        <hgroup>\n          <h2>Service Endpoints</h2>\n          <p>Direct links for the live CA resources exposed on this host.</p>\n        </hgroup>\n      </header>\n      <div class=\"endpoint-list\">\n        <div class=\"endpoint\">\n          <strong>Roots Bundle</strong>\n          <a href=\"/roots.pem\">https://${local.service_domain}/roots.pem</a>\n        </div>\n        <div class=\"endpoint\">\n          <strong>Health Check</strong>\n          <a href=\"/health\">https://${local.service_domain}/health</a>\n        </div>\n        <div class=\"endpoint\">\n          <strong>ACME Directory</strong>\n          <a href=\"/acme/acme/directory\">https://${local.service_domain}/acme/acme/directory</a>\n        </div>\n      </div>\n    </article>\n\n    <article id=\"operations\">\n      <header>\n        <hgroup>\n          <h2>Common Operations</h2>\n          <p>Routine commands for validation, inspection, and day-to-day CA checks.</p>\n        </hgroup>\n      </header>\n      <div class=\"command-grid\">\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Inspect the CA</h3>\n              <p>Verify trust material, service health, and the ACME endpoint.</p>\n            </div>\n          </div>\n          <pre><code>step certificate fingerprint https://${local.service_domain}/roots.pem\nstep ca provisioner list\nhttp https://${local.service_domain}/health\nhttp https://${local.service_domain}/acme/acme/directory</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Issue a smoke-test certificate</h3>\n              <p>Quick validation that signing is working end to end.</p>\n            </div>\n          </div>\n          <pre><code>step ca certificate smoke-test \\\n  smoke-test.crt \\\n  smoke-test.key \\\n  --provisioner admin@sulibot.com\n\nstep certificate inspect smoke-test.crt --short</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Print the root fingerprint</h3>\n              <p>Useful when bootstrapping a new client or validating copied trust data.</p>\n            </div>\n          </div>\n          <pre><code>step certificate fingerprint https://${local.service_domain}/roots.pem</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>List provisioners</h3>\n              <p>Shows the current JWK, ACME, and any later OIDC provisioners.</p>\n            </div>\n          </div>\n          <pre><code>step ca provisioner list</code></pre>\n        </section>\n      </div>\n    </article>\n\n    <article id=\"oidc\">\n      <header>\n        <hgroup>\n          <h2>OIDC Provisioner</h2>\n          <p>Template for adding an Authentik-backed OIDC provisioner. Replace placeholders before running it.</p>\n        </hgroup>\n      </header>\n      <div class=\"callout warning\">\n        <p><strong>Before you run this:</strong> create the OIDC client in Authentik, confirm the discovery URL, and decide which email domains or groups should be trusted for certificate issuance.</p>\n      </div>\n      <div class=\"command-grid\">\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Add provisioner</h3>\n              <p>Creates a new OIDC provisioner that delegates login to Authentik.</p>\n            </div>\n          </div>\n          <pre><code>step ca provisioner add authentik \\\n  --type OIDC \\\n  --client-id YOUR_CLIENT_ID \\\n  --client-secret YOUR_CLIENT_SECRET \\\n  --configuration-endpoint https://auth.sulibot.com/application/o/YOUR_APP/.well-known/openid-configuration \\\n  --domain sulibot.com \\\n  --admin admin@sulibot.com</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Verify the new provisioner</h3>\n              <p>Run after adding it to confirm it appears in the local CA configuration.</p>\n            </div>\n          </div>\n          <pre><code>step ca provisioner list | grep authentik</code></pre>\n        </section>\n      </div>\n    </article>\n\n    <article id=\"client-certs\">\n      <header>\n        <hgroup>\n          <h2>Client Certificate Workflow</h2>\n          <p>Use this sequence when a browser, laptop, script, or local service needs a client identity certificate for mutual TLS.</p>\n        </hgroup>\n      </header>\n      <div class=\"command-grid\">\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Issue a client certificate</h3>\n              <p>Creates a certificate and private key for a user or device identity.</p>\n            </div>\n          </div>\n          <pre><code>step ca certificate alice-laptop \\\n  alice-laptop.crt \\\n  alice-laptop.key \\\n  --provisioner admin@sulibot.com</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Inspect the certificate</h3>\n              <p>Confirm subject, issuer, and validity dates before distribution.</p>\n            </div>\n          </div>\n          <pre><code>step certificate inspect alice-laptop.crt --short</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Create a PKCS#12 bundle</h3>\n              <p>Bundle the certificate and key for browser or OS import.</p>\n            </div>\n          </div>\n          <pre><code>step certificate p12 \\\n  alice-laptop.p12 \\\n  alice-laptop.crt \\\n  alice-laptop.key</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Use it with curl</h3>\n              <p>Simple test against an mTLS-protected endpoint.</p>\n            </div>\n          </div>\n          <pre><code>curl \\\n  --cert alice-laptop.crt \\\n  --key alice-laptop.key \\\n  https://YOUR_MTLS_SERVICE</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Use it with HTTPie</h3>\n              <p>Equivalent workflow for HTTPie-based API testing.</p>\n            </div>\n          </div>\n          <pre><code>http \\\n  --cert alice-laptop.crt \\\n  --cert-key alice-laptop.key \\\n  https://YOUR_MTLS_SERVICE</code></pre>\n        </section>\n        <section class=\"command-card\">\n          <div class=\"command-head\">\n            <div>\n              <h3>Renew an existing certificate</h3>\n              <p>Reuse the existing keypair and update the certificate in place.</p>\n            </div>\n          </div>\n          <pre><code>step ca renew \\\n  alice-laptop.crt \\\n  alice-laptop.key</code></pre>\n        </section>\n      </div>\n    </article>\n  </main>\n\n  <footer>\n    <div class=\"container\">\n      <small>Sulibot PKI. Backed by Smallstep <code>step-ca</code> and Caddy. This page is an operator landing page, not a full admin UI.</small>\n    </div>\n  </footer>\n</body>\n</html>\nHTML",
    "cat > /etc/caddy/Caddyfile <<'CFG'\n{\n  admin off\n}\n\n${local.service_domain} {\n  tls /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key\n\n  handle / {\n    root * /var/www/pki\n    file_server\n  }\n\n  handle {\n    reverse_proxy https://127.0.0.1:9000 {\n      transport http {\n        tls_insecure_skip_verify\n      }\n    }\n  }\n}\nCFG",
    "systemctl daemon-reload",
    "systemctl enable --now caddy",
    "systemctl restart caddy",
    "curl --resolve ${local.service_domain}:443:127.0.0.1 -ksS -o /dev/null https://${local.service_domain}/",
  ]
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
provider "sops" {}

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = "https://10.10.0.1:8006/api2/json"
  username = "root@pam"
  password = data.sops_file.secrets.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}

provider "routeros" {
  hosturl  = data.sops_file.secrets.data["routeros_hosturl"]
  username = data.sops_file.secrets.data["routeros_username"]
  password = data.sops_file.secrets.data["routeros_password"]
  insecure = true
}
EOF2
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
terraform {
  backend "local" {}

  required_providers {
    proxmox  = { source = "bpg/proxmox", version = "${local.lxc_catalog.lxc_defaults.provider_version}" }
    sops     = { source = "carlpett/sops", version = "~> 1.4.0" }
    null     = { source = "hashicorp/null", version = "~> 3.0" }
    routeros = { source = "terraform-routeros/routeros", version = "${local.versions.provider_versions.routeros}" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

variable "smallstep_ca_password" {
  type      = string
  sensitive = true
}

variable "smallstep_provisioner_password" {
  type      = string
  sensitive = true
}

locals {
  ssh_public_key            = file(pathexpand("~/.ssh/id_ed25519.pub"))
  kanidm_unix_auth_commands = ${jsonencode(local.kanidm_auth.kanidm_unix_auth_commands)}
  host_domain               = "${local.host_domain}"
  service_domain            = "${local.service_domain}"
  step_cli_version          = "${local.step_cli_version}"
  step_ca_version           = "${local.step_ca_version}"

  containers = {
    pki01 = {
      vm_id           = ${local.pki_class.vm_id}
      node_name       = "${local.pki_class.node_name}"
      hostname        = "${local.pki_class.hostname}"
      description     = "Smallstep PKI LXC on ${local.pki_class.node_name} (tenant ${local.pki_class.tenant_id})"
      cpu_cores       = ${local.pki_class.sizing.cpu_cores}
      memory_mb       = ${local.pki_class.sizing.memory_mb}
      swap_mb         = ${local.pki_class.sizing.swap_mb}
      disk_gb         = ${local.pki_class.sizing.disk_gb}
      bridge          = "${local.pki_class.network.bridge}"
      vlan_id         = ${jsonencode(local.pki_class.network.vlan_id)}
      firewall        = false
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "${local.pki_class.ipv4}"
      ipv4_gateway    = "${local.pki_class.network.ipv4_gateway}"
      ipv6_address    = "${local.pki_class.ipv6}"
      ipv6_gateway    = "${local.pki_class.network.ipv6_gateway}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["identity", "pki", "smallstep", "lxc", "trixie"]
      mount_points = [
        {
          volume = "${local.pki_class.storage.vm_datastore}"
          size   = "20G"
          path   = "/var/lib/step-ca"
        }
      ]
    }
  }

  smallstep_provision_commands = concat(local.kanidm_unix_auth_commands, [
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends curl ca-certificates jq tar >/dev/null",
    "curl -fsSL -o /tmp/step-cli.deb https://dl.smallstep.com/gh-release/cli/docs-cli-install/v$${local.step_cli_version}/step-cli_$${local.step_cli_version}-1_amd64.deb",
    "dpkg -i /tmp/step-cli.deb >/dev/null",
    "rm -f /tmp/step-cli.deb",
    "curl -fsSL -o /tmp/step-ca.deb https://dl.smallstep.com/gh-release/certificates/docs-ca-install/v$${local.step_ca_version}/step-ca_$${local.step_ca_version}-1_amd64.deb",
    "dpkg -i /tmp/step-ca.deb >/dev/null",
    "rm -f /tmp/step-ca.deb",
    "id step-ca >/dev/null 2>&1 || useradd --system --home-dir /var/lib/step-ca --create-home --shell /usr/sbin/nologin step-ca",
    "mkdir -p /etc/step-ca /etc/step-ca/secrets /var/lib/step-ca/db /var/lib/step-ca/certs /var/lib/step-ca/config",
    "printf '%s' '$${var.smallstep_ca_password}' > /etc/step-ca/secrets/password.txt",
    "printf '%s' '$${var.smallstep_provisioner_password}' > /etc/step-ca/secrets/provisioner-password.txt",
    "chmod 600 /etc/step-ca/secrets/password.txt /etc/step-ca/secrets/provisioner-password.txt",
    "if [ ! -f /var/lib/step-ca/config/ca.json ]; then export STEPPATH=/var/lib/step-ca && step ca init --name 'Sulibot Homelab PKI' --deployment-type standalone --dns '$${local.service_domain},$${local.host_domain}' --address '127.0.0.1:9000' --provisioner 'admin@sulibot.com' --password-file /etc/step-ca/secrets/password.txt --provisioner-password-file /etc/step-ca/secrets/provisioner-password.txt --acme; fi",
    "mkdir -p /etc/step-ca/certs /etc/step-ca/config /etc/step-ca/db",
    "cp -f /var/lib/step-ca/certs/root_ca.crt /etc/step-ca/certs/root_ca.crt",
    "cp -f /var/lib/step-ca/certs/intermediate_ca.crt /etc/step-ca/certs/intermediate_ca.crt",
    "cp -f /var/lib/step-ca/secrets/intermediate_ca_key /etc/step-ca/secrets/intermediate_ca_key",
    "cp -f /var/lib/step-ca/config/ca.json /etc/step-ca/config/ca.json",
    "cp -f /var/lib/step-ca/db/db /etc/step-ca/db/db",
    "chown -R step-ca:step-ca /etc/step-ca /var/lib/step-ca",
    "chmod 600 /etc/step-ca/secrets/password.txt /etc/step-ca/secrets/provisioner-password.txt /etc/step-ca/secrets/intermediate_ca_key",
    "cat > /etc/systemd/system/step-ca.service <<'UNIT'\n[Unit]\nDescription=Smallstep Certificate Authority\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nUser=step-ca\nGroup=step-ca\nEnvironment=STEPPATH=/etc/step-ca\nExecStart=/usr/bin/step-ca /etc/step-ca/config/ca.json --password-file /etc/step-ca/secrets/password.txt\nRestart=on-failure\nRestartSec=5s\nAmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE\nNoNewPrivileges=true\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
    "systemctl daemon-reload",
    "systemctl enable --now step-ca",
    "systemctl restart step-ca",
    "for i in $(seq 1 30); do curl -ksS -o /dev/null https://127.0.0.1:9000/health && exit 0; sleep 2; done; systemctl --no-pager --full status step-ca; exit 1",
  ])
}

module "smallstep_lxc" {
  source = "../../../modules/proxmox_lxc_role"

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.pki_class.storage.vm_datastore}"
  }

  template = {
    download  = false
    url       = ""
    file_name = ""
    file_id   = "${local.lxc_catalog.lxc_defaults.template_file_id}"
  }

  dns_servers = [
    "${local.network_infra.dns_servers.ipv6}",
    "${local.network_infra.dns_servers.ipv4}",
  ]

  containers = local.containers

  provision = {
    enabled            = true
    ssh_user           = "root"
    ssh_private_key    = file(pathexpand("~/.ssh/id_ed25519"))
    ssh_timeout        = "10m"
    wait_for_cloudinit = false
    commands           = local.smallstep_provision_commands
  }
}

output "smallstep_lxc_containers" {
  value = module.smallstep_lxc.containers
}

output "smallstep_endpoint" {
  value = "https://${local.service_domain}"
}

resource "null_resource" "smallstep_caddy_frontend" {
  depends_on = [module.smallstep_lxc]

  triggers = {
    container_id    = module.smallstep_lxc.containers["pki01"].id
    service_domain  = local.service_domain
    cloudflare_hash = sha256(data.sops_file.secrets.data["cloudflare_api_token"])
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "${replace(local.pki_class.ipv4, "/24", "")}"
    timeout     = "10m"
  }

  provisioner "file" {
    content     = <<-EOT
CF_Token=$${data.sops_file.secrets.data["cloudflare_api_token"]}
EOT
    destination = "/root/cloudflare.env"
  }

  provisioner "remote-exec" {
    inline = ${jsonencode(local.caddy_frontend_commands)}
  }
}

resource "routeros_ip_dns_record" "smallstep_host_ipv4" {
  name    = local.host_domain
  type    = "A"
  address = "${replace(local.pki_class.ipv4, "/24", "")}"
  ttl     = "5m"
  comment = "managed by terraform smallstep-lxc"
}

resource "routeros_ip_dns_record" "smallstep_host_ipv6" {
  name    = local.host_domain
  type    = "AAAA"
  address = "${replace(local.pki_class.ipv6, "/64", "")}"
  ttl     = "5m"
  comment = "managed by terraform smallstep-lxc"
}

resource "routeros_ip_dns_record" "smallstep_service_cname" {
  name    = local.service_domain
  type    = "CNAME"
  cname   = local.host_domain
  ttl     = "5m"
  comment = "managed by terraform smallstep-lxc"
}

resource "null_resource" "smallstep_1password_sync" {
  depends_on = [module.smallstep_lxc, null_resource.smallstep_caddy_frontend]

  triggers = {
    service_domain = local.service_domain
    sync_rev       = "smallstep-1password-v1"
  }

  provisioner "local-exec" {
    command = <<-OPCMD
      set -euo pipefail
      SSH_OPTS="-i $HOME/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      timeout 10 op whoami >/dev/null 2>&1 || { echo "Skipping 1Password PKI sync: 1Password CLI is not authenticated"; exit 0; }

      ITEM_ID="$(timeout 15 op item get "${local.onepassword_item_title}" --vault "${local.onepassword_vault}" --format json 2>/dev/null | jq -r '.id' || true)"
      if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
        ITEM_ID="$(timeout 15 op item create \
          --vault="${local.onepassword_vault}" \
          --title="${local.onepassword_item_title}" \
          --category=server \
          "hostname[text]=${local.service_domain}" \
          "host_node[text]=${local.host_domain}" \
          "ca_url[text]=https://${local.service_domain}" \
          --format json | jq -r '.id')"
      fi

      ROOT_CRT="$(timeout 20 ssh $SSH_OPTS root@${replace(local.pki_class.ipv4, "/24", "")} 'cat /etc/step-ca/certs/root_ca.crt')"
      INTERMEDIATE_CRT="$(timeout 20 ssh $SSH_OPTS root@${replace(local.pki_class.ipv4, "/24", "")} 'cat /etc/step-ca/certs/intermediate_ca.crt')"
      INTERMEDIATE_KEY_B64="$(timeout 20 ssh $SSH_OPTS root@${replace(local.pki_class.ipv4, "/24", "")} 'base64 -w0 /etc/step-ca/secrets/intermediate_ca_key')"
      FINGERPRINT="$(timeout 20 ssh $SSH_OPTS root@${replace(local.pki_class.ipv4, "/24", "")} 'step certificate fingerprint /etc/step-ca/certs/root_ca.crt')"
      CA_JSON_B64="$(timeout 20 ssh $SSH_OPTS root@${replace(local.pki_class.ipv4, "/24", "")} 'base64 -w0 /etc/step-ca/config/ca.json')"

      timeout 20 op item edit "$ITEM_ID" \
        --vault="${local.onepassword_vault}" \
        "hostname[text]=${local.service_domain}" \
        "host_node[text]=${local.host_domain}" \
        "ca_url[text]=https://${local.service_domain}" \
        "ca_password[password]=$${var.smallstep_ca_password}" \
        "provisioner_password[password]=$${var.smallstep_provisioner_password}" \
        "root_ca_crt[text]=$ROOT_CRT" \
        "intermediate_ca_crt[text]=$INTERMEDIATE_CRT" \
        "root_ca_fingerprint[text]=$FINGERPRINT" \
        "intermediate_ca_key_base64[concealed]=$INTERMEDIATE_KEY_B64" \
        "ca_json_base64[concealed]=$CA_JSON_B64"
    OPCMD
  }
}
EOF2
}

inputs = {
  smallstep_ca_password          = local.ca_password
  smallstep_provisioner_password = local.provisioner_password
}
