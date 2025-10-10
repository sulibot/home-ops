# Fabric resource is optional (peer model disables it)
locals {
  _fabric_name = var.sdn_fabric_name
}

resource "null_resource" "evpn_fabric" {
  count = var.configure_fabric ? 1 : 0

  triggers = {
    fabric  = local._fabric_name
    ctrl_id = var.sdn_controller.id
    cmdhash = sha1("fabric:${var.sdn_controller.id}:${local._fabric_name}")
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${local._primary_ssh} '
        set -e
        FAB="${self.triggers.fabric}"
        CTRL="${self.triggers.ctrl_id}"

        if pvesh get /cluster/sdn/fabrics/"$FAB" >/dev/null 2>&1; then
          # update (do NOT try to change -type on existing fabric)
          pvesh set /cluster/sdn/fabrics/"$FAB" -controller "$CTRL"
        else
          # Try multiple creation styles for cross-version compatibility
          pvesh create /cluster/sdn/fabrics -type evpn -fabric "$FAB" -controller "$CTRL" >/dev/null 2>&1 || \
          pvesh create /cluster/sdn/fabrics/"$FAB" -type evpn -controller "$CTRL"               >/dev/null 2>&1 || \
          pvesh set    /cluster/sdn/fabrics/"$FAB" -type evpn -controller "$CTRL"
        fi

        # Commit SDN changes
        pvesh create /cluster/sdn/commit >/dev/null 2>&1 || \
        pvesh set    /cluster/sdn/commit >/dev/null 2>&1 || true
      '
    EOT
  }

  depends_on = [null_resource.evpn_controller]
}
