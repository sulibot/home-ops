include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  kanidm_auth   = read_terragrunt_config(find_in_parent_folders("common/lxc-kanidm-auth.hcl")).locals
  kanidm_class  = local.lxc_catalog.services.kanidm
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  tenant_id     = local.kanidm_class.tenant_id
  kanidm_vnet   = local.kanidm_class.network.bridge
  kanidm_gw4    = local.kanidm_class.network.ipv4_gateway
  kanidm_gw6    = local.kanidm_class.network.ipv6_gateway
  kanidm_nodes  = ["10.100.0.61", "10.100.0.62", "10.100.0.63"]
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
  # Force internal API endpoint for homelab provisioning (avoid public DNS/CF path).
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
EOF2
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
terraform {
  backend "gcs" {}

  required_providers {
    proxmox = { source = "bpg/proxmox", version = "${local.lxc_catalog.lxc_defaults.provider_version}" }
    sops    = { source = "carlpett/sops", version = "~> 1.4.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

locals {
  ssh_public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))
  kanidm_unix_auth_commands = ${jsonencode(local.kanidm_auth.kanidm_unix_auth_commands)}
  kanidm_domain  = "idm.sulibot.com"
  kanidm_origin  = "https://idm.sulibot.com"
  kanidm_vip4    = "10.100.0.60"
  kanidm_vip6    = "fd00:100::60"
  kanidm_tls_item = "sulibot-com-tls"
  kanidm_nodes   = ["10.100.0.61", "10.100.0.62", "10.100.0.63"]

  # One Kanidm LXC per Proxmox node for host-level fault isolation.
  containers = {
    kanidm01 = {
      vm_id           = 100061
      node_name       = "pve01"
      hostname        = "kanidm01"
      description     = "Kanidm identity node on pve01"
      cpu_cores       = ${local.kanidm_class.sizing.cpu_cores}
      memory_mb       = ${local.kanidm_class.sizing.memory_mb}
      swap_mb         = ${local.kanidm_class.sizing.swap_mb}
      disk_gb         = ${local.kanidm_class.sizing.disk_gb}
      bridge          = "${local.kanidm_vnet}"
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "10.100.0.61/24"
      ipv4_gateway    = "${local.kanidm_gw4}"
      ipv6_address    = "fd00:100::61/64"
      ipv6_gateway    = "${local.kanidm_gw6}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["identity", "kanidm", "lxc", "trixie"]
      mount_points = [
        {
          volume = "rbd-vm"
          size   = "20G"
          path   = "/var/lib/kanidm"
        }
      ]
    }
    kanidm02 = {
      vm_id           = 100062
      node_name       = "pve02"
      hostname        = "kanidm02"
      description     = "Kanidm identity node on pve02"
      cpu_cores       = ${local.kanidm_class.sizing.cpu_cores}
      memory_mb       = ${local.kanidm_class.sizing.memory_mb}
      swap_mb         = ${local.kanidm_class.sizing.swap_mb}
      disk_gb         = ${local.kanidm_class.sizing.disk_gb}
      bridge          = "${local.kanidm_vnet}"
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "10.100.0.62/24"
      ipv4_gateway    = "${local.kanidm_gw4}"
      ipv6_address    = "fd00:100::62/64"
      ipv6_gateway    = "${local.kanidm_gw6}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["identity", "kanidm", "lxc", "trixie"]
      mount_points = [
        {
          volume = "rbd-vm"
          size   = "20G"
          path   = "/var/lib/kanidm"
        }
      ]
    }
    kanidm03 = {
      vm_id           = 100063
      node_name       = "pve03"
      hostname        = "kanidm03"
      description     = "Kanidm identity node on pve03"
      cpu_cores       = ${local.kanidm_class.sizing.cpu_cores}
      memory_mb       = ${local.kanidm_class.sizing.memory_mb}
      swap_mb         = ${local.kanidm_class.sizing.swap_mb}
      disk_gb         = ${local.kanidm_class.sizing.disk_gb}
      bridge          = "${local.kanidm_vnet}"
      features = {
        nesting = true
        keyctl  = true
      }
      ipv4_address    = "10.100.0.63/24"
      ipv4_gateway    = "${local.kanidm_gw4}"
      ipv6_address    = "fd00:100::63/64"
      ipv6_gateway    = "${local.kanidm_gw6}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["identity", "kanidm", "lxc", "trixie"]
      mount_points = [
        {
          volume = "rbd-vm"
          size   = "20G"
          path   = "/var/lib/kanidm"
        }
      ]
    }
  }

  kanidm_provision_commands = concat(local.kanidm_unix_auth_commands, [
    "export DEBIAN_FRONTEND=noninteractive",
    "sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf",
    "awk '!/idm01|idm02|idm03/ {print}' /etc/hosts > /etc/hosts.new && cat >> /etc/hosts.new <<'HOSTS'\n10.100.0.61 idm01.sulibot.com idm01\n10.100.0.62 idm02.sulibot.com idm02\n10.100.0.63 idm03.sulibot.com idm03\nfd00:100::61 idm01.sulibot.com idm01\nfd00:100::62 idm02.sulibot.com idm02\nfd00:100::63 idm03.sulibot.com idm03\nHOSTS\nmv /etc/hosts.new /etc/hosts",
    "printf 'nameserver 1.1.1.1\\nnameserver 2606:4700:4700::1111\\n' > /etc/resolv.conf",
    "apt-get update -qq",
    "apt-get install -y -qq curl ca-certificates openssl sqlite3 restic gnupg caddy bird2",
    "mkdir -p /etc/apt/keyrings",
    "rm -f /etc/apt/sources.list.d/kanidm_ppa.list /etc/apt/trusted.gpg.d/kanidm_ppa.asc",
    "curl -fsSL https://kanidm.github.io/kanidm_ppa/kanidm_ppa.asc | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kanidm_ppa.gpg",
    "echo 'deb [signed-by=/etc/apt/keyrings/kanidm_ppa.gpg] https://kanidm.github.io/kanidm_ppa bookworm stable' > /etc/apt/sources.list.d/kanidm_ppa.list",
    "apt-get update -qq",
    "apt-get install -y -qq kanidmd kanidm expect",
    "mkdir -p /etc/kanidm/tls /etc/systemd/system/kanidmd.service.d /etc/systemd/system/caddy.service.d /var/lib/kanidm /var/backups/kanidm/snapshots",
    "cat > /usr/local/sbin/kanidm-write-config.sh <<'SCRIPT'\n#!/usr/bin/env bash\nset -euo pipefail\nIP4=\"$(ip -4 -o addr show dev eth0 scope global | awk '{print $4}' | cut -d/ -f1 | head -n1)\"\n# Replication peers contain node identity certificates generated after first\n# boot. Preserve them when Terraform refreshes the baseline configuration.\nPARTNERS=\"\"\nif [ -f /etc/kanidmd/server.toml ]; then\n  PARTNERS=\"$(sed -n '/^\\[replication\\.\"/,$p' /etc/kanidmd/server.toml)\"\nfi\ncat > /etc/kanidmd/server.toml <<CFG\nversion = \"2\"\nlog_level = 'debug'\n# Baseline Kanidm config managed by Terraform provisioning.\nbindaddress = '[::]:8443'\nldapbindaddress = '[::]:3636'\ndomain = '$${local.kanidm_domain}'\norigin = '$${local.kanidm_origin}'\ndb_path = '/var/lib/kanidm/kanidm.db'\nrole = 'WriteReplica'\ntls_chain = '/etc/kanidmd/chain.pem'\ntls_key = '/etc/kanidmd/key.pem'\n[replication]\norigin = \"repl://$IP4:8444\"\nbindaddress = \"[::]:8444\"\nCFG\nif [ -n \"$PARTNERS\" ]; then\n  printf '\\n%s\\n' \"$PARTNERS\" >> /etc/kanidmd/server.toml\nfi\nSCRIPT",
    "chmod 750 /usr/local/sbin/kanidm-write-config.sh",
    "/usr/local/sbin/kanidm-write-config.sh",
    "cat > /etc/systemd/system/kanidmd.service.d/override.conf <<'UNIT'\n[Service]\n# LXC compatibility: disable namespace isolation directives that fail in unprivileged containers.\nDynamicUser=no\nUser=root\nGroup=kanidmd\nPrivateTmp=false\nPrivateDevices=false\nProtectHostname=false\nProtectClock=false\nProtectKernelTunables=false\nProtectKernelModules=false\nProtectKernelLogs=false\nProtectControlGroups=false\nMemoryDenyWriteExecute=false\nNoNewPrivileges=false\n# Persist kanidmd logs in-file because journald/rsyslog are constrained in this LXC profile.\nStandardOutput=append:/var/log/kanidmd.log\nStandardError=append:/var/log/kanidmd.log\nUNIT",
    "cat > /etc/systemd/system/caddy.service.d/override.conf <<'UNIT'\n[Service]\n# LXC compatibility: relax namespace/sandbox options that fail in unprivileged containers.\nPrivateTmp=false\nPrivateDevices=false\nProtectSystem=no\nProtectHome=false\nNoNewPrivileges=false\nUNIT",
    "install -d -m 755 /usr/local/share/kanidm-ui/pkg",
    "printf '%s' '${filebase64("${get_terragrunt_dir()}/kanidm-ui-style.js")}' | base64 --decode > /usr/local/share/kanidm-ui/pkg/style.js",
    "printf '%s' '${filebase64("${get_terragrunt_dir()}/Caddyfile")}' | base64 --decode > /etc/caddy/Caddyfile",
    "cat > /etc/bird/bird.conf <<'CFG'\nlog syslog all;\nrouter id 10.100.0.1;\n\ndefine VIP4 = 10.100.0.60/32;\ndefine VIP6 = fd00:100::60/128;\ndefine LOCAL_AS = 4210000000;\ndefine PEER_AS = 4200001000;\ndefine PEER4 = 10.100.0.254;\ndefine PEER6 = fd00:100::fffe;\n\nprotocol device {}\n\nprotocol direct {\n  ipv4;\n  ipv6;\n  interface \"eth0\", \"lo\";\n}\n\nprotocol kernel k4 {\n  ipv4 {\n    import all;\n    export none;\n  };\n}\n\nprotocol kernel k6 {\n  ipv6 {\n    import all;\n    export none;\n  };\n}\n\nprotocol static anycast4 {\n  ipv4;\n  route VIP4 blackhole;\n}\n\nprotocol static anycast6 {\n  ipv6;\n  route VIP6 blackhole;\n}\n\nprotocol bgp upstream4 {\n  local as LOCAL_AS;\n  neighbor PEER4 as PEER_AS;\n  source address 10.100.0.1;\n  ipv4 {\n    import none;\n    export where net = VIP4;\n  };\n}\n\nprotocol bgp upstream6 {\n  local as LOCAL_AS;\n  neighbor PEER6 as PEER_AS;\n  source address fd00:100::1;\n  ipv6 {\n    import none;\n    export where net = VIP6;\n  };\n}\nCFG",
    "cat > /usr/local/sbin/kanidm-vip.sh <<'SCRIPT'\n#!/usr/bin/env bash\nset -euo pipefail\nip -4 addr show dev lo | grep -q '10.100.0.60/32' || ip -4 addr add 10.100.0.60/32 dev lo\nip -6 addr show dev lo | grep -q 'fd00:100::60/128' || ip -6 addr add fd00:100::60/128 dev lo\nSCRIPT",
    "chmod 750 /usr/local/sbin/kanidm-vip.sh",
    "cat > /etc/systemd/system/kanidm-vip.service <<'UNIT'\n[Unit]\nDescription=Assign Kanidm anycast VIPs to loopback\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/kanidm-vip.sh\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\nUNIT",
    "IP4=$(ip -4 -o addr show dev eth0 scope global | awk '{print $4}' | cut -d/ -f1 | head -n1); IP6=$(ip -6 -o addr show dev eth0 scope global | awk '{print $4}' | cut -d/ -f1 | head -n1); OCT=$(echo \"$IP4\" | awk -F. '{print $4}'); [ -n \"$IP4\" ] && sed -i \"s/router id 10\\.100\\.0\\.1;/router id $IP4;/\" /etc/bird/bird.conf && sed -i \"s/source address 10\\.100\\.0\\.1;/source address $IP4;/\" /etc/bird/bird.conf; [ -n \"$IP6\" ] && sed -i \"s/source address fd00:100::1;/source address $IP6;/\" /etc/bird/bird.conf; [ -n \"$OCT\" ] && sed -i \"s/define LOCAL_AS = 4210000000;/define LOCAL_AS = 42100000$OCT;/\" /etc/bird/bird.conf",
    "cat > /usr/local/sbin/kanidm-anycast-health.sh <<'SCRIPT'\n#!/usr/bin/env bash\nset -euo pipefail\n\nok=1\ncurl -skf --max-time 2 https://127.0.0.1:8443/status >/dev/null 2>&1 || ok=0\nss -ltn '( sport = :3636 )' | grep -q ':3636' || ok=0\n\nif [ \"$ok\" -eq 1 ]; then\n  birdc enable anycast4 >/dev/null 2>&1 || true\n  birdc enable anycast6 >/dev/null 2>&1 || true\nelse\n  birdc disable anycast4 >/dev/null 2>&1 || true\n  birdc disable anycast6 >/dev/null 2>&1 || true\nfi\nSCRIPT",
    "chmod 750 /usr/local/sbin/kanidm-anycast-health.sh",
    "cat > /etc/systemd/system/kanidm-anycast-health.service <<'UNIT'\n[Unit]\nDescription=Kanidm anycast health check toggling BIRD route export\nAfter=network-online.target bird.service kanidmd.service\nWants=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/kanidm-anycast-health.sh\nUNIT",
    "cat > /etc/systemd/system/kanidm-anycast-health.timer <<'UNIT'\n[Unit]\nDescription=Run Kanidm anycast health check every 5 seconds\n\n[Timer]\nOnBootSec=10s\nOnUnitActiveSec=5s\nUnit=kanidm-anycast-health.service\n\n[Install]\nWantedBy=timers.target\nUNIT",
    "printf '%s' '${filebase64("${get_terragrunt_dir()}/kanidm-backup.sh")}' | base64 --decode > /usr/local/sbin/kanidm-backup.sh",
    "chmod 750 /usr/local/sbin/kanidm-backup.sh",
    "cat > /etc/systemd/system/kanidm-backup.service <<'UNIT'\n[Unit]\nDescription=Kanidm backup snapshot to local restic repo\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/kanidm-backup.sh\nUNIT",
    "cat > /etc/systemd/system/kanidm-backup.timer <<'UNIT'\n[Unit]\nDescription=Run Kanidm backup every hour\n\n[Timer]\nOnCalendar=hourly\nPersistent=true\nRandomizedDelaySec=5m\n\n[Install]\nWantedBy=timers.target\nUNIT",
    "install -m 640 -o root -g kanidmd /dev/null /var/log/kanidmd.log || true",
    "chown -R root:kanidmd /var/lib/kanidm /etc/kanidm",
    "if [ ! -f /etc/kanidm/tls/tls.crt ] || [ ! -f /etc/kanidm/tls/tls.key ]; then openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/kanidm/tls/tls.key -out /etc/kanidm/tls/tls.crt -sha256 -days 365 -subj \"/CN=$${local.kanidm_domain}\"; fi",
    "chown root:kanidmd /etc/kanidm/tls/tls.crt /etc/kanidm/tls/tls.key",
    "cp /etc/kanidm/tls/tls.crt /etc/kanidmd/chain.pem && cp /etc/kanidm/tls/tls.key /etc/kanidmd/key.pem && chown root:kanidmd /etc/kanidmd/chain.pem /etc/kanidmd/key.pem && chmod 640 /etc/kanidmd/chain.pem /etc/kanidmd/key.pem",
    "id caddy >/dev/null 2>&1 && usermod -a -G kanidmd caddy || true",
    "kanidmd domain rename -c /etc/kanidmd/server.toml || true",
    "chmod 750 /var/lib/kanidm /etc/kanidm/tls",
    "chmod 755 /etc/kanidm",
    "chmod 640 /etc/kanidmd/server.toml /etc/kanidm/tls/tls.crt /etc/kanidm/tls/tls.key",
    "systemctl daemon-reload",
    "systemctl disable --now rsyslog >/dev/null 2>&1 || true",
    "systemctl reset-failed rsyslog systemd-journald >/dev/null 2>&1 || true",
    "systemctl enable --now kanidm-vip.service",
    "systemctl disable --now kanidm-replica-seed.service >/dev/null 2>&1 || true",
    "systemctl enable --now kanidmd",
    "systemctl enable --now bird",
    "birdc disable anycast4 >/dev/null 2>&1 || true",
    "birdc disable anycast6 >/dev/null 2>&1 || true",
    "systemctl enable --now caddy",
    "systemctl restart caddy",
    "systemctl enable --now kanidm-anycast-health.timer",
    "systemctl enable --now kanidm-backup.timer",
    # Package installs above need reliable resolution before internal DNS is
    # necessarily reachable, hence the public resolvers earlier. Switch back
    # to internal DNS (site.yaml, already the centralized source used
    # elsewhere in this repo) now that bootstrap is done, so idm.sulibot.com
    # and other internal names resolve normally instead of needing per-host
    # /etc/hosts patches.
    "printf 'nameserver ${local.network_infra.dns_servers.ipv6}\\nnameserver ${local.network_infra.dns_servers.ipv4}\\n' > /etc/resolv.conf",
  ])
}

module "kanidm_lxc" {
  source = "../../../modules/proxmox_lxc_role"

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.kanidm_class.storage.vm_datastore}"
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
    commands           = local.kanidm_provision_commands
  }
}

