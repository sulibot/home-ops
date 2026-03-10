include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  versions     = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  kanidm_auth   = read_terragrunt_config(find_in_parent_folders("common/lxc-kanidm-auth.hcl")).locals
  zot_class     = local.lxc_catalog.services.zot
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  secrets       = yamldecode(sops_decrypt_file(local.secrets_file))
  zot_admin_user   = try(local.secrets.zot_admin_user, "admin@sulibot.com")
  zot_admin_pass   = try(local.secrets.zot_admin_password, local.secrets.minio_root_password)
  service_domain   = "zot.sulibot.com"
  host_domain      = "${local.zot_class.hostname}.sulibot.com"
  zot_caddy_frontend_commands = [
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
    "cat > /etc/caddy/Caddyfile <<'CFG'\n{\n  admin off\n}\n\n${local.service_domain} {\n  tls /etc/caddy/certs/${local.service_domain}.crt /etc/caddy/certs/${local.service_domain}.key\n  reverse_proxy 127.0.0.1:5000\n}\nCFG",
    "systemctl daemon-reload",
    "systemctl enable --now caddy",
    "systemctl restart caddy",
    "curl -ksS -o /dev/null https://${local.service_domain}/v2/",
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
    proxmox = { source = "bpg/proxmox", version = "${local.lxc_catalog.lxc_defaults.provider_version}" }
    sops    = { source = "carlpett/sops", version = "~> 1.4.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
    routeros = { source = "terraform-routeros/routeros", version = "${local.versions.provider_versions.routeros}" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

variable "zot_admin_user" {
  type      = string
  sensitive = true
}

variable "zot_admin_password" {
  type      = string
  sensitive = true
}

locals {
  ssh_public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))
  kanidm_unix_auth_commands = ${jsonencode(local.kanidm_auth.kanidm_unix_auth_commands)}
  host_domain    = "${local.host_domain}"
  service_domain = "${local.service_domain}"
  zot_oidc_discovery_url = try(
    data.sops_file.secrets.data["kanidm_zot_oidc_discovery_url"],
    "https://idm.sulibot.com/oauth2/openid/zot/.well-known/openid-configuration"
  )
  zot_oidc_client_id     = try(data.sops_file.secrets.data["kanidm_zot_oidc_client_id"], "")
  zot_oidc_client_secret = try(data.sops_file.secrets.data["kanidm_zot_oidc_client_secret"], "")
  zot_oidc_enabled       = length(local.zot_oidc_client_id) > 0 && length(local.zot_oidc_client_secret) > 0

  containers = {
    zot01 = {
      vm_id           = ${local.zot_class.vm_id}
      node_name       = "${local.zot_class.node_name}"
      hostname        = "${local.zot_class.hostname}"
      description     = "Zot OCI registry LXC on ${local.zot_class.node_name} with Proxmox-managed Ceph volume mountpoint (tenant ${local.zot_class.tenant_id})"
      cpu_cores       = ${local.zot_class.sizing.cpu_cores}
      memory_mb       = ${local.zot_class.sizing.memory_mb}
      swap_mb         = ${local.zot_class.sizing.swap_mb}
      disk_gb         = ${local.zot_class.sizing.disk_gb}
      bridge          = "${local.zot_class.network.bridge}"
      vlan_id         = ${local.zot_class.network.vlan_id}
      firewall        = false
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "${local.zot_class.ipv4}"
      ipv4_gateway    = "${local.zot_class.network.ipv4_gateway}"
      ipv6_address    = "${local.zot_class.ipv6}"
      ipv6_gateway    = "${local.zot_class.network.ipv6_gateway}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["registry", "zot", "lxc", "trixie"]
      mount_points = [
        {
          volume = "${local.zot_class.storage.vm_datastore}"
          size   = "100G"
          path   = "/var/lib/zot"
        }
      ]
    }
  }

  zot_provision_commands = concat(local.kanidm_unix_auth_commands, [
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends curl ca-certificates apache2-utils >/dev/null",
    "curl -fsSL -o /usr/local/bin/zot https://github.com/project-zot/zot/releases/download/v2.1.2/zot-linux-amd64",
    "chmod 755 /usr/local/bin/zot",
    "if id -u zot >/dev/null 2>&1; then true; elif id -u debian >/dev/null 2>&1; then usermod -l zot debian && groupmod -n zot debian; else groupadd -g 1000 zot && useradd -u 1000 -g 1000 -s /usr/sbin/nologin -M zot; fi",
    "usermod -d /nonexistent -s /usr/sbin/nologin zot >/dev/null 2>&1 || true",
    "mkdir -p /etc/zot /var/lib/zot",
    "chown -R 1000:1000 /var/lib/zot",
    "if [ \"$${local.zot_oidc_enabled}\" = \"true\" ]; then cat > /etc/zot/oidc-credentials.json <<'JSON'\n{\n  \"oidc\": {\n    \"clientid\": \"$${local.zot_oidc_client_id}\",\n    \"clientsecret\": \"$${local.zot_oidc_client_secret}\"\n  }\n}\nJSON\nchown root:zot /etc/zot/oidc-credentials.json\nchmod 640 /etc/zot/oidc-credentials.json\ncat > /etc/zot/config.json <<'JSON'\n{\n  \"distSpecVersion\": \"1.1.0\",\n  \"storage\": {\n    \"rootDirectory\": \"/var/lib/zot\"\n  },\n  \"http\": {\n    \"address\": \"0.0.0.0\",\n    \"port\": \"5000\",\n    \"externalUrl\": \"https://$${local.service_domain}\",\n    \"auth\": {\n      \"openid\": {\n        \"providers\": {\n          \"kanidm\": {\n            \"issuer\": \"$${local.zot_oidc_discovery_url}\",\n            \"scopes\": [\"openid\", \"profile\", \"email\", \"groups\"]\n          }\n        }\n      }\n    }\n  },\n  \"log\": {\n    \"level\": \"info\"\n  },\n  \"extensions\": {\n    \"ui\": {\n      \"enable\": true\n    },\n    \"search\": {\n      \"enable\": true,\n      \"cve\": {\n        \"updateInterval\": \"24h\"\n      }\n    },\n    \"sync\": {\n      \"enable\": true,\n      \"registries\": [\n        {\"urls\": [\"https://registry-1.docker.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/docker.io\"}]},\n        {\"urls\": [\"https://ghcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/ghcr.io\"}]},\n        {\"urls\": [\"https://gcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/gcr.io\"}]},\n        {\"urls\": [\"https://mirror.gcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/mirror.gcr.io\"}]},\n        {\"urls\": [\"https://registry.k8s.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/registry.k8s.io\"}]},\n        {\"urls\": [\"https://quay.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/quay.io\"}]},\n        {\"urls\": [\"https://lscr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/lscr.io\"}]},\n        {\"urls\": [\"https://public.ecr.aws\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/public.ecr.aws\"}]},\n        {\"urls\": [\"https://factory.talos.dev\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/factory.talos.dev\"}]}\n      ]\n    }\n  }\n}\nJSON\nelse\nhtpasswd -nbBC 10 \"$${var.zot_admin_user}\" \"$${var.zot_admin_password}\" > /etc/zot/htpasswd\nchown root:zot /etc/zot/htpasswd\nchmod 640 /etc/zot/htpasswd\ncat > /etc/zot/config.json <<'JSON'\n{\n  \"distSpecVersion\": \"1.1.0\",\n  \"storage\": {\n    \"rootDirectory\": \"/var/lib/zot\"\n  },\n  \"http\": {\n    \"address\": \"0.0.0.0\",\n    \"port\": \"5000\",\n    \"externalUrl\": \"https://$${local.service_domain}\",\n    \"auth\": {\n      \"htpasswd\": {\n        \"path\": \"/etc/zot/htpasswd\"\n      }\n    }\n  },\n  \"log\": {\n    \"level\": \"info\"\n  },\n  \"extensions\": {\n    \"ui\": {\n      \"enable\": true\n    },\n    \"search\": {\n      \"enable\": true,\n      \"cve\": {\n        \"updateInterval\": \"24h\"\n      }\n    },\n    \"sync\": {\n      \"enable\": true,\n      \"registries\": [\n        {\"urls\": [\"https://registry-1.docker.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/docker.io\"}]},\n        {\"urls\": [\"https://ghcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/ghcr.io\"}]},\n        {\"urls\": [\"https://gcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/gcr.io\"}]},\n        {\"urls\": [\"https://mirror.gcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/mirror.gcr.io\"}]},\n        {\"urls\": [\"https://registry.k8s.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/registry.k8s.io\"}]},\n        {\"urls\": [\"https://quay.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/quay.io\"}]},\n        {\"urls\": [\"https://lscr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/lscr.io\"}]},\n        {\"urls\": [\"https://public.ecr.aws\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/public.ecr.aws\"}]},\n        {\"urls\": [\"https://factory.talos.dev\"], \"onDemand\": true, \"tlsVerify\": true, \"preserveDigest\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/factory.talos.dev\"}]}\n      ]\n    }\n  }\n}\nJSON\nfi",
    "cat > /etc/systemd/system/zot.service <<'UNIT'\n[Unit]\nDescription=Zot OCI Registry\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=/usr/local/bin/zot serve /etc/zot/config.json\nRestart=on-failure\nRestartSec=5s\nUser=zot\nGroup=zot\nStateDirectory=zot\nRuntimeDirectory=zot\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
    "systemctl daemon-reload",
    "systemctl enable zot",
    "systemctl restart zot",
  ])
}

module "zot_lxc" {
  source = "../../../modules/proxmox_lxc_role"

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.zot_class.storage.vm_datastore}"
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
    commands           = local.zot_provision_commands
  }
}

