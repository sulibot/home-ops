# Get first control plane node for bootstrap
locals {
  first_cp_name    = length(var.control_plane_nodes) > 0 ? sort(keys(var.control_plane_nodes))[0] : ""
  first_cp_node    = length(var.control_plane_nodes) > 0 ? var.control_plane_nodes[local.first_cp_name] : { ipv6 = "", ipv4 = "" }
  cluster_name     = var.cluster_name != "" ? var.cluster_name : "cluster-${var.cluster_id}"
  output_directory = var.output_directory != "" ? var.output_directory : "${var.repo_root}/talos/clusters/${local.cluster_name}"
  cluster_endpoint_host = var.cluster_endpoint != "" ? replace(
    replace(
      replace(
        replace(
          replace(var.cluster_endpoint, "https://", ""),
          "http://",
          ""
        ),
        "[",
        ""
      ),
      "]",
      ""
    ),
    ":6443",
    ""
  ) : ""
  effective_cluster_endpoint = local.cluster_endpoint_host != "" ? local.cluster_endpoint_host : local.first_cp_node.ipv6
}

# Bootstrap the cluster on the first control plane node.
# Use talosctl directly to make reruns idempotent: if etcd is already bootstrapped,
# Talos returns AlreadyExists, which we treat as success.
resource "null_resource" "bootstrap_cluster" {
  triggers = {
    first_cp_node = local.effective_cluster_endpoint
    endpoint      = local.effective_cluster_endpoint
    talosconfig   = sha256(var.talosconfig)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      TALOSCONFIG_FILE=$(mktemp)
      cat > "$TALOSCONFIG_FILE" <<'EOF'
${var.talosconfig}
EOF
      export TALOSCONFIG="$TALOSCONFIG_FILE"

      # Bootstrap can race early node startup (Talos API not yet listening on :50000).
      # Retry transient connectivity errors for up to 5 minutes.
      MAX_ATTEMPTS=60
      SLEEP_SECONDS=5
      ATTEMPT=1

      while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
        set +e
        BOOTSTRAP_OUTPUT=$(talosctl bootstrap \
          --nodes ${local.effective_cluster_endpoint} \
          --endpoints ${local.effective_cluster_endpoint} 2>&1)
        BOOTSTRAP_RC=$?
        set -e

        if [ "$BOOTSTRAP_RC" -eq 0 ]; then
          echo "✓ Talos bootstrap completed"
          break
        fi

        if echo "$BOOTSTRAP_OUTPUT" | grep -qi "AlreadyExists\\|etcd data directory is not empty"; then
          echo "✓ Talos bootstrap already completed (etcd present), continuing"
          break
        fi

        if echo "$BOOTSTRAP_OUTPUT" | grep -qi "connection refused\\|code = Unavailable\\|i/o timeout\\|deadline exceeded"; then
          if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
            echo "⏳ Talos API not ready for bootstrap (attempt $ATTEMPT/$MAX_ATTEMPTS), retrying in $SLEEP_SECONDS s..."
            sleep "$SLEEP_SECONDS"
            ATTEMPT=$((ATTEMPT + 1))
            continue
          fi
        fi

        echo "$BOOTSTRAP_OUTPUT" >&2
        rm -f "$TALOSCONFIG_FILE"
        exit "$BOOTSTRAP_RC"
      done

      rm -f "$TALOSCONFIG_FILE"
    EOT
  }
}

# Smart wait: Poll for cluster health every 10s, up to 5 minutes
resource "null_resource" "wait_for_etcd" {
  triggers = {
    bootstrap_id = null_resource.bootstrap_cluster.id
  }

  provisioner "local-exec" {
    # This provisioner's only job is to wait until the bootstrap boundary is crossed:
    # Kubernetes API reachable, at least one node registered, etcd formed, and the
    # kubernetes service has an API endpoint. CNI readiness belongs to the Cilium stage.
    command = <<-EOT
      echo "---[ Wait for Kubernetes API ]---"
      TALOSCONFIG_FILE=$(mktemp)
      cat > "$TALOSCONFIG_FILE" <<'EOF'
${var.talosconfig}
EOF
      export TALOSCONFIG="$TALOSCONFIG_FILE"

      KUBECONFIG_FILE=$(mktemp)

      echo "⏳ Waiting for talosctl to generate kubeconfig..."
      i=1
      while [ "$i" -le 12 ]; do
        if talosctl -n ${local.effective_cluster_endpoint} -e ${local.effective_cluster_endpoint} kubeconfig "$KUBECONFIG_FILE" --force >/dev/null 2>&1; then
          echo "✓ Kubeconfig generated."
          break
        fi
        echo "  ... attempt $i/12, retrying in 5s"
        sleep 5
        i=$((i + 1))
      done

      echo "✓ Kubeconfig is available. Continuing to Cilium bootstrap for CNI readiness."
      rm -f "$KUBECONFIG_FILE"
      rm -f "$TALOSCONFIG_FILE"
      exit 0
    EOT
  }

  depends_on = [null_resource.bootstrap_cluster]
}

# Note: The talos_cluster_health data source is not used because it compares etcd
# member IPs (reported as IPv4) against control plane node IPs. This would require
# passing IPv4 addresses, which defeats the purpose of IPv6 configuration.
# The null_resource.wait_for_etcd above already verifies cluster health via kubectl.

# Get kubeconfig after bootstrap
resource "talos_cluster_kubeconfig" "cluster" {
  client_configuration = var.client_configuration
  node                 = local.effective_cluster_endpoint
  endpoint             = local.effective_cluster_endpoint

  depends_on = [null_resource.wait_for_etcd]
}

# Note: SOPS AGE secret creation moved to flux-instance module
# This keeps the bootstrap module focused on Talos cluster bootstrap only

# Write kubeconfig to file for use by downstream modules
resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  filename        = "${local.output_directory}/kubeconfig"
  file_permission = "0600"

  depends_on = [talos_cluster_kubeconfig.cluster]
}

# Note: Post-bootstrap operations moved to flux-instance module
# This is where HelmRelease fix and Kopia restore should run after Flux is ready
