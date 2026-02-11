# Get first control plane node for bootstrap
locals {
  first_cp_name = length(var.control_plane_nodes) > 0 ? sort(keys(var.control_plane_nodes))[0] : ""
  first_cp_node = length(var.control_plane_nodes) > 0 ? var.control_plane_nodes[local.first_cp_name] : { ipv6 = "", ipv4 = "" }
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

# Bootstrap the cluster on the first control plane node
resource "talos_machine_bootstrap" "cluster" {
  client_configuration = var.client_configuration
  node                 = local.first_cp_node.ipv6
  endpoint             = local.first_cp_node.ipv6
}

# Smart wait: Poll for cluster health every 10s, up to 5 minutes
resource "null_resource" "wait_for_etcd" {
  triggers = {
    bootstrap_id = talos_machine_bootstrap.cluster.id
  }

  provisioner "local-exec" {
    # This provisioner's only job is to wait until the Kubernetes API is responsive.
    # All other operational logic (CoreDNS patching, HelmRelease fixing, etc.)
    # has been moved to a post-provisioning script or is handled declaratively by Flux.
    command = <<-EOT
      echo "---[ Wait for Kubernetes API ]---"
      TALOSCONFIG_FILE=$(mktemp)
      cat > "$TALOSCONFIG_FILE" <<'EOF'
${var.talosconfig}
EOF
      export TALOSCONFIG="$TALOSCONFIG_FILE"

      KUBECONFIG_FILE=$(mktemp)

      # Wait for talosctl to be able to generate a kubeconfig
      echo "⏳ Waiting for talosctl to generate kubeconfig..."
      for i in {1..12}; do
        if talosctl -n ${local.first_cp_node.ipv6} kubeconfig "$KUBECONFIG_FILE" >/dev/null 2>&1; then
          echo "✓ Kubeconfig generated."
          break
        fi
        echo "  ... attempt $i/12, retrying in 5s"
        sleep 5
      done

      # Wait for the Kubernetes API to be responsive AND at least 1 node to register
      # Note: `kubectl get nodes >/dev/null 2>&1` exits 0 even with 0 nodes (empty list).
      # We must check for at least one node row to avoid proceeding before kubelets join.
      echo "⏳ Waiting for Kubernetes API server and node registration..."
      for i in {1..60}; do
        if timeout 10 kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes --no-headers 2>/dev/null | grep -q .; then
          NODE_COUNT=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
          echo "✓ Kubernetes API is healthy! ($NODE_COUNT node(s) registered)"
          break
        fi
        echo "  ... attempt $i/60, retrying in 10s (waiting for nodes to register)"
        sleep 10
      done

      # Wait for etcd cluster to fully form with all members
      # This is critical for reliable bootstrap - etcd must have all 3 members before
      # API servers can register properly. Learner promotion can take 5-10 minutes.
      EXPECTED_CP_COUNT=${length(var.control_plane_nodes)}
      echo "⏳ Waiting for etcd cluster to form with all $EXPECTED_CP_COUNT members..."
      for i in {1..120}; do
        ETCD_MEMBER_COUNT=$(talosctl -n ${local.first_cp_node.ipv6} etcd members 2>/dev/null | grep -c "false$" || echo "0")
        if [ "$ETCD_MEMBER_COUNT" -ge "$EXPECTED_CP_COUNT" ]; then
          echo "✓ All $EXPECTED_CP_COUNT etcd members joined (learner promotion complete)"
          break
        fi
        if [ $((i % 12)) -eq 0 ]; then
          echo "  ... $ETCD_MEMBER_COUNT/$EXPECTED_CP_COUNT etcd members ready, waiting for learner promotion..."
        fi
        sleep 5
      done

      # Wait for all control plane API servers to be registered in kubernetes service endpoints
      # This prevents issues where pods can't reach ClusterIP if they're scheduled on a CP node
      # whose API server hasn't joined yet
      echo "⏳ Waiting for all $EXPECTED_CP_COUNT control plane API servers to join kubernetes service..."
      for i in {1..60}; do
        CP_ENDPOINT_COUNT=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get endpoints kubernetes -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
        if [ "$CP_ENDPOINT_COUNT" -ge "$EXPECTED_CP_COUNT" ]; then
          echo "✓ All $EXPECTED_CP_COUNT control plane API servers registered in kubernetes service"
          rm -f "$KUBECONFIG_FILE"
          rm -f "$TALOSCONFIG_FILE"
          exit 0
        fi
        echo "  ... $CP_ENDPOINT_COUNT/$EXPECTED_CP_COUNT endpoints ready, retrying in 5s"
        sleep 5
      done

      echo "❌ Control plane endpoint registration timed out after 5 minutes. Aborting."
      rm -f "$KUBECONFIG_FILE"
      rm -f "$TALOSCONFIG_FILE"
      exit 1
    EOT
  }

  depends_on = [talos_machine_bootstrap.cluster]
}

# Note: The talos_cluster_health data source is not used because it compares etcd
# member IPs (reported as IPv4) against control plane node IPs. This would require
# passing IPv4 addresses, which defeats the purpose of IPv6 configuration.
# The null_resource.wait_for_etcd above already verifies cluster health via kubectl.

# Get kubeconfig after bootstrap
resource "talos_cluster_kubeconfig" "cluster" {
  client_configuration = var.client_configuration
  node                 = local.first_cp_node.ipv6
  endpoint             = local.effective_cluster_endpoint

  depends_on = [null_resource.wait_for_etcd]
}

# Note: SOPS AGE secret creation moved to flux-instance module
# This keeps the bootstrap module focused on Talos cluster bootstrap only

# Write kubeconfig to file for use by downstream modules
resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  filename        = "${var.repo_root}/talos/clusters/cluster-${var.cluster_id}/kubeconfig"
  file_permission = "0600"

  depends_on = [talos_cluster_kubeconfig.cluster]
}

# Note: Post-bootstrap operations moved to flux-instance module
# This is where HelmRelease fix and Kopia restore should run after Flux is ready
