# Debian VM validating direct, path-scoped CephFS access. Cloud-init installs
# only non-secret client prerequisites; the CephX secret is enrolled by the
# user-storage validation runbook after creation.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  catalog       = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  kanidm_auth   = read_terragrunt_config(find_in_parent_folders("common/lxc-kanidm-auth.hcl")).locals
  guest         = local.catalog.services["debfs-vm"]
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
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
  endpoint = "${local.proxmox_infra.api_endpoint}"
  username = "root@pam"
  password = data.sops_file.secrets.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}

terraform {
  backend "gcs" {}
}
EOF2
}

terraform {
  source = "../../../modules/debian_vm"
}

inputs = {
  vm_name = local.guest.hostname
  vm_id   = local.guest.vm_id

  proxmox = {
    node_name    = local.guest.node_name
    datastore_id = local.proxmox_infra.storage.datastore_id
    vm_datastore = local.guest.storage.vm_datastore
    migrate      = false
  }

  vm_resources = {
    cpu_cores = local.guest.sizing.cpu_cores
    memory_mb = local.guest.sizing.memory_mb
    disk_gb   = local.guest.sizing.disk_gb
  }

  network = {
    bridge       = local.guest.network.bridge
    vlan_id      = local.guest.network.vlan_id
    ipv4_address = local.guest.ipv4_cidr
    ipv4_gateway = local.guest.network.ipv4_gateway
    ipv6_address = local.guest.ipv6_cidr
    ipv6_gateway = local.guest.network.ipv6_gateway
  }

  dns_servers      = [local.catalog.site.dns_servers.ipv4, local.catalog.site.dns_servers.ipv6]
  ssh_public_key   = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
  debian_version   = "13"
  debian_image_url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
  initial_packages = [
    "acl",
    "attr",
    "ceph-common",
    "nfs-common",
    "qemu-guest-agent",
  ]
  setup_script = <<-SCRIPT
    install -d -m 0755 /etc/kanidm
    printf '%s\n' 'uri = "https://idm.sulibot.com"' > /etc/kanidm/config
    printf '%s\n' 'version = "2"' '[kanidm]' 'pam_allowed_login_groups = ["${local.kanidm_auth.kanidm_login_group}"]' > /etc/kanidm/unixd
    chmod 0600 /etc/kanidm/config /etc/kanidm/unixd
    if command -v kanidm_unixd >/dev/null 2>&1; then
      systemctl enable --now kanidm-unixd kanidm-unixd-tasks
    fi
    install -d -o 1888405477 -g 1888405477 -m 0700 /home/sulibot
    install -d -o 1888405477 -g 1888405477 -m 0750 /home/sulibot/Cloud
    install -d -m 0755 /srv/common
    grep -qF 'sulibot-cloud@.content=/users/sulibot/Cloud /home/sulibot/Cloud ceph' /etc/fstab ||
      printf '%s\n' \
        'sulibot-cloud@.content=/users/sulibot/Cloud /home/sulibot/Cloud ceph noauto,x-systemd.automount,x-systemd.idle-timeout=10min,_netdev 0 0' \
        >> /etc/fstab
    grep -qF '10.200.0.209:/common /srv/common nfs4' /etc/fstab ||
      printf '%s\n' \
        '10.200.0.209:/common /srv/common nfs4 noauto,x-systemd.automount,x-systemd.idle-timeout=10min,_netdev,vers=4.1,proto=tcp,hard 0 0' \
        >> /etc/fstab
    cat >/etc/systemd/system/user-storage-ceph-route.service <<'EOF'
    [Unit]
    Description=Route Ceph messenger traffic through the local PVE node
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/sbin/ip -6 route replace fc00:20::/64 via fd00:200::3 dev eth0
    ExecStop=/usr/sbin/ip -6 route del fc00:20::/64 via fd00:200::3 dev eth0

    [Install]
    WantedBy=multi-user.target
    EOF
    systemctl daemon-reload
    systemctl enable --now user-storage-ceph-route.service
  SCRIPT
  tags         = ["vm", "user-storage-validation"]
}
