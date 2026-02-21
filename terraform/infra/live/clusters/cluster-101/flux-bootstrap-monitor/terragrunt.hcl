include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../flux-instance"]
}

dependency "bootstrap" {
  config_path = "../bootstrap"

  mock_outputs = {
    kubeconfig_path = "/tmp/mock-kubeconfig"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "flux_instance" {
  config_path = "../flux-instance"

  mock_outputs = {
    flux_ready = true
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/flux_bootstrap_monitor"
}

inputs = {
  kubeconfig_path = dependency.bootstrap.outputs.kubeconfig_path

  # Set to false to keep bootstrap intervals running (manual control)
  auto_switch_intervals = true

  # Bootstrap override intervals — written to cluster-settings ConfigMap immediately.
  # These override each app's ${VAR:=production_default} during bootstrap.
  # After bootstrap completes the ConfigMap is deleted; apps revert to their own defaults.
  # Only set these if you need values different from the module defaults.
  # tier0_bootstrap_interval        = "30s"   # default
  # tier0_bootstrap_retry_interval  = "10s"   # default
  # tier1_bootstrap_interval        = "1m"    # default
  # tier1_bootstrap_retry_interval  = "20s"   # default
  # tier2_bootstrap_interval        = "2m"    # default
  # tier2_bootstrap_retry_interval  = "30s"   # default
}
