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
    "op item get '${local.onepassword_item_title}' --vault '${local.onepassword_vault}' --fields label=ca_password --reveal 2>/dev/null || true",
  ))
  provisioner_password_op = trimspace(run_cmd(
    "sh",
    "-lc",
    "op item get '${local.onepassword_item_title}' --vault '${local.onepassword_vault}' --fields label=provisioner_password --reveal 2>/dev/null || true",
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
    "mkdir -p /etc/caddy/certs /etc/systemd/system/caddy.service.d /root/.acme.sh",
    "cat > /etc/systemd/system/caddy.service.d/override.conf <<'UNIT'\n[Service]\nPrivateTmp=false\nPrivateDevices=false\nProtectSystem=no\nProtectHome=false\nNoNewPrivileges=false\nUNIT",
    "if [ ! -x /root/.acme.sh/acme.sh ]; then curl -fsSL https://get.acme.sh | sh -s email=admin@sulibot.com >/dev/null; fi",
    "set -a && . /root/cloudflare.env && set +a",
    "/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null",
    "/root/.acme.sh/acme.sh --issue --dns dns_cf -d ${local.service_domain} --keylength ec-256 --force",
    "/root/.acme.sh/acme.sh --install-cert -d ${local.service_domain} --ecc --fullchain-file /etc/caddy/certs/${local.service_domain}.crt --key-file /etc/caddy/certs/${local.service_domain}.key",
    "shred -u /root/cloudflare.env || rm -f /root/cloudflare.env",
    "chown root:caddy /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key",
    "chmod 640 /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key",
    "cat > /etc/caddy/Caddyfile <<'CFG'\n{\n  admin off\n}\n\n${local.service_domain} {\n  tls /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key\n  reverse_proxy https://127.0.0.1:9000 {\n    transport http {\n      tls_insecure_skip_verify\n    }\n  }\n}\nCFG",
    "systemctl daemon-reload",
    "systemctl enable --now caddy",
    "systemctl restart caddy",
    "curl --resolve ${local.service_domain}:443:127.0.0.1 -ksS -o /dev/null https://${local.service_domain}/health",
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

      timeout 10 op whoami >/dev/null 2>&1 || { echo "Skipping 1Password PKI sync: 1Password CLI is not authenticated or is waiting for interactive unlock"; exit 0; }

      ITEM_ID="$(timeout 10 op item get "${local.onepassword_item_title}" --vault "${local.onepassword_vault}" --format json 2>/dev/null | jq -r '.id' || true)"
      if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
        ITEM_ID="$(timeout 15 op item create \
          --vault="${local.onepassword_vault}" \
          --title="${local.onepassword_item_title}" \
          --category=server \
          "hostname[text]=${local.service_domain}" \
          "host_node[text]=${local.host_domain}" \
          "ca_url[text]=https://${local.service_domain}" \
          --format json | jq -r '.id' || true)"
      fi

      if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
        echo "Skipping 1Password PKI sync: unable to read or create item ${local.onepassword_item_title} in vault ${local.onepassword_vault}"
        exit 0
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
        "ca_json_base64[concealed]=$CA_JSON_B64" || {
          echo "Skipping 1Password PKI sync: update timed out or failed"
          exit 0
        }
    OPCMD
  }
}
EOF2
}

inputs = {
  smallstep_ca_password          = local.ca_password
  smallstep_provisioner_password = local.provisioner_password
}
