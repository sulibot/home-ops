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

      # Wait for the Kubernetes API to be responsive via kubectl
      echo "⏳ Waiting for Kubernetes API server to respond..."
      for i in {1..60}; do
        if timeout 10 kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes >/dev/null 2>&1; then
          echo "✓ Kubernetes API is healthy!"
          rm -f "$KUBECONFIG_FILE"
          rm -f "$TALOSCONFIG_FILE"
          exit 0
        fi
        echo "  ... attempt $i/60, retrying in 10s"
        sleep 10
      done

      echo "❌ Cluster health check timed out after 10 minutes. Aborting."
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

# Create SOPS AGE secret for Flux to decrypt secrets
resource "null_resource" "sops_age_secret" {
  count = var.flux_git_repository != "" && var.sops_age_key != "" ? 1 : 0

  triggers = {
    kubeconfig = sha256(talos_cluster_kubeconfig.cluster.kubeconfig_raw)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create temp kubeconfig for kubectl
      KUBECONFIG_FILE=$(mktemp)
      echo '${base64encode(talos_cluster_kubeconfig.cluster.kubeconfig_raw)}' | base64 -d > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"

      echo "🔑 Creating SOPS AGE secret in flux-system namespace..."

      # Create namespace if it doesn't exist (required before Flux bootstrap)
      kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

      # Create or update the secret
      kubectl create secret generic sops-age \
        --namespace=flux-system \
        --from-literal=age.agekey="${var.sops_age_key}" \
        --dry-run=client -o yaml | kubectl apply -f -

      echo "✓ SOPS AGE secret created"

      # IMPORTANT: Wait for secret to be actually readable
      # This ensures Flux controllers can access it before Kustomizations reconcile
      echo "⏱ Verifying secret is readable..."
      RETRIES=30
      ATTEMPT=0
      while [ $ATTEMPT -lt $RETRIES ]; do
        if kubectl get secret sops-age -n flux-system >/dev/null 2>&1 && \
           kubectl get secret sops-age -n flux-system -o jsonpath='{.data.age\.agekey}' | base64 -d | grep -q "AGE-SECRET-KEY"; then
          echo "✓ SOPS AGE secret is readable and valid"
          exit 0
        fi
        ATTEMPT=$((ATTEMPT + 1))
        sleep 1
      done

      echo "⚠ Warning: Secret verification timed out, but proceeding anyway"

      rm -f "$KUBECONFIG_FILE"
      exit 0
    EOT
  }

  depends_on = [
    talos_cluster_kubeconfig.cluster
  ]
}

# Run post-bootstrap operations (HelmRelease fix, Kopia restore)
resource "null_resource" "post_bootstrap" {
  count = var.flux_git_repository != "" && var.repo_root != "" ? 1 : 0

  triggers = {
    sops_secret_created = try(null_resource.sops_age_secret[0].id, "")
  }

  provisioner "local-exec" {
    working_dir = var.repo_root
    command = <<-EOT
      # Create temp kubeconfig for post-bootstrap script
      KUBECONFIG_FILE=$(mktemp)
      echo '${base64encode(talos_cluster_kubeconfig.cluster.kubeconfig_raw)}' | base64 -d > "$KUBECONFIG_FILE"

      # Run post-bootstrap script
      KUBECONFIG="$KUBECONFIG_FILE" ./scripts/post-bootstrap.sh

      # Cleanup
      rm -f "$KUBECONFIG_FILE"
    EOT
  }

  depends_on = [
    null_resource.sops_age_secret
  ]
}
