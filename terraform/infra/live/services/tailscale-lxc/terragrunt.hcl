include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  versions      = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  tail_class    = local.lxc_catalog.services.tail
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  pve_ssh_hosts = local.proxmox_infra.ssh_hosts
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

  locals {
    ssh_public_key                 = data.sops_file.secrets.data["ssh_public_key"]
    pve_ssh_hosts                  = ${jsonencode(local.pve_ssh_hosts)}
    tailscale_tag                  = "${local.tail_class.tailscale.tag}"
    tailscale_advertise_exit_node  = ${try(local.tail_class.tailscale.advertise_exit_node, false)}
    tailscale_advertise_routes     = ${jsonencode(local.tail_class.tailscale.advertise_routes)}
    tailscale_advertise_routes_csv = join(",", local.tailscale_advertise_routes)
    tailscale_exit_node_arg        = local.tailscale_advertise_exit_node ? "--advertise-exit-node" : ""

  containers = {
%{for name, instance in local.tail_class.instances~}
    ${name} = {
      vm_id           = ${instance.vm_id}
      node_name       = "${instance.node_name}"
      hostname        = "${instance.hostname}"
      description     = "Tailscale client LXC on ${instance.node_name} (tenant ${local.tail_class.tenant_id})"
      cpu_cores       = ${local.tail_class.sizing.cpu_cores}
      memory_mb       = ${local.tail_class.sizing.memory_mb}
      swap_mb         = ${local.tail_class.sizing.swap_mb}
      disk_gb         = ${local.tail_class.sizing.disk_gb}
      bridge          = "${local.tail_class.network.bridge}"
      vlan_id         = ${local.tail_class.network.vlan_id == null ? "null" : local.tail_class.network.vlan_id}
      firewall        = false
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "${instance.ipv4_cidr}"
      ipv4_gateway    = "${local.tail_class.network.ipv4_gateway}"
      ipv6_address    = "${instance.ipv6_cidr}"
      ipv6_gateway    = "${local.tail_class.network.ipv6_gateway}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["tailscale", "lxc", "trixie"]
      mount_points    = []
    }
%{endfor~}
  }

  tail_provision_commands = [
    "set -euo pipefail",
    "export DEBIAN_FRONTEND=noninteractive",
    "rm -f /etc/apt/sources.list.d/tailscale.list /etc/apt/keyrings/tailscale-archive-keyring.gpg /usr/share/keyrings/tailscale-archive-keyring.gpg",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends ca-certificates curl ethtool gnupg iproute2 >/dev/null",
    "install -d -m 0755 /usr/share/keyrings",
    ". /etc/os-release && curl -fsSL https://pkgs.tailscale.com/stable/debian/$VERSION_CODENAME.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg",
    ". /etc/os-release && curl -fsSL https://pkgs.tailscale.com/stable/debian/$VERSION_CODENAME.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends tailscale >/dev/null",
    "cat > /etc/sysctl.d/99-tailscale-subnet-router.conf <<'SYSCTL'\nnet.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\nSYSCTL",
    "sysctl -w net.ipv4.ip_forward=1 >/dev/null",
    "sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null",
    "cat > /usr/local/sbin/tailscale-ethtool-tune <<'SCRIPT'\n#!/bin/sh\nset -eu\nNETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d ' ')\nethtool -K \"$NETDEV\" rx-udp-gro-forwarding on rx-gro-list off\nSCRIPT\nchmod 755 /usr/local/sbin/tailscale-ethtool-tune",
    "cat > /etc/systemd/system/tailscale-ethtool-tune.service <<'UNIT'\n[Unit]\nDescription=Tune network offloads for Tailscale subnet routing\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/tailscale-ethtool-tune\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
    "systemctl daemon-reload",
    "systemctl enable --now tailscale-ethtool-tune.service",
    "systemctl enable --now tailscaled",
    "test -c /dev/net/tun",
    "chmod 600 /root/tailscale-auth.env",
    "set +e; set -a; . /root/tailscale-auth.env; set +a; tailscale up --auth-key=\"$TAILSCALE_AUTHKEY\" --advertise-tags=$${local.tailscale_tag} --advertise-routes=$${local.tailscale_advertise_routes_csv} $${local.tailscale_exit_node_arg} --ssh --hostname=\"$(hostname -s)\" --accept-dns=false; rc=$?; rm -f /root/tailscale-auth.env; set -e; exit $rc",
    "tailscale status --json >/dev/null",
    "tailscale ip -4 >/dev/null",
    "tailscale version",
  ]

  host_records = {
    for name, container in local.containers : name => {
      domain = "$${container.hostname}.sulibot.com"
      ipv4   = split("/", container.ipv4_address)[0]
      ipv6   = split("/", container.ipv6_address)[0]
    }
  }
}

module "tailscale_lxc" {
  source = "../../../modules/proxmox_lxc_role"

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.tail_class.storage.vm_datastore}"
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
    enabled            = false
    ssh_user           = "root"
    ssh_private_key    = ""
    ssh_timeout        = "10m"
    wait_for_cloudinit = false
    commands           = []
  }
}

resource "null_resource" "tailscale_host_config" {
  for_each = local.containers

  depends_on = [module.tailscale_lxc]

  triggers = {
    container_id = module.tailscale_lxc.containers[each.key].id
    vm_id        = tostring(each.value.vm_id)
    node_name    = each.value.node_name
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = local.pve_ssh_hosts[each.value.node_name]
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "pct stop $${each.value.vm_id} >/dev/null 2>&1 || true",
      "pct set $${each.value.vm_id} --onboot 1 --dev0 path=/dev/net/tun",
      "pct start $${each.value.vm_id}",
      "for i in $(seq 1 24); do pct exec $${each.value.vm_id} -- sh -lc 'test -c /dev/net/tun' && break || sleep 5; done",
      "pct exec $${each.value.vm_id} -- sh -lc 'test -c /dev/net/tun'",
    ]
  }
}

resource "null_resource" "tailscale_provision" {
  for_each = local.containers

  depends_on = [null_resource.tailscale_host_config]

  triggers = {
    container_id = module.tailscale_lxc.containers[each.key].id
    commands_sha = sha256(join("\n", local.tail_provision_commands))
    routes_sha   = sha256(join(",", local.tailscale_advertise_routes))
    auth_sha     = sha256(data.sops_file.secrets.data["tailscale_oauth_client_secret"])
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = split("/", each.value.ipv4_address)[0]
    timeout     = "10m"
  }

  provisioner "file" {
    content     = "TAILSCALE_AUTHKEY=$${data.sops_file.secrets.data["tailscale_oauth_client_secret"]}\n"
    destination = "/root/tailscale-auth.env"
  }

  provisioner "remote-exec" {
    inline = local.tail_provision_commands
  }
}

resource "routeros_ip_dns_record" "tailscale_host_ipv4" {
  for_each = local.host_records

  name    = each.value.domain
  type    = "A"
  address = each.value.ipv4
  ttl     = "5m"
  comment = "managed by terraform tailscale-lxc"
}

resource "routeros_ip_dns_record" "tailscale_host_ipv6" {
  for_each = local.host_records

  name    = each.value.domain
  type    = "AAAA"
  address = each.value.ipv6
  ttl     = "5m"
  comment = "managed by terraform tailscale-lxc"
}

output "tailscale_lxc_containers" {
  value = module.tailscale_lxc.containers
}

output "tailscale_hosts" {
  value = local.host_records
}
EOF2
}
