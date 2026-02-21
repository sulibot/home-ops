# Write kubeconfig and talosconfig directly to home directory

# Merge kubeconfig into ~/.kube/config using the file already written by local_sensitive_file.kubeconfig.
# This avoids a second live talosctl API call (which can fail if talosconfig context is stale)
# and uses kubectl's --flatten merge which replaces existing entries with the same name (no duplicates).
resource "null_resource" "kubeconfig" {
  triggers = {
    # Re-run whenever the kubeconfig content changes (new cluster certs after re-bootstrap)
    kubeconfig = sha256(talos_cluster_kubeconfig.cluster.kubeconfig_raw)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      SRC="${var.repo_root}/talos/clusters/cluster-${var.cluster_id}/kubeconfig"
      DST="$HOME/.kube/config"
      mkdir -p "$HOME/.kube"
      # Merge: new context replaces existing same-named entry, no duplicates
      KUBECONFIG="$SRC:$DST" kubectl config view --flatten > "$DST.new"
      mv "$DST.new" "$DST"
      chmod 0600 "$DST"
      echo "✓ Kubeconfig merged to ~/.kube/config (context: sol)"
    EOT
  }

  depends_on = [local_sensitive_file.kubeconfig]
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
