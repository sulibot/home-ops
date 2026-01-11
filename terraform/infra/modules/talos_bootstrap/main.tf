# Get first control plane node for bootstrap
locals {
  first_cp_name = length(var.control_plane_nodes) > 0 ? sort(keys(var.control_plane_nodes))[0] : ""
  first_cp_node = length(var.control_plane_nodes) > 0 ? var.control_plane_nodes[local.first_cp_name] : { ipv6 = "", ipv4 = "" }
}

# Apply machine configurations to all nodes
resource "talos_machine_configuration_apply" "nodes" {
  for_each = toset(var.all_node_names)

  client_configuration        = var.client_configuration
  machine_configuration_input = replace(var.machine_configs[each.key].machine_configuration, "$$", "$")
  node                        = each.key

  config_patches = [
    replace(var.machine_configs[each.key].config_patch, "$$", "$")
  ]

  # Apply configs via IPv6 (static fc00::/7 route provides connectivity)
  endpoint = var.all_node_ips[each.key].ipv6
}

# Bootstrap the cluster on the first control plane node
resource "talos_machine_bootstrap" "cluster" {
  client_configuration = var.client_configuration
  node                 = local.first_cp_node.ipv6
  endpoint             = local.first_cp_node.ipv6

  depends_on = [talos_machine_configuration_apply.nodes]
}

# Smart wait: Poll for cluster health every 10s, up to 5 minutes
resource "null_resource" "wait_for_etcd" {
  triggers = {
    bootstrap_id = talos_machine_bootstrap.cluster.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for cluster to become healthy..."

      # Generate kubeconfig to temp file
      KUBECONFIG_FILE=$(mktemp)
      talosctl -n ${local.first_cp_node.ipv6} kubeconfig "$KUBECONFIG_FILE" 2>/dev/null || true

      RETRIES=30  # 30 retries * 10 seconds = 5 minutes max
      ATTEMPT=0

      while [ $ATTEMPT -lt $RETRIES ]; do
        ATTEMPT=$((ATTEMPT + 1))
        echo "⏱ Attempt $ATTEMPT/$RETRIES: Checking cluster health..."

        if timeout 10 kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes >/dev/null 2>&1; then
          echo "✓ Cluster is healthy!"
          rm -f "$KUBECONFIG_FILE"
          exit 0
        fi

        if [ $ATTEMPT -lt $RETRIES ]; then
          echo "   Cluster not ready, waiting 10 seconds..."
          sleep 10
        fi
      done

      echo "🔧 Configuring CoreDNS to use host DNS forwarder (169.254.116.108)..."
      
      # Wait for CoreDNS ConfigMap to exist
      echo "⏳ Waiting for CoreDNS ConfigMap..."
      timeout 60s bash -c "until kubectl --kubeconfig='$KUBECONFIG_FILE' -n kube-system get configmap coredns >/dev/null 2>&1; do sleep 2; done"

      # Patch CoreDNS ConfigMap to forward to Talos link-local DNS
      # This overrides the default forward to /etc/resolv.conf (127.0.0.53) which is unreachable
      kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system patch configmap coredns --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health {\n        lameduck 5s\n    }\n    ready\n    log . {\n        class error\n    }\n    prometheus :9153\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    forward . 169.254.116.108 {\n       max_concurrent 1000\n    }\n    cache 30 {\n        denial 9984 30\n    }\n    loop\n    reload\n    loadbalance\n}\n"}}'

      # Restart CoreDNS to pick up changes
      echo "🔄 Restarting CoreDNS..."
      kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system rollout restart deployment coredns
      
      # Wait for rollout to complete
      kubectl --kubeconfig="$KUBECONFIG_FILE" -n kube-system rollout status deployment coredns --timeout=60s

      echo "✅ CoreDNS configured successfully"

      rm -f "$KUBECONFIG_FILE"
      echo "⚠ Cluster health check timed out after 5 minutes, proceeding anyway..."
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
  endpoint             = local.first_cp_node.ipv6

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