output "zot_lxc_containers" {
  value = module.zot_lxc.containers
}

output "zot_endpoint" {
  value = "https://${local.service_domain}"
}

resource "null_resource" "zot_caddy_frontend" {
  depends_on = [module.zot_lxc]

  triggers = {
    container_id    = module.zot_lxc.containers["zot01"].id
    service_domain  = local.service_domain
    cloudflare_hash = sha256(data.sops_file.secrets.data["cloudflare_api_token"])
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "${replace(local.zot_class.ipv4, "/24", "")}"
    timeout     = "10m"
  }

  provisioner "file" {
    content     = <<-EOT
CF_Token=$${data.sops_file.secrets.data["cloudflare_api_token"]}
EOT
    destination = "/root/cloudflare.env"
  }

  provisioner "remote-exec" {
    inline = ${jsonencode(local.zot_caddy_frontend_commands)}
  }
}

resource "routeros_ip_dns_record" "zot_host_ipv4" {
  name    = local.host_domain
  type    = "A"
  address = "${replace(local.zot_class.ipv4, "/24", "")}"
  ttl     = "5m"
  comment = "managed by terraform zot-lxc"
}

resource "routeros_ip_dns_record" "zot_host_ipv6" {
  name    = local.host_domain
  type    = "AAAA"
  address = "${replace(local.zot_class.ipv6, "/64", "")}"
  ttl     = "5m"
  comment = "managed by terraform zot-lxc"
}

resource "routeros_ip_dns_record" "zot_service_cname" {
  name    = local.service_domain
  type    = "CNAME"
  cname   = local.host_domain
  ttl     = "5m"
  comment = "managed by terraform zot-lxc"
}
EOF2
}

inputs = {
  zot_admin_user     = local.zot_admin_user
  zot_admin_password = local.zot_admin_pass
}
