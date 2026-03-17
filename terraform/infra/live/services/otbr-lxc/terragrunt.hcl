include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  versions            = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  proxmox_infra       = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra       = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog         = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  otbr_class          = local.lxc_catalog.services.otbr
  credentials         = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file        = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  host_domain         = "${local.otbr_class.hostname}.sulibot.com"
  service_domain      = "otbr.sulibot.com"
  rcp_device          = "/dev/ttyACM0"
  otbr_git_ref        = "thread-reference-20250612"
  infra_if_name       = "eth0"
  radio_url           = "spinel+hdlc+uart://${local.rcp_device}?uart-baudrate=460800"
  thread_network_name = "sulibot-home"
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

locals {
  ssh_public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))
  host_domain    = "${local.host_domain}"
  service_domain = "${local.service_domain}"
  container_ipv4 = "${replace(local.otbr_class.ipv4, "/24", "")}"
  container_ipv6 = "${replace(local.otbr_class.ipv6, "/64", "")}"
  thread_dataset_tlv = data.sops_file.secrets.data["otbr_thread_dataset_secret"]

  containers = {
    otbr01 = {
      vm_id           = ${local.otbr_class.vm_id}
      node_name       = "${local.otbr_class.node_name}"
      hostname        = "${local.otbr_class.hostname}"
      description     = "OpenThread Border Router LXC on ${local.otbr_class.node_name} using SONOFF ZBDongle-E RCP"
      started         = false
      cpu_cores       = ${local.otbr_class.sizing.cpu_cores}
      memory_mb       = ${local.otbr_class.sizing.memory_mb}
      swap_mb         = ${local.otbr_class.sizing.swap_mb}
      disk_gb         = ${local.otbr_class.sizing.disk_gb}
      bridge          = "${local.otbr_class.network.bridge}"
      vlan_id         = ${local.otbr_class.network.vlan_id}
      firewall        = false
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "${local.otbr_class.ipv4}"
      ipv4_gateway    = "${local.otbr_class.network.ipv4_gateway}"
      ipv6_address    = "${local.otbr_class.ipv6}"
      ipv6_gateway    = "${local.otbr_class.network.ipv6_gateway}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["thread", "matter", "otbr", "lxc", "trixie"]
      mount_points = [
        {
          volume = "${local.otbr_class.storage.vm_datastore}"
          size   = "8G"
          path   = "/var/lib/otbr"
        }
      ]
    }
  }

  otbr_provision_commands = [
    "set -euo pipefail",
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update -qq >/dev/null",
    "apt-get install -y -qq --no-install-recommends ca-certificates curl git iproute2 jq lsb-release sudo >/dev/null",
    "mkdir -p /etc/iproute2",
    "touch /etc/iproute2/rt_tables",
    "mkdir -p /var/lib/otbr",
    "if [ ! -d /opt/ot-br-posix/.git ]; then git clone https://github.com/openthread/ot-br-posix /opt/ot-br-posix >/dev/null 2>&1; fi",
    "cd /opt/ot-br-posix && git fetch --tags --force >/dev/null 2>&1 && git checkout -f ${local.otbr_git_ref} >/dev/null 2>&1 && git submodule update --init --recursive --depth 1 >/dev/null 2>&1 || git submodule update --init --recursive >/dev/null 2>&1",
    "cd /opt/ot-br-posix && OTBR_MDNS=avahi WEB_GUI=1 NAT64=0 BORDER_ROUTING=1 INFRA_IF_NAME=${local.infra_if_name} ./script/bootstrap",
    "cd /opt/ot-br-posix && ./script/cmake-build -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=/usr -DOTBR_DBUS=ON -DOTBR_DNSSD_DISCOVERY_PROXY=ON -DOTBR_INFRA_IF_NAME=${local.infra_if_name} -DOTBR_MDNS=avahi -DOTBR_VERSION= -DOT_PACKAGE_VERSION= -DOTBR_SRP_ADVERTISING_PROXY=ON -DOTBR_WEB=ON -DOTBR_BORDER_ROUTING=ON -DOTBR_REST=ON -DOTBR_BACKBONE_ROUTER=ON -DOT_FIREWALL=ON",
    "cd /opt/ot-br-posix/build/otbr && ninja",
    "cd /opt/ot-br-posix/build/otbr && ninja install",
    "test -x /usr/sbin/otbr-agent",
    "test -x /etc/init.d/otbr-agent",
    "cat > /etc/default/otbr-agent <<'CONF'\nOTBR_AGENT_OPTS=\"-I wpan0 -B ${local.infra_if_name} -d 7 ${local.radio_url} trel://${local.infra_if_name}\"\nCONF",
    "systemctl daemon-reload",
    "systemctl enable otbr-agent",
    "systemctl enable otbr-web",
    "systemctl start otbr-agent",
    "for i in $(seq 1 12); do systemctl is-active --quiet otbr-agent && break || sleep 5; done",
    "systemctl start otbr-web",
    "for i in $(seq 1 24); do systemctl is-active --quiet otbr-agent && systemctl is-active --quiet otbr-web && break || sleep 5; done",
    "systemctl is-active --quiet otbr-agent",
    "systemctl is-active --quiet otbr-web",
    "timeout 10 ot-ctl state >/dev/null",
    "timeout 10 ot-ctl dataset set active $${local.thread_dataset_tlv}",
    "timeout 10 ot-ctl dataset init active",
    "timeout 10 ot-ctl dataset networkname ${local.thread_network_name}",
    "timeout 10 ot-ctl dataset commit active",
    "timeout 10 ot-ctl ifconfig up",
    "timeout 10 ot-ctl thread start",
    "timeout 10 sh -lc \"ot-ctl dataset active | grep -F 'Network Name: ${local.thread_network_name}'\"",
    "journalctl -u otbr-agent --no-pager -n 20 | tail -n 20",
  ]
}

