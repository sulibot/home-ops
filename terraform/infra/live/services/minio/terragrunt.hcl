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
  dir           = get_terragrunt_dir()

  # DNS servers (interpolated at generation time into main.tf as literals)
  dns_ipv6 = local.network_infra.dns_servers.ipv6
  dns_ipv4 = local.network_infra.dns_servers.ipv4
  vm_ds    = local.minio_class.storage.vm_datastore
  data_ds  = local.proxmox_infra.storage.datastore_id
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.secrets.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.secrets.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {}

  required_providers {
    proxmox = { source = "bpg/proxmox", version = "${local.lxc_catalog.lxc_defaults.provider_version}" }
    sops    = { source = "carlpett/sops", version = "~> 1.3.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

# Injected by root.hcl extra_arguments
variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  ssh_public_key      = file(pathexpand("~/.ssh/id_ed25519.pub"))
  minio_root_user     = data.sops_file.secrets.data["minio_root_user"]
  minio_root_password = data.sops_file.secrets.data["minio_root_password"]
  minio_barman_ak     = data.sops_file.secrets.data["minio_barman_access_key"]
  minio_barman_sk     = data.sops_file.secrets.data["minio_barman_secret_key"]
}

# Debian Trixie (13) LXC template is pre-staged on pve02 resources datastore.
# resources:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst

resource "proxmox_virtual_environment_container" "minio01" {
  vm_id       = ${local.minio_class.vm_id}
  node_name   = "${local.minio_class.node_name}"
  description = "MinIO S3 object storage - CNPG barman WAL backups (VLAN 200)"

  started = true

  operating_system {
    template_file_id = "${local.lxc_catalog.lxc_defaults.template_file_id}"
    type             = "debian"
  }

  # Rootfs on Ceph RBD (16 GB)
  disk {
    datastore_id = "${local.vm_ds}"
    size         = 16
  }

  # MinIO data volume on Ceph RBD (200 GB). Proxmox mounts this at /data in the container.
  mount_point {
    volume = "${local.vm_ds}"
    size   = "200G"
    path   = "/data"
  }

  cpu {
    cores = ${local.minio_class.sizing.cpu_cores}
  }

  memory {
    dedicated = ${local.minio_class.sizing.memory_mb}
    swap      = ${local.minio_class.sizing.swap_mb}
  }

  network_interface {
    name     = "eth0"
    bridge   = "${local.minio_class.network.bridge}"
    vlan_id  = ${local.minio_class.network.vlan_id}
    firewall = false
  }

  initialization {
    hostname = "${local.minio_class.hostname}"

    ip_config {
      ipv4 {
        address = "${local.minio_class.ipv4}"
        gateway = "${local.minio_class.network.ipv4_gateway}"
      }
      ipv6 {
        address = "${local.minio_class.ipv6}"
        gateway = "${local.minio_class.network.ipv6_gateway}"
      }
    }

    dns {
      servers = ["${local.dns_ipv6}", "${local.dns_ipv4}"]
    }

    user_account {
      keys = [local.ssh_public_key]
    }
  }

  # All fields are write-only at create time; ignore post-import diffs entirely.
  # Terraform role here is provisioning only — manual changes are acceptable.
  lifecycle {
    ignore_changes = all
  }
}

resource "null_resource" "minio_provision" {
  depends_on = [proxmox_virtual_environment_container.minio01]

  triggers = {
    container_id  = proxmox_virtual_environment_container.minio01.id
    minio_service = filemd5("${local.dir}/files/minio.service")
    # Re-provision if credentials change
    minio_user    = sha256(local.minio_root_user)
    barman_ak     = local.minio_barman_ak
    barman_sk_sha = sha256(local.minio_barman_sk)
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "${replace(local.minio_class.ipv4, "/24", "")}"
    timeout     = "5m"
  }

  # Upload credentials env file. Using file provisioner avoids shell escaping
  # issues with special characters in passwords.
  provisioner "file" {
    content = join("\n", [
      "MINIO_VOLUMES=/data/minio",
      "MINIO_ROOT_USER=$${local.minio_root_user}",
      "MINIO_ROOT_PASSWORD=$${local.minio_root_password}",
      "MINIO_SITE_NAME=homelab-minio",
      "",
    ])
    destination = "/tmp/minio-env"
  }

  provisioner "file" {
    source      = "${local.dir}/files/minio.service"
    destination = "/tmp/minio.service"
  }

  provisioner "remote-exec" {
    inline = [
      # Basic setup
      "apt-get update -qq && apt-get install -y -qq curl xfsprogs",
      # Ensure MinIO data directory exists on the Proxmox-mounted volume
      "mkdir -p /data/minio",
      # Download MinIO server binary
      "curl -fsSL -o /tmp/minio https://dl.min.io/server/minio/release/linux-amd64/minio",
      "install -m 755 /tmp/minio /usr/local/bin/minio",
      # Download mc client
      "curl -fsSL -o /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc",
      "install -m 755 /tmp/mc /usr/local/bin/mc",
      # Create minio system user
      "useradd -r -s /usr/sbin/nologin minio-user 2>/dev/null || true",
      "chown minio-user:minio-user /data/minio",
      # Install credentials env file (mode 600, root-owned)
      "install -m 600 /tmp/minio-env /etc/default/minio",
      "chown root:root /etc/default/minio",
      # Install and start the systemd service
      "install -m 644 /tmp/minio.service /etc/systemd/system/minio.service",
      "systemctl daemon-reload",
      "systemctl enable --now minio",
      # Wait for MinIO to be ready
      "for i in $(seq 1 12); do curl -sf http://localhost:9000/minio/health/ready && break || sleep 5; done",
      "curl -sf http://localhost:9000/minio/health/ready && echo 'MinIO S3 API OK'",
      # Create bucket and service account via mc
      "mc alias set local http://localhost:9000 $${local.minio_root_user} $${local.minio_root_password} --quiet",
      "mc mb --ignore-existing local/cnpg-backups",
      "mc admin user add local $${local.minio_barman_ak} $${local.minio_barman_sk} 2>/dev/null || mc admin user enable local $${local.minio_barman_ak}",
      "mc admin policy attach local readwrite --user $${local.minio_barman_ak} 2>/dev/null || true",
      "echo MinIO provisioning complete",
    ]
  }
}

# Sync barman service-account credentials to 1Password Kubernetes vault for ESO.
# Requires 'op' CLI installed and signed in (op signin).
resource "null_resource" "minio_1password_sync" {
  depends_on = [null_resource.minio_provision]

  triggers = {
    barman_ak     = local.minio_barman_ak
    barman_sk_sha = sha256(local.minio_barman_sk)
  }

  provisioner "local-exec" {
    command = <<-OPCMD
      op item create \
        --vault=Kubernetes \
        --title=minio \
        --category=login \
        "username=$${local.minio_barman_ak}" \
        "access-key[text]=$${local.minio_barman_ak}" \
        "secret-key[password]=$${local.minio_barman_sk}" \
        2>/dev/null \
      || op item edit minio \
           --vault=Kubernetes \
           "access-key[text]=$${local.minio_barman_ak}" \
           "secret-key[password]=$${local.minio_barman_sk}"
    OPCMD
  }
}

output "minio01_info" {
  value = {
    vm_id        = proxmox_virtual_environment_container.minio01.id
    ipv4_address = "${replace(local.minio_class.ipv4, "/24", "")}"
    ipv6_address = "${replace(local.minio_class.ipv6, "/64", "")}"
  }
}

output "minio_s3_endpoint" {
  value = "http://minio.sulibot.com:9000"
}

output "minio_console_url" {
  value = "http://[fd00:200::52]:9001"
}
EOF
}
