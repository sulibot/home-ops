include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  openbao_class = local.lxc_catalog.services.openbao
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  openbao_domain = "openbao.sulibot.com"
  openbao_nodes4 = [
    for name in sort(keys(local.openbao_class.instances)) :
    local.openbao_class.instances[name].ipv4
  ]

  # Pin the release artifact and hash together. Do not update only one.
  openbao_version = "2.6.1"
  openbao_sha256  = "07fcc56ab6dc422a6a8b69b1cb6c1d20ada81edb86cfce428e35e9eab4799c9f"

  # GCP KMS is an independent root of trust for unattended startup. These
  # selectors are non-secret; the restricted service-account JSON is read from
  # 1Password only by local-exec.
  openbao_gcp_kms_project_id        = get_env("OPENBAO_GCP_KMS_PROJECT_ID", "sulibot-openbao-kms")
  openbao_gcp_kms_location          = get_env("OPENBAO_GCP_KMS_LOCATION", "global")
  openbao_gcp_kms_key_ring          = get_env("OPENBAO_GCP_KMS_KEY_RING", "openbao")
  openbao_gcp_kms_crypto_key        = get_env("OPENBAO_GCP_KMS_CRYPTO_KEY", "auto-unseal")
  openbao_gcp_kms_onepassword_item  = get_env("OPENBAO_GCP_KMS_1PASSWORD_ITEM", "openbao-gcp-kms")
  openbao_gcp_kms_onepassword_vault = get_env("OPENBAO_GCP_KMS_1PASSWORD_VAULT", "Kubernetes")
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

  openbao_domain      = "${local.openbao_domain}"
  openbao_tls_item    = "sulibot-com-tls"
  openbao_vip4        = "${local.openbao_class.vip.ipv4}"
  openbao_vip6        = "${local.openbao_class.vip.ipv6}"
  openbao_node_ipv4   = ${jsonencode(local.openbao_nodes4)}
  openbao_nodes       = ${jsonencode(local.openbao_class.instances)}
  openbao_gcp_kms_project_id        = "${local.openbao_gcp_kms_project_id}"
  openbao_gcp_kms_location          = "${local.openbao_gcp_kms_location}"
  openbao_gcp_kms_key_ring          = "${local.openbao_gcp_kms_key_ring}"
  openbao_gcp_kms_crypto_key        = "${local.openbao_gcp_kms_crypto_key}"
  openbao_gcp_kms_onepassword_item  = "${local.openbao_gcp_kms_onepassword_item}"
  openbao_gcp_kms_onepassword_vault = "${local.openbao_gcp_kms_onepassword_vault}"

  containers = {
    for name, node in local.openbao_nodes : name => {
      vm_id           = node.vm_id
      node_name       = node.node_name
      hostname        = node.hostname
      description     = "OpenBao Raft member on $${node.node_name}"
      protection      = true
      cpu_cores       = ${local.openbao_class.sizing.cpu_cores}
      memory_mb       = ${local.openbao_class.sizing.memory_mb}
      swap_mb         = ${local.openbao_class.sizing.swap_mb}
      disk_gb         = ${local.openbao_class.sizing.disk_gb}
      bridge          = "${local.openbao_class.network.bridge}"
      vlan_id         = ${local.openbao_class.network.vlan_id == null ? "null" : local.openbao_class.network.vlan_id}
      ipv4_address    = node.ipv4_cidr
      ipv4_gateway    = "${local.openbao_class.network.ipv4_gateway}"
      ipv6_address    = node.ipv6_cidr
      ipv6_gateway    = "${local.openbao_class.network.ipv6_gateway}"
      ssh_public_keys = [local.ssh_public_key]
      tags            = ["openbao", "raft", "secrets", "lxc", "trixie"]
      mount_points = [
        {
          volume = "${local.openbao_class.storage.vm_datastore}"
          size   = "${local.openbao_class.sizing.disk_gb}G"
          path   = "/opt/openbao/data"
          backup = true
        }
      ]
    }
  }

  openbao_provision_commands = [
    "install -m 0750 /dev/null /usr/local/sbin/openbao-provision",
    "printf '%s' '${filebase64("${get_terragrunt_dir()}/provision.sh")}' | base64 --decode > /usr/local/sbin/openbao-provision",
    "OPENBAO_VERSION='${local.openbao_version}' OPENBAO_SHA256='${local.openbao_sha256}' OPENBAO_TENANT='${local.openbao_class.tenant_id}' OPENBAO_DOMAIN='${local.openbao_domain}' OPENBAO_BASE_DOMAIN='${local.lxc_catalog.site.domain}' OPENBAO_VIP4='${local.openbao_class.vip.ipv4}' OPENBAO_VIP6='${local.openbao_class.vip.ipv6}' OPENBAO_PEERS4='${join(" ", local.openbao_nodes4)}' OPENBAO_BGP_PEER4='${local.openbao_class.network.ipv4_gateway}' OPENBAO_BGP_PEER6='${local.openbao_class.network.ipv6_gateway}' OPENBAO_BGP_PEER_AS='4200001000' OPENBAO_SEAL_TYPE='gcpckms' OPENBAO_GCP_KMS_PROJECT_ID='${local.openbao_gcp_kms_project_id}' OPENBAO_GCP_KMS_LOCATION='${local.openbao_gcp_kms_location}' OPENBAO_GCP_KMS_KEY_RING='${local.openbao_gcp_kms_key_ring}' OPENBAO_GCP_KMS_CRYPTO_KEY='${local.openbao_gcp_kms_crypto_key}' /usr/local/sbin/openbao-provision",
  ]
}

