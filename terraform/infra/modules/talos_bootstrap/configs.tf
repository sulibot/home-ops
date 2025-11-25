# Write kubeconfig and talosconfig directly to home directory

# Write kubeconfig to temp file and merge to ~/.kube/config
resource "null_resource" "kubeconfig" {
  triggers = {
    kubeconfig = sha256(talos_cluster_kubeconfig.cluster.kubeconfig_raw)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Use talosctl to fetch and merge kubeconfig - it handles everything properly
      # Must specify a node since talosconfig has multiple nodes configured
      FIRST_NODE=$(talosctl config info -o json 2>/dev/null | jq -r '.endpoints[0]' || echo "")
      if [ -n "$FIRST_NODE" ]; then
        talosctl -n "$FIRST_NODE" kubeconfig --force
      else
        echo "⚠ Warning: Could not determine talos endpoint, skipping kubeconfig"
        exit 1
      fi
      echo "✓ Kubeconfig merged to ~/.kube/config"
    EOT
  }

  depends_on = [null_resource.talosconfig]
}

# Write talosconfig to temp file and merge to ~/.talos/config
resource "null_resource" "talosconfig" {
  triggers = {
    talosconfig = sha256(var.talosconfig)
  }

  provisioner "local-exec" {
    command = <<-EOT
      TMP_FILE=$(mktemp)
      cat > "$TMP_FILE" <<'EOF'
${var.talosconfig}
EOF
      mkdir -p ~/.talos
      talosctl config merge "$TMP_FILE"
      rm "$TMP_FILE"
      echo "✓ Talosconfig merged to ~/.talos/config (use: talosctl config context cluster-${var.cluster_id})"
    EOT
  }
}
