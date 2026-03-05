include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  minio_class   = local.lxc_catalog.services.minio
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  minio_1p_item_id = "ycu7jzlweslrkpwnspmcgah75u"
  minio_root_user  = trimspace(run_cmd("--terragrunt-quiet", "op", "read", "op://Private/${local.minio_1p_item_id}/username"))
  minio_root_pass  = trimspace(run_cmd("--terragrunt-quiet", "op", "read", "op://Private/${local.minio_1p_item_id}/password"))
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

variable "minio_root_user" {
  type      = string
  sensitive = true
}

variable "minio_root_password" {
  type      = string
  sensitive = true
}

locals {
  ssh_public_key      = file(pathexpand("~/.ssh/id_ed25519.pub"))
  minio_root_user     = var.minio_root_user
  minio_root_password = var.minio_root_password
  minio_barman_ak     = data.sops_file.secrets.data["minio_barman_access_key"]
  minio_barman_sk     = data.sops_file.secrets.data["minio_barman_secret_key"]

  containers = {
    minio01 = {
      vm_id           = ${local.minio_class.vm_id}
      node_name       = "${local.minio_class.node_name}"
      hostname        = "${local.minio_class.hostname}"
      description     = "MinIO LXC on ${local.minio_class.node_name} with Proxmox-managed Ceph volume mountpoint (tenant ${local.minio_class.tenant_id})"
      cpu_cores       = ${local.minio_class.sizing.cpu_cores}
      memory_mb       = ${local.minio_class.sizing.memory_mb}
      swap_mb         = ${local.minio_class.sizing.swap_mb}
      disk_gb         = ${local.minio_class.sizing.disk_gb}
      bridge          = "${local.minio_class.network.bridge}"
      vlan_id         = ${local.minio_class.network.vlan_id}
      firewall        = false
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "${local.minio_class.ipv4}"
      ipv4_gateway    = "${local.minio_class.network.ipv4_gateway}"
      ipv6_address    = "${local.minio_class.ipv6}"
      ipv6_gateway    = "${local.minio_class.network.ipv6_gateway}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["storage", "minio", "lxc", "trixie"]
      mount_points = [
        {
          volume = "${local.minio_class.storage.vm_datastore}"
          size   = "200G"
          path   = "/data"
        }
      ]
    }
  }

  minio_provision_commands = [
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends curl ca-certificates >/dev/null",
    "mkdir -p /data/minio /etc/default",
    "curl -fsSL -o /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio",
    "curl -fsSL -o /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc",
    "chmod 755 /usr/local/bin/minio /usr/local/bin/mc",
    "if id -u minio-user >/dev/null 2>&1; then true; elif id -u debian >/dev/null 2>&1; then usermod -l minio-user debian && groupmod -n minio-user debian; else groupadd -g 1000 minio-user && useradd -u 1000 -g 1000 -s /usr/sbin/nologin -M minio-user; fi",
    "usermod -d /nonexistent -s /usr/sbin/nologin minio-user >/dev/null 2>&1 || true",
    "chown -R minio-user:minio-user /data/minio",
    "cat > /etc/default/minio <<'ENV'\nMINIO_VOLUMES=/data/minio\nMINIO_ROOT_USER=$${local.minio_root_user}\nMINIO_ROOT_PASSWORD=$${local.minio_root_password}\nMINIO_SITE_NAME=homelab-minio\nENV",
    "chmod 600 /etc/default/minio",
    "cat > /etc/systemd/system/minio.service <<'UNIT'\n[Unit]\nDescription=MinIO Object Storage\nDocumentation=https://min.io/docs/minio/linux/index.html\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=notify\nUser=minio-user\nGroup=minio-user\nEnvironmentFile=/etc/default/minio\nExecStart=/usr/local/bin/minio server $MINIO_VOLUMES --console-address :9001\nRestart=on-failure\nRestartSec=5\nTimeoutStartSec=120\nLimitNOFILE=65536\nLimitNPROC=4096\nNoNewPrivileges=yes\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
    "systemctl daemon-reload",
    "systemctl enable --now minio",
    "for i in $(seq 1 12); do curl -fsS -o /dev/null http://localhost:9000/minio/health/ready && break || sleep 5; done",
    "curl -fsS -o /dev/null http://localhost:9000/minio/health/ready",
    "mc alias set local http://localhost:9000 $${local.minio_root_user} $${local.minio_root_password} --quiet",
    "mc mb --ignore-existing local/cnpg-backups",
    "mc admin user add local $${local.minio_barman_ak} $${local.minio_barman_sk} 2>/dev/null || mc admin user enable local $${local.minio_barman_ak}",
    "mc admin policy attach local readwrite --user $${local.minio_barman_ak} 2>/dev/null || true",
  ]
}

module "minio_lxc" {
  source = "../../../modules/proxmox_lxc_role"

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.minio_class.storage.vm_datastore}"
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
    commands           = local.minio_provision_commands
  }
}

output "minio_lxc_containers" {
  value = module.minio_lxc.containers
}

output "minio_endpoints" {
  value = {
    api     = "http://${replace(local.minio_class.ipv4, "/24", "")}:9000"
    console = "http://${replace(local.minio_class.ipv4, "/24", "")}:9001"
  }
}
EOF2
}

inputs = {
  minio_root_user     = local.minio_root_user
  minio_root_password = local.minio_root_pass
}