resource "null_resource" "openbao_kms_preflight" {
  triggers = {
    project_id = local.openbao_gcp_kms_project_id
    location   = local.openbao_gcp_kms_location
    key_ring   = local.openbao_gcp_kms_key_ring
    crypto_key = local.openbao_gcp_kms_crypto_key
    op_item    = local.openbao_gcp_kms_onepassword_item
    op_vault   = local.openbao_gcp_kms_onepassword_vault
    revision   = "gcp-kms-v1"
  }

  provisioner "local-exec" {
    command = "${get_terragrunt_dir()}/sync-gcp-kms-credentials.sh check"
    environment = {
      OPENBAO_GCP_KMS_PROJECT_ID          = local.openbao_gcp_kms_project_id
      OPENBAO_GCP_KMS_LOCATION            = local.openbao_gcp_kms_location
      OPENBAO_GCP_KMS_KEY_RING            = local.openbao_gcp_kms_key_ring
      OPENBAO_GCP_KMS_CRYPTO_KEY          = local.openbao_gcp_kms_crypto_key
      OPENBAO_GCP_KMS_1PASSWORD_ITEM      = local.openbao_gcp_kms_onepassword_item
      OPENBAO_GCP_KMS_1PASSWORD_VAULT     = local.openbao_gcp_kms_onepassword_vault
    }
  }
}

module "openbao_lxc" {
  source = "../../../modules/proxmox_lxc_role"
  depends_on = [null_resource.openbao_kms_preflight]

  proxmox = {
    datastore_id = "${local.proxmox_infra.storage.datastore_id}"
    vm_datastore = "${local.openbao_class.storage.vm_datastore}"
  }

  template = {
    download  = false
    url       = ""
    file_name = ""
    file_id   = "${local.lxc_catalog.lxc_defaults.template_file_id}"
  }

  dns_servers = [
    "${local.network_infra.dns_servers.ipv4}",
    "${local.network_infra.dns_servers.ipv6}",
  ]

  containers = local.containers

  provision = {
    enabled            = true
    ssh_user           = "root"
    ssh_private_key    = file(pathexpand("~/.ssh/id_ed25519"))
    ssh_timeout        = "10m"
    wait_for_cloudinit = false
    commands           = local.openbao_provision_commands
  }
}

# Stream the KMS principal to root-owned systemd environment files, then start
# each node and verify its seal type. Values are resolved inside the script and
# never become Terraform inputs, outputs, or state attributes.
resource "null_resource" "openbao_kms_credentials_sync" {
  depends_on = [module.openbao_lxc]

  triggers = {
    project_id = local.openbao_gcp_kms_project_id
    location   = local.openbao_gcp_kms_location
    key_ring   = local.openbao_gcp_kms_key_ring
    crypto_key = local.openbao_gcp_kms_crypto_key
    nodes      = join(",", local.openbao_node_ipv4)
    op_item    = local.openbao_gcp_kms_onepassword_item
    op_vault   = local.openbao_gcp_kms_onepassword_vault
    sync_rev   = "gcp-kms-v1"
  }

  provisioner "local-exec" {
    command = "${get_terragrunt_dir()}/sync-gcp-kms-credentials.sh sync"
    environment = {
      OPENBAO_GCP_KMS_PROJECT_ID          = local.openbao_gcp_kms_project_id
      OPENBAO_GCP_KMS_LOCATION            = local.openbao_gcp_kms_location
      OPENBAO_GCP_KMS_KEY_RING            = local.openbao_gcp_kms_key_ring
      OPENBAO_GCP_KMS_CRYPTO_KEY          = local.openbao_gcp_kms_crypto_key
      OPENBAO_GCP_KMS_1PASSWORD_ITEM      = local.openbao_gcp_kms_onepassword_item
      OPENBAO_GCP_KMS_1PASSWORD_VAULT     = local.openbao_gcp_kms_onepassword_vault
      OPENBAO_DOMAIN                      = local.openbao_domain
      OPENBAO_NODES                       = join(" ", local.openbao_node_ipv4)
    }
  }
}