output "kanidm_containers" {
  value = module.kanidm_lxc.containers
}

# Enforce required LXC feature flags for kanidm-unixd namespace support.
resource "null_resource" "kanidm_lxc_features" {
  triggers = {
    features_rev = "nesting-keyctl-v1"
    ctids        = "100061,100062,100063"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-SHELL
      set -euo pipefail
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      ensure_features() {
        local pve="$1"
        local ctid="$2"
        local features
        features="$(ssh $SSH_OPTS root@$pve "pct config $ctid | awk -F': ' '/^features:/{print \\$2}'" || true)"
        if [[ "$features" == *"nesting=1"* && "$features" == *"keyctl=1"* ]]; then
          echo "[$pve/$ctid] features already set: $features"
          return 0
        fi

        echo "[$pve/$ctid] setting features nesting=1,keyctl=1"
        timeout 30 ssh $SSH_OPTS root@$pve "pct set $ctid -features nesting=1,keyctl=1"
        echo "[$pve/$ctid] rebooting container to activate namespace features"
        timeout 120 ssh $SSH_OPTS root@$pve "pct reboot $ctid --timeout 60 || (pct stop $ctid --timeout 60; pct start $ctid)"
      }

      ensure_features 10.10.0.1 100061
      ensure_features 10.10.0.2 100062
      ensure_features 10.10.0.3 100063
    SHELL
  }
}