module "otbr_lxc" {
  source = "../../../modules/proxmox_lxc_role"

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.otbr_class.storage.vm_datastore}"
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

resource "null_resource" "otbr_host_config" {
  depends_on = [module.otbr_lxc]

  triggers = {
    container_id = module.otbr_lxc.containers["otbr01"].id
    vm_id        = "${local.otbr_class.vm_id}"
    rcp_device   = "${local.rcp_device}"
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "10.10.0.1"
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "pct stop ${local.otbr_class.vm_id} >/dev/null 2>&1 || true",
      "pct set ${local.otbr_class.vm_id} --onboot 1 --dev0 path=/dev/net/tun --dev1 path=${local.rcp_device}",
      "pct start ${local.otbr_class.vm_id}",
      "for i in $(seq 1 24); do pct exec ${local.otbr_class.vm_id} -- sh -lc 'test -e /dev/net/tun && test -e ${local.rcp_device}' && break || sleep 5; done",
      "pct exec ${local.otbr_class.vm_id} -- sh -lc 'test -e /dev/net/tun && test -e ${local.rcp_device}'",
    ]
  }
}

resource "null_resource" "otbr_provision" {
  depends_on = [null_resource.otbr_host_config]

  triggers = {
    container_id = module.otbr_lxc.containers["otbr01"].id
    commands_sha = sha256(join("\n", local.otbr_provision_commands))
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = local.container_ipv4
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = local.otbr_provision_commands
  }
}

output "otbr_lxc_containers" {
  value = module.otbr_lxc.containers
}

output "otbr_endpoints" {
  value = {
    host      = local.host_domain
    service   = local.service_domain
    ipv4      = local.container_ipv4
    ipv6      = local.container_ipv6
  }
}

resource "routeros_ip_dns_record" "otbr_host_ipv4" {
  name    = local.host_domain
  type    = "A"
  address = local.container_ipv4
  ttl     = "5m"
  comment = "managed by terraform otbr-lxc"
}

resource "routeros_ip_dns_record" "otbr_host_ipv6" {
  name    = local.host_domain
  type    = "AAAA"
  address = local.container_ipv6
  ttl     = "5m"
  comment = "managed by terraform otbr-lxc"
}

resource "routeros_ip_dns_record" "otbr_service_cname" {
  name    = local.service_domain
  type    = "CNAME"
  cname   = local.host_domain
  ttl     = "5m"
  comment = "managed by terraform otbr-lxc"
}
EOF2
}