# Install the existing public wildcard certificate without placing its private
# key in Terraform state. OpenBao reloads listener certificates on SIGHUP, so
# this does not restart or seal initialized members.
resource "null_resource" "openbao_tls_sync" {
  depends_on = [null_resource.openbao_kms_credentials_sync]

  triggers = {
    tls_item = local.openbao_tls_item
    nodes    = join(",", local.openbao_node_ipv4)
    sync_rev = "wildcard-sighup-v2"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-SHELL
      set -euo pipefail
      CERT=""
      KEY=""
      SOURCE=""
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

      decode_if_base64() {
        local input="$1"
        if printf "%s\n" "$input" | grep -q "BEGIN CERTIFICATE\\|BEGIN .*PRIVATE KEY"; then
          printf "%s\n" "$input"
        else
          printf "%s" "$input" | base64 --decode 2>/dev/null || printf "%s\n" "$input"
        fi
      }

      cert_is_usable() {
        local cert="$1"
        local key="$2"
        local cert_pub key_pub cert_text
        cert_pub="$(printf "%s\n" "$cert" | openssl x509 -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}' || true)"
        key_pub="$(printf "%s\n" "$key" | openssl pkey -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}' || true)"
        cert_text="$(printf "%s\n" "$cert" | openssl x509 -noout -text 2>/dev/null || true)"
        test -n "$cert_pub" &&
          test "$cert_pub" = "$key_pub" &&
          printf "%s\n" "$cert" | openssl x509 -checkend 604800 -noout >/dev/null 2>&1 &&
          [[ "$cert_text" == *'DNS:*.sulibot.com'* ||
            "$cert_text" == *'DNS:openbao.sulibot.com'* ]]
      }

      if kubectl -n network get secret sulibot-com-tls >/dev/null 2>&1; then
        CERT="$(kubectl -n network get secret sulibot-com-tls -o jsonpath='{.data.tls\.crt}' | base64 --decode)"
        KEY="$(kubectl -n network get secret sulibot-com-tls -o jsonpath='{.data.tls\.key}' | base64 --decode)"
        if cert_is_usable "$CERT" "$KEY"; then
          SOURCE="kubernetes-secret"
        else
          CERT=""
          KEY=""
        fi
      fi

      if [[ -z "$CERT" || -z "$KEY" ]]; then
        CERT="$(op item get "$${local.openbao_tls_item}" --vault Kubernetes --fields label=crt 2>/dev/null || true)"
        KEY="$(op item get "$${local.openbao_tls_item}" --vault Kubernetes --fields label=key 2>/dev/null || true)"
        if [[ -z "$CERT" || -z "$KEY" ]]; then
          CERT="$(op item get "$${local.openbao_tls_item}" --vault Kubernetes --fields label=tls.crt 2>/dev/null || true)"
          KEY="$(op item get "$${local.openbao_tls_item}" --vault Kubernetes --fields label=tls.key 2>/dev/null || true)"
        fi
        CERT="$(decode_if_base64 "$CERT")"
        KEY="$(decode_if_base64 "$KEY")"
        if cert_is_usable "$CERT" "$KEY"; then
          SOURCE="1password"
        else
          CERT=""
          KEY=""
        fi
      fi

      if [[ -z "$CERT" || -z "$KEY" ]]; then
        for node in $${join(" ", local.openbao_node_ipv4)}; do
          CERT="$(ssh $SSH_OPTS root@$node 'cat /etc/openbao/tls/tls.crt 2>/dev/null' || true)"
          KEY="$(ssh $SSH_OPTS root@$node 'cat /etc/openbao/tls/tls.key 2>/dev/null' || true)"
          if cert_is_usable "$CERT" "$KEY"; then
            SOURCE="existing-node:$node"
            break
          fi
          CERT=""
          KEY=""
        done
      fi

      if [[ -z "$CERT" || -z "$KEY" ]]; then
        echo "no valid public certificate found in Kubernetes, 1Password, or an existing OpenBao node" >&2
        exit 1
      fi

      echo "installing OpenBao listener certificate from $SOURCE"
      for node in $${join(" ", local.openbao_node_ipv4)}; do
        ssh $SSH_OPTS root@$node "install -d -m 0750 -o openbao -g openbao /etc/openbao/tls"
        printf "%s\n" "$CERT" |
          ssh $SSH_OPTS root@$node "install -m 0644 -o root -g openbao /dev/stdin /etc/openbao/tls/tls.crt"
        printf "%s\n" "$KEY" |
          ssh $SSH_OPTS root@$node "install -m 0640 -o root -g openbao /dev/stdin /etc/openbao/tls/tls.key"
        ssh $SSH_OPTS root@$node "systemctl reload openbao"
      done
    SHELL
  }
}

