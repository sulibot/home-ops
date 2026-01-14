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
    command = <<-EOT
      set -x  # Enable debug mode - print all commands

      echo "=========================================="
      echo "DEBUG: Starting cluster health check"
      echo "=========================================="

      # Use the generated talosconfig directly for this run
      TALOSCONFIG_FILE=$(mktemp)
      cat > "$TALOSCONFIG_FILE" <<'EOF'
${var.talosconfig}
EOF
      export TALOSCONFIG="$TALOSCONFIG_FILE"
      echo "DEBUG: Created temp talosconfig at: $TALOSCONFIG_FILE"

      # Generate kubeconfig to temp file
      KUBECONFIG_FILE=$(mktemp)
      echo "DEBUG: Created temp kubeconfig at: $KUBECONFIG_FILE"

      TALOS_RETRIES=12
      TALOS_ATTEMPT=0
      while [ $TALOS_ATTEMPT -lt $TALOS_RETRIES ]; do
        TALOS_ATTEMPT=$((TALOS_ATTEMPT + 1))
        if talosctl -n ${local.first_cp_node.ipv6} kubeconfig "$KUBECONFIG_FILE" 2>&1; then
          echo "DEBUG: Kubeconfig generated"
          break
        fi

        if [ $TALOS_ATTEMPT -lt $TALOS_RETRIES ]; then
          echo "WARN: talosctl kubeconfig failed (attempt $TALOS_ATTEMPT/$TALOS_RETRIES), retrying in 5 seconds..."
          sleep 5
        else
          echo "ERROR: talosctl kubeconfig failed after $TALOS_RETRIES attempts"
          exit 1
        fi
      done

      RETRIES=60  # 60 retries * 10 seconds = 10 minutes max
      ATTEMPT=0

      while [ $ATTEMPT -lt $RETRIES ]; do
        ATTEMPT=$((ATTEMPT + 1))
        echo "DEBUG: ⏱ Attempt $ATTEMPT/$RETRIES: Checking cluster health..."

        if timeout 10 kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes 2>&1; then
          echo "DEBUG: ✓ Cluster is healthy!"
          break
        fi

        if [ $ATTEMPT -lt $RETRIES ]; then
          echo "DEBUG:    Cluster not ready, waiting 10 seconds..."
          sleep 10
        fi
      done

      # Check if cluster became healthy
      if ! kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes >/dev/null 2>&1; then
        echo "ERROR: ✗ Cluster health check timed out after 10 minutes. Aborting."
        exit 1
      fi

      echo "=========================================="
      echo "DEBUG: Starting CoreDNS patch"
      echo "=========================================="

      # Wait for CoreDNS ConfigMap to exist (Talos creates it during bootstrap)
      echo "DEBUG: ⏳ Waiting for CoreDNS ConfigMap to be created..."
      WAIT_ATTEMPTS=0
      MAX_WAIT=60  # Wait up to 60 seconds for ConfigMap to appear

      while [ $WAIT_ATTEMPTS -lt $MAX_WAIT ]; do
        if kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system get configmap coredns >/dev/null 2>&1; then
          echo "DEBUG: ✓ CoreDNS ConfigMap found after $${WAIT_ATTEMPTS}s"
          break
        fi
        WAIT_ATTEMPTS=$((WAIT_ATTEMPTS + 1))
        sleep 1
      done

      if ! kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system get configmap coredns >/dev/null 2>&1; then
        echo "DEBUG: ✗ CoreDNS ConfigMap not found after $${MAX_WAIT}s, aborting"
        exit 1
      fi

      # PATCH: Ensure CoreDNS is configured to use the host DNS forwarder
      # This is required because Talos/Cilium integration sometimes reverts to /etc/resolv.conf
      echo "DEBUG: 🔧 Patching CoreDNS to use host DNS forwarder (169.254.116.108)..."

      if kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system patch configmap coredns --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health {\n        lameduck 5s\n    }\n    ready\n    log . {\n        class error\n    }\n    prometheus :9153\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    forward . 169.254.116.108 {\n       max_concurrent 1000\n    }\n    cache 30 {\n        denial 9984 30\n    }\n    loop\n    reload\n    loadbalance\n}\n"}}' 2>&1; then
        echo "DEBUG: ✓ CoreDNS ConfigMap patched successfully"
      else
        echo "DEBUG: ✗ CoreDNS ConfigMap patch failed"
        exit 1
      fi

      echo "DEBUG: 🔄 Restarting CoreDNS..."
      if kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system get deployment coredns >/dev/null 2>&1; then
        if kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system rollout restart deployment coredns 2>&1; then
          echo "DEBUG: ✓ CoreDNS restart initiated"
        else
          echo "DEBUG: ✗ CoreDNS restart failed"
          exit 1
        fi

        # Wait for rollout to complete (optional, but good for verification)
        echo "DEBUG: ⏳ Waiting for CoreDNS rollout to complete..."
        if kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system rollout status deployment coredns --timeout=60s 2>&1; then
          echo "DEBUG: ✓ CoreDNS rollout completed"
        else
          echo "DEBUG: ⚠ CoreDNS rollout status check timed out (continuing anyway)"
        fi
      else
        echo "DEBUG: ⚠ CoreDNS deployment not found, skipping restart"
      fi

      echo "=========================================="
      echo "DEBUG: Verifying CoreDNS configuration"
      echo "=========================================="
      kubectl --kubeconfig="$KUBECONFIG_FILE" get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' | grep -A 2 forward || true

      echo "=========================================="
      echo "DEBUG: Bootstrap completed successfully"
      echo "=========================================="
      rm -f "$KUBECONFIG_FILE"
      rm -f "$TALOSCONFIG_FILE"
      exit 0
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
    flux_installed = try(flux_bootstrap_git.this[0].id, "")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🔑 Creating SOPS AGE secret in flux-system namespace..."

      # Wait for flux-system namespace to exist
      RETRIES=30
      ATTEMPT=0
      while [ $ATTEMPT -lt $RETRIES ]; do
        if kubectl get namespace flux-system >/dev/null 2>&1; then
          break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        sleep 2
      done

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
      exit 0
    EOT
  }

  depends_on = [
    flux_bootstrap_git.this
  ]
}