# Pull cert-manager/ACME wildcard cert from 1Password and install on each node.
resource "null_resource" "kanidm_tls_sync" {
  depends_on = [module.kanidm_lxc, null_resource.kanidm_lxc_features]

  triggers = {
    tls_item = local.kanidm_tls_item
    sync_rev = "k8s-secret-priority-v6-fixed"
    nodes    = join(",", local.kanidm_nodes)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-SHELL
      set -euo pipefail
      CERT=""
      KEY=""
      SOURCE=""
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
      CERT_OK=0

      decode_if_base64() {
        local input="$1"
        if printf "%s\n" "$input" | grep -q "BEGIN CERTIFICATE\\|BEGIN .*PRIVATE KEY"; then
          printf "%s\n" "$input"
        else
          printf "%s" "$input" | base64 --decode 2>/dev/null || printf "%s\n" "$input"
        fi
      }

      cert_matches_domain_and_key() {
        local cert="$1"
        local key="$2"
        local cert_pub key_pub
        cert_pub="$(printf "%s\n" "$cert" | openssl x509 -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}' || true)"
        key_pub="$(printf "%s\n" "$key"  | openssl pkey -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}' || true)"
        if [ -z "$cert_pub" ] || [ -z "$key_pub" ] || [ "$cert_pub" != "$key_pub" ]; then
          return 1
        fi
        # sulibot-com-tls is a wildcard cert (DNS:*.sulibot.com, DNS:sulibot.com),
        # not a literal DNS:idm.sulibot.com SAN - the old exact-match regex here
        # never matched, so this validation always failed and fell through to
        # the (also broken - see the "timeout" note below) fallback paths. The
        # currently-installed node certs predate this bug and were never
        # actually refreshed by this sync path.
        printf "%s\n" "$cert" | openssl x509 -noout -text 2>/dev/null | grep -qE "DNS:(\\*\\.sulibot\\.com|idm\\.sulibot\\.com)"
      }

      # Primary source: cert-manager managed wildcard cert from the in-cluster secret.
      if kubectl -n network get secret sulibot-com-tls >/dev/null 2>&1; then
        CERT="$(kubectl -n network get secret sulibot-com-tls -o jsonpath='{.data.tls\.crt}' | base64 --decode)"
        KEY="$(kubectl -n network get secret sulibot-com-tls -o jsonpath='{.data.tls\.key}' | base64 --decode)"
        if cert_matches_domain_and_key "$CERT" "$KEY"; then
          SOURCE="kubernetes-secret"
          CERT_OK=1
        else
          echo "TLS sync warning: Kubernetes secret sulibot-com-tls is invalid for idm.sulibot.com; ignoring."
          CERT=""
          KEY=""
        fi
      fi

      # Fallback source: 1Password mirror item.
      if [ -z "$CERT" ] || [ -z "$KEY" ]; then
        # Try 1Password directly (works with service-account mode where op whoami may fail).
        CERT="$(op item get "$${local.kanidm_tls_item}" --vault Kubernetes --fields label=crt 2>/dev/null || true)"
        KEY="$(op item get "$${local.kanidm_tls_item}" --vault Kubernetes --fields label=key 2>/dev/null || true)"
        if [ -z "$CERT" ] || [ -z "$KEY" ]; then
          CERT="$(op item get "$${local.kanidm_tls_item}" --vault Kubernetes --fields label=tls.crt 2>/dev/null || true)"
          KEY="$(op item get "$${local.kanidm_tls_item}" --vault Kubernetes --fields label=tls.key 2>/dev/null || true)"
        fi
        CERT="$(decode_if_base64 "$CERT")"
        KEY="$(decode_if_base64 "$KEY")"
        if [ -n "$CERT" ] && [ -n "$KEY" ]; then
          if cert_matches_domain_and_key "$CERT" "$KEY"; then
            SOURCE="1password"
            CERT_OK=1
          else
            echo "TLS sync warning: 1Password item $${local.kanidm_tls_item} is invalid for idm.sulibot.com; ignoring."
            CERT=""
            KEY=""
          fi
        fi
      fi

      # Last-resort fallback: clone currently-installed cert/key from any healthy node.
      if [ -z "$CERT" ] || [ -z "$KEY" ]; then
        for node in 10.100.0.61 10.100.0.62 10.100.0.63; do
          if ssh $SSH_OPTS root@$node "test -s /etc/kanidm/tls/tls.crt && test -s /etc/kanidm/tls/tls.key"; then
            CERT="$(ssh $SSH_OPTS root@$node "cat /etc/kanidm/tls/tls.crt")"
            KEY="$(ssh $SSH_OPTS root@$node "cat /etc/kanidm/tls/tls.key")"
            SOURCE="existing-node:$node"
            CERT_OK=1
            break
          fi
        done
      fi

      if [ -z "$CERT" ] || [ -z "$KEY" ]; then
        echo "TLS sync skipped: unable to read cert from Kubernetes secret, 1Password, or existing nodes."
        exit 0
      fi

      if [ "$CERT_OK" -ne 1 ]; then
        echo "TLS sync failed: selected certificate source did not pass validation."
        exit 1
      fi

      if [ "$SOURCE" != "kubernetes-secret" ] && [ "$SOURCE" != "1password" ]; then
        echo "TLS sync warning: using existing node certificate from $SOURCE. Wildcard validation skipped."
      fi

      for node in 10.100.0.61 10.100.0.62 10.100.0.63; do
        ssh $SSH_OPTS root@$node "install -d -m 750 /etc/kanidm/tls /etc/kanidmd"
        printf "%s\n" "$CERT" | ssh $SSH_OPTS root@$node "cat > /etc/kanidm/tls/tls.crt && chown root:kanidmd /etc/kanidm/tls/tls.crt && chmod 640 /etc/kanidm/tls/tls.crt"
        printf "%s\n" "$KEY"  | ssh $SSH_OPTS root@$node "cat > /etc/kanidm/tls/tls.key && chown root:kanidmd /etc/kanidm/tls/tls.key && chmod 640 /etc/kanidm/tls/tls.key"
        ssh $SSH_OPTS root@$node "cp /etc/kanidm/tls/tls.crt /etc/kanidmd/chain.pem && cp /etc/kanidm/tls/tls.key /etc/kanidmd/key.pem && chown root:kanidmd /etc/kanidmd/chain.pem /etc/kanidmd/key.pem && chmod 640 /etc/kanidmd/chain.pem /etc/kanidmd/key.pem"
        ssh $SSH_OPTS root@$node "systemctl restart kanidmd caddy"
      done
    SHELL
  }
}

