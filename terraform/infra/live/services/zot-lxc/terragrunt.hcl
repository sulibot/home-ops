include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  zot_class     = local.lxc_catalog.services.zot
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  zot_1p_item_id   = "h2gtnhpcfyqbb7dbspkkukdq3q"
  zot_admin_user   = trimspace(run_cmd("--terragrunt-quiet", "op", "read", "op://Private/${local.zot_1p_item_id}/username"))
  zot_admin_pass   = trimspace(run_cmd("--terragrunt-quiet", "op", "read", "op://Private/${local.zot_1p_item_id}/password"))
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
    sops    = { source = "carlpett/sops", version = "~> 1.3.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
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

  zot_provision_commands = [
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends curl ca-certificates apache2-utils >/dev/null",
    "curl -fsSL -o /usr/local/bin/zot https://github.com/project-zot/zot/releases/download/v2.1.2/zot-linux-amd64",
    "chmod 755 /usr/local/bin/zot",
    "if id -u zot >/dev/null 2>&1; then true; elif id -u debian >/dev/null 2>&1; then usermod -l zot debian && groupmod -n zot debian; else groupadd -g 1000 zot && useradd -u 1000 -g 1000 -s /usr/sbin/nologin -M zot; fi",
    "usermod -d /nonexistent -s /usr/sbin/nologin zot >/dev/null 2>&1 || true",
    "mkdir -p /etc/zot /var/lib/zot",
    "chown -R 1000:1000 /var/lib/zot",
    "htpasswd -nbBC 10 \"$${var.zot_admin_user}\" \"$${var.zot_admin_password}\" > /etc/zot/htpasswd",
    "chown root:zot /etc/zot/htpasswd",
    "chmod 640 /etc/zot/htpasswd",
    "cat > /etc/zot/config.json <<'JSON'\n{\n  \"distSpecVersion\": \"1.1.0\",\n  \"storage\": {\n    \"rootDirectory\": \"/var/lib/zot\"\n  },\n  \"http\": {\n    \"address\": \"0.0.0.0\",\n    \"port\": \"5000\",\n    \"auth\": {\n      \"htpasswd\": {\n        \"path\": \"/etc/zot/htpasswd\"\n      }\n    }\n  },\n  \"log\": {\n    \"level\": \"info\"\n  },\n  \"extensions\": {\n    \"ui\": {\n      \"enable\": true\n    },\n    \"search\": {\n      \"enable\": true,\n      \"cve\": {\n        \"updateInterval\": \"24h\"\n      }\n    },\n    \"sync\": {\n      \"enable\": true,\n      \"registries\": [\n        {\"urls\": [\"https://registry-1.docker.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/docker.io\"}]},\n        {\"urls\": [\"https://ghcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/ghcr.io\"}]},\n        {\"urls\": [\"https://gcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/gcr.io\"}]},\n        {\"urls\": [\"https://mirror.gcr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/mirror.gcr.io\"}]},\n        {\"urls\": [\"https://registry.k8s.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/registry.k8s.io\"}]},\n        {\"urls\": [\"https://quay.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/quay.io\"}]},\n        {\"urls\": [\"https://lscr.io\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/lscr.io\"}]},\n        {\"urls\": [\"https://public.ecr.aws\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/public.ecr.aws\"}]},\n        {\"urls\": [\"https://factory.talos.dev\"], \"onDemand\": true, \"tlsVerify\": true, \"content\": [{\"prefix\": \"**\", \"destination\": \"/factory.talos.dev\"}]}\n      ]\n    }\n  }\n}\nJSON",
    "cat > /etc/systemd/system/zot.service <<'UNIT'\n[Unit]\nDescription=Zot OCI Registry\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=/usr/local/bin/zot serve /etc/zot/config.json\nRestart=on-failure\nRestartSec=5s\nUser=zot\nGroup=zot\nStateDirectory=zot\nRuntimeDirectory=zot\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
    "systemctl daemon-reload",
    "systemctl enable zot",
    "systemctl restart zot",
  ]
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
  value = "http://${replace(local.zot_class.ipv4, "/24", "")}:5000"
}
EOF2
}

inputs = {
  zot_admin_user     = local.zot_admin_user
  zot_admin_password = local.zot_admin_pass
}
