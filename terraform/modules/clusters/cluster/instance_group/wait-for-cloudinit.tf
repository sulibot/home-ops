# Wait for cloud-init to complete on all VMs
resource "null_resource" "wait_for_cloudinit" {
  for_each = toset(local.indices)

  # Run after VM is created
  depends_on = [proxmox_virtual_environment_vm.instances]

  # Trigger re-provisioning if VM changes
  triggers = {
    vm_id = proxmox_virtual_environment_vm.instances[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      HOSTNAME="${format("%s%s%03d", var.cluster_name, var.group.role_id, var.group.segment_start + tonumber(each.key))}"
      IP_ADDR="${local.mesh_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(each.key)}"
      MAX_WAIT=900  # 15 minutes max
      ELAPSED=0

      echo "=== Waiting for $HOSTNAME ($IP_ADDR) to be SSH accessible ==="
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@$IP_ADDR "exit" 2>/dev/null; then
          echo "✓ SSH accessible"
          break
        fi
        echo "Attempt $((ELAPSED/5)): Waiting for SSH... ($ELAPSED/$MAX_WAIT seconds)"
        sleep 5
        ELAPSED=$((ELAPSED + 5))
      done

      if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "✗ SSH never became accessible on $HOSTNAME"
        exit 1
      fi

      echo "=== Waiting for cloud-init to complete on $HOSTNAME ==="
      ssh -o StrictHostKeyChecking=no root@$IP_ADDR "cloud-init status --wait" || {
        echo "✗ cloud-init failed on $HOSTNAME"
        ssh -o StrictHostKeyChecking=no root@$IP_ADDR "cloud-init status --long"
        exit 1
      }

      echo "✓ cloud-init completed on $HOSTNAME"

      # Show timing summary
      ssh -o StrictHostKeyChecking=no root@$IP_ADDR "cloud-init analyze show 2>/dev/null | head -20" || true
    EOT
  }
}