# Sync Kanidm bootstrap metadata to 1Password Kubernetes vault for ESO.
resource "null_resource" "kanidm_1password_sync" {
  depends_on = [module.kanidm_lxc, null_resource.kanidm_lxc_features, null_resource.kanidm_tls_sync]

  triggers = {
    domain   = "idm.sulibot.com"
    sync_rev = "admin-sync-v2"
  }

  provisioner "local-exec" {
    command = <<-OPCMD
      set -euo pipefail
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      op whoami >/dev/null 2>&1 || { echo "Skipping 1Password metadata sync: 1Password CLI is not authenticated"; exit 0; }

      ITEM_ID="$(op item get kanidm --vault Kubernetes --format json 2>/dev/null | jq -r '.id' || true)"
      NEW_ITEM=0
      if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
        NEW_ITEM=1
        ITEM_ID="$(op item create \
          --vault=Kubernetes \
          --title=kanidm \
          --category=login \
          "username=idm_admin" \
          "password=$(openssl rand -base64 36 | tr -d '\n')" \
          "url[text]=$${local.kanidm_origin}" \
          "domain[text]=$${local.kanidm_domain}" \
          "node1[text]=10.100.0.61" \
          "node2[text]=10.100.0.62" \
          "node3[text]=10.100.0.63" \
          "vip4[text]=$${local.kanidm_vip4}" \
          "vip6[text]=$${local.kanidm_vip6}" \
          "replication_mode[text]=manual" \
          "ldap_uri[text]=ldaps://$${local.kanidm_domain}" \
          --format json | jq -r '.id')"
      fi

      # A freshly-created item's password is an arbitrary local random value
      # that was never actually applied to the server - it MUST be pushed via
      # recover-account, not just read back (reading it back is always
      # non-empty right after `op item create`, which used to make this
      # fallback never trigger and left 1Password out of sync with the real
      # idm_admin credential).
      if [ "$NEW_ITEM" = "1" ]; then
        ADMIN_PASS="$(ssh $SSH_OPTS root@10.100.0.61 "kanidmd recover-account -c /etc/kanidmd/server.toml idm_admin | sed -n 's/.*new_password: \"\\([^\"]*\\)\".*/\\1/p' | tail -n1")"
      else
        ADMIN_PASS="$(op item get "$ITEM_ID" --vault Kubernetes --fields password --reveal 2>/dev/null || true)"
        if [ -z "$ADMIN_PASS" ]; then
          ADMIN_PASS="$(ssh $SSH_OPTS root@10.100.0.61 "kanidmd recover-account -c /etc/kanidmd/server.toml idm_admin | sed -n 's/.*new_password: \"\\([^\"]*\\)\".*/\\1/p' | tail -n1")"
        fi
      fi

      op item edit "$ITEM_ID" \
        --vault=Kubernetes \
        "username=idm_admin" \
        "password=$ADMIN_PASS" \
        "url[text]=$${local.kanidm_origin}" \
        "domain[text]=$${local.kanidm_domain}" \
        "node1[text]=10.100.0.61" \
        "node2[text]=10.100.0.62" \
        "node3[text]=10.100.0.63" \
        "vip4[text]=$${local.kanidm_vip4}" \
        "vip6[text]=$${local.kanidm_vip6}" \
        "replication_mode[text]=manual" \
        "ldap_uri[text]=ldaps://$${local.kanidm_domain}" >/dev/null
    OPCMD
  }
}

