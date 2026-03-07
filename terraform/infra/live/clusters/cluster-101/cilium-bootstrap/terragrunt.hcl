include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id

  cluster_enabled        = try(local.cluster_config.enabled, true)
  bootstrap_mode         = trimspace(lower(get_env("TALOS_BOOTSTRAP_MODE", "false"))) == "true"
  cluster_kubeconfig     = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"
  has_cluster_kubeconfig = fileexists(local.cluster_kubeconfig)
  kubernetes_api_ready = local.has_cluster_kubeconfig && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.cluster_kubeconfig}' timeout 8 kubectl get --raw=/readyz >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
  cilium_daemonset_exists = local.kubernetes_api_ready && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.cluster_kubeconfig}' timeout 8 kubectl -n kube-system get daemonset cilium >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
  cluster_uid = local.kubernetes_api_ready ? trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.cluster_kubeconfig}' timeout 8 kubectl get namespace kube-system -o jsonpath='{.metadata.uid}' 2>/dev/null || true"
  )) : ""
}

# Bootstrap unit runs for first build, and can be forced in explicit bootstrap mode.
skip = !local.cluster_enabled || (!local.bootstrap_mode && local.kubernetes_api_ready && local.cilium_daemonset_exists)

dependencies {
  paths = ["../bootstrap"]
}

dependency "bootstrap" {
  config_path = "../bootstrap"

  mock_outputs = {
    kubeconfig_path = "/tmp/mock-kubeconfig"
    cluster_ready   = true
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/cilium_bootstrap"

  before_hook "refresh_kubeconfig" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "set -euo pipefail; REPO_ROOT='${get_repo_root()}'; TENANT_ID='${local.tenant_id}'; CLUSTER_DIR=\"$REPO_ROOT/talos/clusters/cluster-$TENANT_ID\"; TALOSCONFIG_SRC=\"$CLUSTER_DIR/talosconfig\"; KUBECONFIG_REPO=\"$CLUSTER_DIR/kubeconfig\"; KUBECONFIG_USER=\"$HOME/.kube/config\"; TALOSCONFIG_USER=\"$HOME/.talos/config\"; BOOTSTRAP_NODE=\"10.$TENANT_ID.0.11\"; if [ -f \"$TALOSCONFIG_SRC\" ]; then mkdir -p \"$HOME/.kube\" \"$HOME/.talos\"; cp \"$TALOSCONFIG_SRC\" \"$TALOSCONFIG_USER\"; chmod 600 \"$TALOSCONFIG_USER\" || true; talosctl --talosconfig \"$TALOSCONFIG_SRC\" --nodes \"$BOOTSTRAP_NODE\" --endpoints \"$BOOTSTRAP_NODE\" kubeconfig \"$KUBECONFIG_REPO\" --merge=false --force >/dev/null 2>&1 || true; talosctl --talosconfig \"$TALOSCONFIG_SRC\" --nodes \"$BOOTSTRAP_NODE\" --endpoints \"$BOOTSTRAP_NODE\" kubeconfig \"$KUBECONFIG_USER\" --force >/dev/null 2>&1 || true; fi"
    ]
  }
}

inputs = {
  kubeconfig_path         = local.has_cluster_kubeconfig ? local.cluster_kubeconfig : dependency.bootstrap.outputs.kubeconfig_path
  cilium_daemonset_exists = local.cilium_daemonset_exists
  cluster_uid             = local.cluster_uid
  repo_root               = get_repo_root()
}
