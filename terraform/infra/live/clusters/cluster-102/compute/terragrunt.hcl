include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled           = try(local.cluster_config.enabled, true)
  cnpg_new_db_mode          = trimspace(lower(get_env("CNPG_NEW_DB", "false"))) == "true"
  cnpg_restore_mode         = trimspace(upper(get_env("CNPG_RESTORE_MODE", local.cnpg_new_db_mode ? "NEW_DB" : "RESTORE_REQUIRED")))
  cnpg_backup_max_age_hours = trimspace(get_env("CNPG_BACKUP_MAX_AGE_HOURS", "36"))
  cnpg_preflight_skip       = trimspace(lower(get_env("CNPG_PREFLIGHT_SKIP", "false"))) == "true"
  cluster_kubeconfig        = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"

  # Shared context locals
  proxmox_infra     = local.context.proxmox_infra
  network_infra     = local.context.network_infra
  ipv6_prefixes     = local.context.ipv6_prefixes
  versions          = local.context.versions
  artifact_registry = local.context.artifacts_registry_catalog

  control_plane_defaults = local.context.vm_sizing.control_plane
  worker_defaults        = local.context.vm_sizing.worker

  # Generate control plane nodes
  control_planes = [for i in range(local.cluster_config.controlplanes) : {
    name          = format("%scp%02d", local.cluster_config.cluster_name, i + 1)
    vm_id         = tonumber(format("%d0%d", local.tenant_id, i + local.network_infra.addressing.controlplane_offset))
    ip_suffix     = i + local.network_infra.addressing.controlplane_offset
    control_plane = true
    cpu_cores     = local.control_plane_defaults.cpu_cores
    memory_mb     = local.control_plane_defaults.memory_mb
    disk_gb       = local.control_plane_defaults.disk_gb
  }]

  # Generate worker nodes
  workers = [for i in range(local.cluster_config.workers) : {
    name          = format("%swk%02d", local.cluster_config.cluster_name, i + 1)
    vm_id         = tonumber(format("%d0%d", local.tenant_id, i + local.network_infra.addressing.worker_offset))
    ip_suffix     = i + local.network_infra.addressing.worker_offset
    control_plane = false
    cpu_cores     = local.worker_defaults.cpu_cores
    memory_mb     = local.worker_defaults.memory_mb
    disk_gb       = local.worker_defaults.disk_gb
  }]

  all_nodes = concat(local.control_planes, local.workers)
  nodes_map = { for node in local.all_nodes : node.name => node }

  final_nodes = [
    for name, config in merge(local.nodes_map, local.cluster_config.node_overrides) :
    merge(lookup(local.nodes_map, name, {}), config)
  ]

  # Read credentials from centralized common file
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
}

skip = !local.cluster_enabled