# Configure full-mesh replication agreements and seed secondaries from node01.
resource "null_resource" "kanidm_replication_bootstrap" {
  depends_on = [module.kanidm_lxc, null_resource.kanidm_lxc_features, null_resource.kanidm_tls_sync]

  triggers = {
    bootstrap_rev = "repl-bootstrap-v6-primary-seeded"
    nodes         = join(",", local.kanidm_nodes)
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      get_repl_cert() {
        local node="$1"
        timeout 60 ssh $SSH_OPTS root@$node "kanidmd show-replication-certificate -c /etc/kanidmd/server.toml 2>&1 | grep 'certificate:' | tail -n1 | cut -d '\"' -f2"
      }

      CERT61="$(get_repl_cert 10.100.0.61)"
      CERT62="$(get_repl_cert 10.100.0.62)"
      CERT63="$(get_repl_cert 10.100.0.63)"

      [ -n "$CERT61" ] && [ -n "$CERT62" ] && [ -n "$CERT63" ] || { echo "replication bootstrap failed: could not extract replication certificates"; exit 1; }

      cfg() {
        local self="$1" p1="$2" c1="$3" p2="$4" c2="$5"
        local auto1=""
        if [ "$self" != "10.100.0.61" ] && [ "$p1" = "10.100.0.61" ]; then
          auto1="automatic_refresh = true"
        fi
        cat <<EOF
# Baseline Kanidm config managed by Terraform provisioning.
bindaddress = '[::]:8443'
ldapbindaddress = '[::]:3636'
domain = 'idm.sulibot.com'
origin = 'https://idm.sulibot.com'
db_path = '/var/lib/kanidm/kanidm.db'
role = 'WriteReplica'
tls_chain = '/etc/kanidmd/chain.pem'
tls_key = '/etc/kanidmd/key.pem'

[replication]
origin = 'repl://$self:8444'
bindaddress = '[::]:8444'

[replication."repl://$p1:8444"]
type = 'mutual-pull'
partner_cert = '$c1'
$auto1

[replication."repl://$p2:8444"]
type = 'mutual-pull'
partner_cert = '$c2'
EOF
      }

      apply_cfg() {
        local node="$1" content="$2"
        timeout 60 ssh $SSH_OPTS root@$node "cat > /etc/kanidmd/server.toml <<'EOF'
$content
EOF
chown root:kanidmd /etc/kanidmd/server.toml
chmod 640 /etc/kanidmd/server.toml
systemctl restart kanidmd
systemctl is-active kanidmd
"
      }

      apply_cfg 10.100.0.61 "$(cfg 10.100.0.61 10.100.0.62 "$CERT62" 10.100.0.63 "$CERT63")"
      apply_cfg 10.100.0.62 "$(cfg 10.100.0.62 10.100.0.61 "$CERT61" 10.100.0.63 "$CERT63")"
      apply_cfg 10.100.0.63 "$(cfg 10.100.0.63 10.100.0.61 "$CERT61" 10.100.0.62 "$CERT62")"

      refresh_node() {
        local node="$1"
        timeout 60 ssh $SSH_OPTS root@$node \
          "kanidmd refresh-replication-consumer --config-path /etc/kanidmd/server.toml --i-want-to-refresh-this-servers-database"
      }

      get_domain_uuid() {
        local node="$1"
        timeout 40 ssh $SSH_OPTS root@$node \
          "kanidmd domain show -c /etc/kanidmd/server.toml | grep 'domain_uuid' | head -n1 | sed -E 's/.*domain_uuid[[:space:]]*:[[:space:]]*//'"
      }

      # On fresh independent DBs, each node may have a different domain UUID.
      # Refresh until all nodes converge to a single replicated lineage.
      for attempt in 1 2 3 4; do
        U61="$(get_domain_uuid 10.100.0.61)"
        U62="$(get_domain_uuid 10.100.0.62)"
        U63="$(get_domain_uuid 10.100.0.63)"

        if [ -n "$U61" ] && [ "$U61" = "$U62" ] && [ "$U62" = "$U63" ]; then
          echo "replication domain UUID converged: $U61"
          break
        fi

        echo "replication domain UUID mismatch (attempt $attempt): 61=$U61 62=$U62 63=$U63"
        # node01 is canonical. Never refresh it from an unseeded secondary.
        refresh_node 10.100.0.62
        refresh_node 10.100.0.63
        sleep 5
      done

      U61="$(get_domain_uuid 10.100.0.61)"
      U62="$(get_domain_uuid 10.100.0.62)"
      U63="$(get_domain_uuid 10.100.0.63)"
      [ -n "$U61" ] && [ "$U61" = "$U62" ] && [ "$U62" = "$U63" ] || {
        echo "replication bootstrap failed: domain UUID mismatch persists (61=$U61 62=$U62 63=$U63)"
        exit 1
      }

      for node in 10.100.0.61 10.100.0.62 10.100.0.63; do
        ssh $SSH_OPTS root@$node "tail -n 100 /var/log/kanidmd.log | egrep -q 'UnknownIssuer|UnknownCA|Unable to connect to supplier'" && {
          echo "replication bootstrap failed: TLS trust errors still present on $node"
          exit 1
        } || true
      done
    SHELL
  }
}