resource "null_resource" "openbao_post_deploy_validation" {
  depends_on = [null_resource.openbao_tls_sync]

  triggers = {
    nodes      = join(",", local.openbao_node_ipv4)
    domain     = local.openbao_domain
    validation = "v2"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-SHELL
      set -euo pipefail
      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
      health_file="$(mktemp)"
      trap 'rm -f "$health_file"' EXIT

      for node in $OPENBAO_NODES; do
        ssh $SSH_OPTS root@$node "bash -lc '
          set -euo pipefail
          systemctl is-active --quiet openbao bird openbao-leader-route-health.timer
          birdc configure check

          for attempt in \$(seq 1 30); do
            if birdc show protocols all upstream | grep -q \"BGP state:.*Established\"; then
              exit 0
            fi
            sleep 2
          done

          birdc show protocols all upstream || true
          exit 1
        '"

        code="$(curl --silent --output "$health_file" --write-out '%%%{http_code}' \
          --resolve "$OPENBAO_DOMAIN:443:$node" \
          "https://$OPENBAO_DOMAIN/v1/sys/health")"
        case "$code" in
          200|429|501|503) ;;
          *)
            echo "unexpected OpenBao health response from $node: HTTP $code" >&2
            exit 1
            ;;
        esac
        if [[ "$(jq -r '.initialized // false' "$health_file")" == "true" ]] &&
           [[ "$(jq -r '.sealed // true' "$health_file")" != "false" ]]; then
          echo "initialized OpenBao node $node did not auto-unseal" >&2
          exit 1
        fi

        seal_type="$(curl --silent \
          --resolve "$OPENBAO_DOMAIN:443:$node" \
          "https://$OPENBAO_DOMAIN/v1/sys/seal-status" |
          jq -r '.type // empty')"
        if [[ "$seal_type" != "gcpckms" ]]; then
          echo "unexpected OpenBao seal type on $node: $seal_type" >&2
          exit 1
        fi
      done
    SHELL
    environment = {
      OPENBAO_DOMAIN = local.openbao_domain
      OPENBAO_NODES  = join(" ", local.openbao_node_ipv4)
    }
  }
}

resource "null_resource" "openbao_backup_sync" {
  depends_on = [null_resource.openbao_post_deploy_validation]

  triggers = {
    nodes                  = join(",", local.openbao_node_ipv4)
    backup_script_sha      = "${filesha256("${get_terragrunt_dir()}/openbao-backup.sh")}"
    sync_script_sha        = "${filesha256("${get_terragrunt_dir()}/sync-backup-credentials.sh")}"
    integrations_sha       = "${filesha256("${get_terragrunt_dir()}/configure-integrations.sh")}"
    snapshot_policy_sha    = "${filesha256("${get_terragrunt_dir()}/policies/openbao-snapshot.hcl")}"
  }

  provisioner "local-exec" {
    command = "${get_terragrunt_dir()}/configure-integrations.sh && ${get_terragrunt_dir()}/sync-backup-credentials.sh"
    environment = {
      OPENBAO_NODES = join(" ", local.openbao_node_ipv4)
    }
  }
}

output "openbao_containers" {
  value = module.openbao_lxc.containers
}

output "openbao_endpoint" {
  value = {
    url  = "https://$${local.openbao_domain}"
    vip4 = local.openbao_vip4
    vip6 = local.openbao_vip6
  }
}

output "initialization_next_steps" {
  value = <<-EOT
    Terraform intentionally leaves recovery material outside state and logs.

    1. Apply RouterOS DNS and this OpenBao unit.
    2. Confirm the GCP KMS key has deletion prevention and one active version.
       Rotate the restricted service-account credential on a scheduled runbook;
       do not rotate the KMS key merely on a calendar.
    3. On a secure operator shell:
       export VAULT_ADDR=https://openbao01.sulibot.com
       bao operator init -recovery-shares=5 -recovery-threshold=3
    4. Store each recovery share as a separate 1Password item. Keep an
       independently encrypted offline backup; recovery keys cannot replace a
       deleted or unavailable KMS key.
    5. The members join and unseal automatically. Verify:
       bao operator raft list-peers
       bao status

    After election, only the active leader advertises:
      ${local.openbao_class.vip.ipv4}/32
      ${local.openbao_class.vip.ipv6}/128
  EOT
}
EOF2
}