terraform {
  source = "../../../../modules/cluster_core"

  before_hook "validate_artifact_registry_catalog" {
    commands = ["apply", "plan"]
    execute = ["bash", "-c", <<-EOT
      set -euo pipefail
      if [ ! -f "${local.context.artifacts_registry_catalog_path}" ]; then
        echo "ERROR: Artifact registry catalog not found: ${local.context.artifacts_registry_catalog_path}"
        echo "Run: cd ${get_repo_root()}/terraform/infra/live/artifacts/registry && terragrunt apply"
        exit 1
      fi
      echo "✓ Artifact registry catalog found"
    EOT
    ]
  }

  before_hook "cnpg_restore_preflight" {
    commands = ["apply", "plan"]
    execute = ["bash", "-c", <<-EOT
      set -euo pipefail
      if [ "${local.cnpg_preflight_skip}" = "true" ]; then
        echo "⚠ CNPG preflight skipped because CNPG_PREFLIGHT_SKIP=true"
        exit 0
      fi

      MODE="${local.cnpg_restore_mode}"
      MAX_AGE_HOURS="${local.cnpg_backup_max_age_hours}"
      CLUSTER_NAME="postgres-vectorchord"
      CLUSTER_NS="default"
      KUBECONFIG_PATH="${local.cluster_kubeconfig}"

      if ! printf '%s' "$MAX_AGE_HOURS" | grep -Eq '^[0-9]+$'; then
        echo "ERROR: CNPG_BACKUP_MAX_AGE_HOURS must be a positive integer, got '$MAX_AGE_HOURS'" >&2
        exit 1
      fi
      if [ "$MAX_AGE_HOURS" -le 0 ]; then
        echo "ERROR: CNPG_BACKUP_MAX_AGE_HOURS must be > 0" >&2
        exit 1
      fi

      if [ "$MODE" = "NEW_DB" ]; then
        echo "✓ CNPG preflight skipped in NEW_DB mode"
        exit 0
      fi

      if [ ! -f "$KUBECONFIG_PATH" ]; then
        echo "ERROR: kubeconfig not found at $KUBECONFIG_PATH (required in RESTORE_REQUIRED mode)" >&2
        exit 1
      fi
      if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required for CNPG preflight" >&2
        exit 1
      fi
      if ! kubectl --kubeconfig="$KUBECONFIG_PATH" version --request-timeout=10s >/dev/null 2>&1; then
        echo "ERROR: cannot reach Kubernetes API using $KUBECONFIG_PATH in RESTORE_REQUIRED mode" >&2
        exit 1
      fi

      THRESHOLD_SECONDS=$((MAX_AGE_HOURS * 3600))

      plugin_age="$(
        kubectl --kubeconfig="$KUBECONFIG_PATH" -n "$CLUSTER_NS" get backup.postgresql.cnpg.io -o json 2>/dev/null | \
          jq -r --arg cluster "$CLUSTER_NAME" '
            [ .items[]?
              | select(
                  ((.metadata.labels["cnpg.io/cluster"] // "") == $cluster)
                  or ((.spec.cluster.name // "") == $cluster)
                )
              | select((.spec.method // "") == "plugin")
              | select((.status.phase // "" | ascii_downcase) == "completed")
              | (now - ((.status.stoppedAt // .status.completedAt // .metadata.creationTimestamp) | fromdateiso8601))
            ]
            | if length == 0 then "" else (min | floor | tostring) end'
      )"

      snapshot_age="$(
        kubectl --kubeconfig="$KUBECONFIG_PATH" -n "$CLUSTER_NS" get volumesnapshots.snapshot.storage.k8s.io -l "cnpg.io/cluster=$CLUSTER_NAME" -o json 2>/dev/null | \
          jq -r '
            [ .items[]?
              | select((.status.readyToUse // false) == true)
              | (now - (.metadata.creationTimestamp | fromdateiso8601))
            ]
            | if length == 0 then "" else (min | floor | tostring) end'
      )"

      plugin_fresh="false"
      snapshot_fresh="false"
      if [ -n "$plugin_age" ] && [ "$plugin_age" -le "$THRESHOLD_SECONDS" ]; then
        plugin_fresh="true"
      fi
      if [ -n "$snapshot_age" ] && [ "$snapshot_age" -le "$THRESHOLD_SECONDS" ]; then
        snapshot_fresh="true"
      fi

      if [ "$plugin_fresh" = "true" ] || [ "$snapshot_fresh" = "true" ]; then
        echo "✓ CNPG preflight passed (fresh restore source found)"
        exit 0
      fi

      echo "ERROR: no fresh CNPG restore source found and CNPG_RESTORE_MODE=RESTORE_REQUIRED" >&2
      echo "       refresh backup/snapshot or set CNPG_RESTORE_MODE=NEW_DB intentionally" >&2
      exit 1
    EOT
    ]
  }

  # Automatically generate talenv.yaml after successful apply
  after_hook "generate_talenv" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "cd ${get_repo_root()} && mkdir -p talos/clusters/cluster-${local.tenant_id} && cd ${get_terragrunt_dir()} && terragrunt output -raw talenv_yaml 2>/dev/null | yq eval '... style=\"\"' - > ${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/talenv.yaml"]
    run_on_error = false
  }
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  # Use root credentials instead of API token for hardware mapping support
  # Hardware mappings require root PAM authentication due to IOMMU interactions
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF2
}

generate "routeros_provider" {
  path      = "routeros_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF2
    provider "routeros" {
      hosturl  = data.sops_file.proxmox.data["routeros_hosturl"]
      username = data.sops_file.proxmox.data["routeros_username"]
      password = data.sops_file.proxmox.data["routeros_password"]
      insecure = true
    }
  EOF2
}

generate "dns" {
  path      = "dns_nodes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF2
    # Loopback records — {name}.${local.network_infra.base_domain} → loopback IPs (BGP-routed)
    resource "routeros_ip_dns_record" "node_loopback_aaaa" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}.${local.network_infra.base_domain}"
      type    = "AAAA"
      address = "fd00:${local.tenant_id}:fe::$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.tenant_id} compute"
    }

    resource "routeros_ip_dns_record" "node_loopback_a" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}.${local.network_infra.base_domain}"
      type    = "A"
      address = "10.${local.tenant_id}.254.$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.tenant_id} compute"
    }

    # Interface records — {name}-if.${local.network_infra.base_domain} → public VLAN IPs
    resource "routeros_ip_dns_record" "node_if_aaaa" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}-if.${local.network_infra.base_domain}"
      type    = "AAAA"
      address = "$${var.ip_config.public.ipv6_prefix}$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.tenant_id} compute"
    }

    resource "routeros_ip_dns_record" "node_if_a" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}-if.${local.network_infra.base_domain}"
      type    = "A"
      address = "$${var.ip_config.public.ipv4_prefix}$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.tenant_id} compute"
    }
  EOF2
}

inputs = {
  cluster_id = local.tenant_id
  nodes      = local.final_nodes

  # Shared artifact handoff (no external dependency traversal during cluster run-all)
  talos_image_file_id = lookup(
    local.artifact_registry.talos_image_file_ids,
    local.proxmox_infra.proxmox_nodes[0],
    "resources:iso/mock-talos-image.iso"
  )

  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version

  ip_config = {
    mesh = {
      ipv6_prefix = "fc00:${local.tenant_id}::"
      ipv4_prefix = "10.10.${local.tenant_id}."
    }
    public = {
      ipv6_prefix      = "fd00:${local.tenant_id}::"
      ipv4_prefix      = "10.${local.tenant_id}.0."
      ipv6_gateway     = "fd00:${local.tenant_id}::fffe"
      ipv4_gateway     = "10.${local.tenant_id}.0.254"
      gua_ipv6_prefix  = try(local.ipv6_prefixes.delegated_prefixes["vnet${local.tenant_id}"], "")
      gua_ipv6_gateway = try(local.ipv6_prefixes.delegated_gateways["vnet${local.tenant_id}"], "")
    }
    dns_servers = [
      local.network_infra.dns_servers.ipv6,
      local.network_infra.dns_servers.ipv4,
    ]
  }

  network = local.cluster_config.network

  proxmox = {
    datastore_id = local.proxmox_infra.storage.datastore_id
    vm_datastore = local.proxmox_infra.storage.vm_datastore
    node_primary = local.proxmox_infra.proxmox_primary_node
    nodes        = local.proxmox_infra.proxmox_nodes
  }

  proxmox_ssh_hostnames = local.proxmox_infra.proxmox_hostnames

  vm_defaults = {
    cpu_cores = local.control_plane_defaults.cpu_cores
    memory_mb = local.control_plane_defaults.memory_mb
    disk_gb   = local.worker_defaults.disk_gb
  }
}