resource "null_resource" "kanidm_post_deploy_validation" {
  depends_on = [null_resource.kanidm_tls_sync, null_resource.kanidm_replication_bootstrap]

  triggers = {
    validation_rev = "v1"
    nodes          = join(",", local.kanidm_nodes)
    domain         = local.kanidm_domain
    vip4           = local.kanidm_vip4
    vip6           = local.kanidm_vip6
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      for node in 10.100.0.61 10.100.0.62 10.100.0.63; do
        ssh $SSH_OPTS root@$node "bash -lc '
          for i in \$(seq 1 30); do
              if systemctl is-active --quiet kanidmd caddy bird \
                && curl -sk --max-time 5 https://127.0.0.1:443/ >/dev/null \
                && birdc show protocols | grep -Eq \"^anycast4\\\\s+Static\\\\s+\\\\S+\\\\s+up\" \
                && birdc show protocols | grep -Eq \"^anycast6\\\\s+Static\\\\s+\\\\S+\\\\s+up\"; then
              exit 0
            fi
            sleep 2
          done
          systemctl --no-pager --full status kanidmd caddy bird || true
          birdc show protocols || true
          exit 1
        '"
      done
    SHELL
  }
}

# Create (or reconcile) the Kanidm OAuth2 resource server backing Authentik's
# Kanidm login source (see docs/tickets/kanidm-oidc-source-for-authentik.md).
# Idempotent by design: "create"/"add-redirect-url"/"update-scope-map" are
# allowed to fail with "already exists" on reapply, mirroring the
# best-effort style used throughout this file (e.g. `domain rename ... ||
# true`). The client secret is never written back to this repo automatically
# - it's printed via the apply log so it can be reviewed before being added
# to the 1Password "authentik" item (KANIDM_OIDC_CLIENT_ID/SECRET fields),
# the same way GOOGLE_CLIENT_ID/etc. are set there.
#
# Two things discovered the hard way running this the first time, both
# baked into the script below:
#  1. `kanidm login` requires an actual TTY for the password prompt - no
#     piped-stdin or --password flag exists in this CLI. Driven via `expect`.
#  2. The CLI's default uri (https://idm.sulibot.com, from /etc/kanidm/config)
#     goes through Caddy's load-balancer to any of the 3 replicas. A
#     password just changed via `kanidmd recover-account` on one node isn't
#     necessarily replicated to the others yet, so hitting the VIP can land
#     on a stale replica and fail auth. Talk to 127.0.0.1:8443 on this node
#     directly instead (matches kanidm-anycast-health.sh's own health check).
resource "null_resource" "kanidm_oauth2_authentik_client" {
  depends_on = [null_resource.kanidm_post_deploy_validation]

  triggers = {
    client_rev = "authentik-oauth2-v2"
  }

  provisioner "local-exec" {
    command = <<-SHELL
      set -euo pipefail
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      op whoami >/dev/null 2>&1 || { echo "Skipping Authentik oauth2 client provisioning: 1Password CLI is not authenticated"; exit 0; }

      ADMIN_PASS="$(op item get kanidm --vault Kubernetes --fields password --reveal 2>/dev/null || true)"
      if [ -z "$ADMIN_PASS" ]; then
        echo "Skipping Authentik oauth2 client provisioning: could not read idm_admin password from 1Password item 'kanidm'"
        exit 0
      fi

      ssh $SSH_OPTS root@10.100.0.61 "which expect >/dev/null 2>&1 || apt-get install -y -qq expect"

      ssh $SSH_OPTS root@10.100.0.61 bash -s <<REMOTE
        set -euo pipefail
        export KANIDM_URL="https://127.0.0.1:8443"
        export KANIDM_SKIP_HOSTNAME_VERIFICATION=true
        export KANIDM_ACCEPT_INVALID_CERTS=true

        expect -c "
          set timeout 15
          spawn kanidm login --name idm_admin
          expect \"Password:\"
          send \"$ADMIN_PASS\r\"
          expect eof
        "

        kanidm system oauth2 create authentik 'Authentik SSO' https://auth.sulibot.com --name idm_admin || true
        kanidm system oauth2 add-redirect-url authentik https://auth.sulibot.com/source/oauth/callback/kanidm/ --name idm_admin || true
        kanidm system oauth2 update-scope-map authentik idm_all_persons openid email profile --name idm_admin || true

        echo "=== Kanidm 'authentik' OAuth2 client secret (add to the 1Password 'authentik' item as KANIDM_OIDC_CLIENT_ID=authentik / KANIDM_OIDC_CLIENT_SECRET=<below>) ==="
        kanidm system oauth2 show-basic-secret authentik --name idm_admin
REMOTE
    SHELL
  }
}

EOF2
}
