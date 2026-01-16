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
        echo "DEBUG: ⚠ CoreDNS ConfigMap not found after $${MAX_WAIT}s, skipping CoreDNS patch"
      else
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
      fi

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

# Fix stuck HelmReleases after bootstrap
# Workaround for Flux bug where early HelmReleases get observedGeneration: -1
resource "null_resource" "fix_stuck_helmreleases" {
  count = var.flux_git_repository != "" ? 1 : 0

  triggers = {
    sops_secret_created = try(null_resource.sops_age_secret[0].id, "")
  }

  provisioner "local-exec" {
    working_dir = var.repo_root
    command = <<-EOT
      echo "=========================================="
      echo "🔧 Checking for stuck HelmReleases"
      echo "=========================================="

      # Loop for up to 10 minutes checking every 30 seconds
      MAX_DURATION=600  # 10 minutes
      CHECK_INTERVAL=30
      START_TIME=$(date +%s)
      FIX_APPLIED=false

      while true; do
        ELAPSED=$(($(date +%s) - START_TIME))
        if [ $ELAPSED -ge $MAX_DURATION ]; then
          echo "⏱ Reached 10-minute timeout"
          break
        fi

        # Check if HelmReleases exist
        if ! kubectl get helmrelease -n ceph-csi ceph-csi-cephfs ceph-csi-rbd >/dev/null 2>&1; then
          echo "⏱ [$ELAPSED s] Waiting for Ceph CSI HelmReleases to be created..."
          sleep $CHECK_INTERVAL
          continue
        fi

        # Check if HelmReleases are ready
        CEPHFS_READY=$(kubectl get helmrelease ceph-csi-cephfs -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        RBD_READY=$(kubectl get helmrelease ceph-csi-rbd -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

        if [ "$CEPHFS_READY" = "True" ] && [ "$RBD_READY" = "True" ]; then
          echo "✓ Ceph CSI HelmReleases are ready"
          break
        fi

        # Check if stuck with observedGeneration: -1 (only check after 90 seconds)
        if [ $ELAPSED -ge 90 ] && [ "$FIX_APPLIED" = "false" ]; then
          CEPHFS_GEN=$(kubectl get helmrelease ceph-csi-cephfs -n ceph-csi -o jsonpath='{.status.observedGeneration}' 2>/dev/null || echo "")
          RBD_GEN=$(kubectl get helmrelease ceph-csi-rbd -n ceph-csi -o jsonpath='{.status.observedGeneration}' 2>/dev/null || echo "")

          if [ "$CEPHFS_GEN" = "-1" ] || [ "$RBD_GEN" = "-1" ]; then
            echo "⚠ [$ELAPSED s] Detected stuck HelmReleases (observedGeneration: -1)"
            echo "🔧 Applying fix for stuck HelmReleases..."

            # Remove finalizers and delete HelmReleases
            kubectl patch helmrelease ceph-csi-cephfs -n ceph-csi -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
            kubectl patch helmrelease ceph-csi-rbd -n ceph-csi -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
            sleep 2

            # Reconcile kustomizations to recreate HelmReleases
            kubectl annotate kustomization ceph-csi-cephfs -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite 2>/dev/null || true
            kubectl annotate kustomization ceph-csi-rbd -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite 2>/dev/null || true
            sleep 5

            # Restart helm-controller to pick up new HelmReleases
            kubectl rollout restart deployment helm-controller -n flux-system
            kubectl rollout status deployment helm-controller -n flux-system --timeout=60s

            echo "✓ Fix applied, HelmReleases recreated and helm-controller restarted"
            FIX_APPLIED=true
            # Continue loop to verify fix worked
          fi
        fi

        echo "⏱ [$ELAPSED s] Waiting for Ceph CSI HelmReleases to reconcile..."
        sleep $CHECK_INTERVAL
      done

      # Final status check
      CEPHFS_READY=$(kubectl get helmrelease ceph-csi-cephfs -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
      RBD_READY=$(kubectl get helmrelease ceph-csi-rbd -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

      if [ "$CEPHFS_READY" = "True" ] && [ "$RBD_READY" = "True" ]; then
        echo "✓ Ceph CSI HelmReleases are ready"
      else
        echo "⚠ Warning: Ceph CSI may still need manual intervention"
        echo "   Check with: kubectl get helmrelease -n ceph-csi"
      fi

      echo "=========================================="
      echo "✓ HelmRelease check complete"
      echo "=========================================="

      # Apply Kopia repository PV/PVC after Ceph CSI is ready
      echo "=========================================="
      echo "🗄 Reclaiming Kopia repository"
      echo "=========================================="

      # Wait for Ceph CSI to be actually running (pods exist)
      echo "⏱ Waiting for Ceph CSI pods to be running..."
      RETRIES=30
      ATTEMPT=0
      while [ $ATTEMPT -lt $RETRIES ]; do
        CEPHFS_PODS=$(kubectl get pods -n ceph-csi -l app=ceph-csi-cephfs --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
        if [ "$CEPHFS_PODS" -gt 0 ]; then
          echo "✓ Ceph CSI CephFS pods are running"
          break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        sleep 5
      done

      if [ $ATTEMPT -eq $RETRIES ]; then
        echo "⚠ Warning: Ceph CSI pods not running, Kopia repository may not bind"
      fi

      # Apply Kopia repository PV and PVC to reclaim existing backup storage
      echo "📦 Applying Kopia repository PV and PVC..."
      kubectl apply -f kubernetes/apps/data/kopia/app/kopia-repository-pv.yaml
      kubectl apply -f kubernetes/apps/data/kopia/app/kopia-repository-pvc.yaml

      # Wait for PVC to bind
      echo "⏱ Waiting for Kopia PVC to bind..."
      RETRIES=12
      ATTEMPT=0
      while [ $ATTEMPT -lt $RETRIES ]; do
        PVC_STATUS=$(kubectl get pvc kopia -n volsync-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PVC_STATUS" = "Bound" ]; then
          echo "✓ Kopia repository PVC bound successfully"
          break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        sleep 5
      done

      if [ "$PVC_STATUS" != "Bound" ]; then
        echo "⚠ Warning: Kopia PVC did not bind within 60 seconds"
        echo "   Check with: kubectl get pvc kopia -n volsync-system"
      fi

      echo "=========================================="
      echo "✓ Bootstrap complete"
      echo "=========================================="
      exit 0
    EOT
  }

  depends_on = [
    null_resource.sops_age_secret
  ]
}
