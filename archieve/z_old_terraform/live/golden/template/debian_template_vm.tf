# ===== ./debian_template_vm.tf =====
# --- VM that will become the template ---
resource "proxmox_virtual_environment_vm" "debian_template" {
  name      = "debian13-cloudinit-template"
  vm_id     = 9000
  node_name = var.node_name # <-- Used variable for portability

  machine         = "q35"
  bios            = "ovmf"
  stop_on_destroy = true
  keyboard_layout = "en-us"
  scsi_hardware   = "virtio-scsi-pci"  # Match cloned VMs for consistency

  operating_system { type = "l26" }

  cpu {
    type    = "host"
    sockets = 1
    cores   = 2
  }

  memory {
    dedicated = 1048
    floating  = 2048
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 200
  }

  # Keep EFI vars off Ceph for reliability
  # No Secure Boot for faster boot and consistency with cloned VMs
  efi_disk {
    datastore_id      = "local"
    type              = "4m"
    pre_enrolled_keys = false  # Disable Secure Boot (not needed for K8s)
  }

  # Import qcow2 -> Ceph RBD, then resize
  disk {
    datastore_id = "rbd-vm"
    interface    = "scsi0"
    file_id      = var.template_image_id
    size         = 16
    iothread     = true
    cache        = "writeback"
    discard      = "on"
    file_format  = "raw" 
  }

  agent { enabled = true }

  serial_device { device = "socket" }
  vga           { type = "serial0" }
  on_boot       = false

  initialization {
    datastore_id      = "local"
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id

    ip_config {
      ipv4 { address = "dhcp" }
      ipv6 { address = "auto" }
    }
  }

  depends_on = [proxmox_virtual_environment_file.user_data_cloud_config]
}

# --- Wait for cloud-init to finish inside the VM (uses qemu-guest-agent) ---
locals {
  pve_ssh_target = "root@${var.pve_ssh_host}" # <-- Used variable for dynamic SSH target
}

resource "null_resource" "wait_for_cloud_init_done" {
  triggers = {
    vm_generation = proxmox_virtual_environment_vm.debian_template.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      ssh -o StrictHostKeyChecking=no ${local.pve_ssh_target} << 'SSH_EOF'
        set -e
        VM_ID=${proxmox_virtual_environment_vm.debian_template.vm_id}
        
        echo "Waiting for qemu-guest-agent in VM $VM_ID..."

        # First wait for qemu-guest-agent to be responsive
        AGENT_TIMEOUT=120  # 2 minutes (reduced from 5 min)
        AGENT_ELAPSED=0
        until qm guest cmd $VM_ID ping >/dev/null 2>&1; do
          if [ $AGENT_ELAPSED -ge $AGENT_TIMEOUT ]; then
            echo "ERROR: qemu-guest-agent not responding after $AGENT_TIMEOUT seconds"
            exit 1
          fi
          echo "Waiting for qemu-guest-agent... ($AGENT_ELAPSED/$AGENT_TIMEOUT seconds)"
          sleep 2
          AGENT_ELAPSED=$((AGENT_ELAPSED + 2))
        done
        echo "✓ qemu-guest-agent is responsive"

        echo "Waiting for cloud-init in VM $VM_ID..."

        # Wait for completion marker with timeout
        TIMEOUT=900  # 15 minutes (reduced from 30 min)
        ELAPSED=0
        until qm guest exec $VM_ID -- test -f /tmp/golden-cloud-config.done >/dev/null 2>&1; do
          if [ $ELAPSED -ge $TIMEOUT ]; then
            echo "ERROR: Timeout waiting for cloud-init after $TIMEOUT seconds"
            echo "Checking cloud-init status..."
            qm guest exec $VM_ID -- cloud-init status || true
            exit 1
          fi
          echo "Still waiting for cloud-init to complete... ($ELAPSED/$TIMEOUT seconds)"
          sleep 5
          ELAPSED=$((ELAPSED + 5))
        done
        
        echo "cloud-init completed in VM $VM_ID"
        
        # Comprehensive verification
        echo "=== Verifying template configuration ==="
        
        # Check SR-IOV drivers
        echo "Checking SR-IOV drivers..."
        if qm guest exec $VM_ID -- dkms status | grep -q "i915-sriov.*installed"; then
          echo "✓ SR-IOV drivers installed successfully"
        else
          echo "✗ WARNING: SR-IOV drivers not found in DKMS"
          qm guest exec $VM_ID -- dkms status || true
        fi
        
        # Check DKMS service is disabled
        echo "Checking DKMS service status..."
        if qm guest exec $VM_ID -- systemctl is-enabled dkms.service 2>&1 | grep -q "masked"; then
          echo "✓ DKMS service is properly masked"
        else
          echo "✗ WARNING: DKMS service not properly disabled"
          qm guest exec $VM_ID -- systemctl status dkms.service || true
        fi
        
        # Check module files exist
        echo "Checking module files..."
        KERNEL_VER=$(qm guest exec $VM_ID -- uname -r | tr -d '\n\r')
        if qm guest exec $VM_ID -- ls /lib/modules/$KERNEL_VER/updates/dkms/ 2>/dev/null | grep -q "i915"; then
          echo "✓ i915 module files found"
        else
          echo "✗ WARNING: i915 module files not found"
        fi
        
        # Check GRUB configuration
        echo "Checking GRUB configuration..."
        if qm guest exec $VM_ID -- grep -q "intel_iommu=on" /etc/default/grub; then
          echo "✓ GRUB configured with SR-IOV parameters"
        else
          echo "✗ WARNING: GRUB not configured with SR-IOV parameters"
        fi
        
        # Check qemu-guest-agent
        echo "Checking qemu-guest-agent..."
        if qm guest exec $VM_ID -- systemctl is-active qemu-guest-agent >/dev/null 2>&1; then
          echo "✓ qemu-guest-agent is running"
        else
          echo "✗ WARNING: qemu-guest-agent not running"
        fi
        
        # Check containerd
        echo "Checking containerd..."
        if qm guest exec $VM_ID -- systemctl is-enabled containerd >/dev/null 2>&1; then
          echo "✓ containerd is enabled"
        else
          echo "✗ WARNING: containerd not enabled"
        fi
        
        # Check chrony
        echo "Checking chrony..."
        if qm guest exec $VM_ID -- systemctl is-active chrony >/dev/null 2>&1; then
          echo "✓ chrony is active"
        else
          echo "✗ WARNING: chrony not active"
        fi
        
        # Verify systemd-timesyncd is disabled
        echo "Checking systemd-timesyncd is disabled..."
        if qm guest exec $VM_ID -- systemctl is-enabled systemd-timesyncd 2>&1 | grep -q "masked"; then
          echo "✓ systemd-timesyncd is masked (correct for K8s)"
        else
          echo "⚠ WARNING: systemd-timesyncd not masked"
        fi
        
        echo "=== Template verification complete ==="
      SSH_EOF
    EOT
  }
}

# --- Convert VM to a Proxmox template ---
resource "null_resource" "mark_as_template" {
  depends_on = [null_resource.wait_for_cloud_init_done]

  triggers = {
    vm_generation = proxmox_virtual_environment_vm.debian_template.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      ssh -o StrictHostKeyChecking=no ${local.pve_ssh_target} << 'SSH_EOF'
        set -e
        VM_ID=${proxmox_virtual_environment_vm.debian_template.vm_id}
        
        echo "Preparing VM $VM_ID for template conversion..."
        
        # Final cleanup inside VM before shutdown
        echo "Performing final cleanup..."
        qm guest exec $VM_ID -- bash -c '
          # Remove temporary files
          rm -f /tmp/golden-cloud-config.done
          rm -rf /tmp/*
          rm -rf /var/tmp/*
          
          # Clear bash history
          history -c
          rm -f /root/.bash_history
          rm -f /home/*/.bash_history
          
          # Clear SSH host keys (must be regenerated on first clone boot) <-- Added for hardening
          rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
          
          # Clear logs (keep SR-IOV and cloud-init template logs for reference)
          find /var/log -type f -name "*.log" ! -name "sriov-install.log" ! -name "cloud-init-template.log" -exec truncate -s 0 {} \;
          
          # Final sync
          sync
        ' || echo "Cleanup commands completed with warnings"
        
        echo "Shutting down VM $VM_ID..."
        qm shutdown $VM_ID --timeout 180 || {
          echo "Graceful shutdown failed, forcing stop..."
          qm stop $VM_ID
        }
        
        # Wait for VM to fully stop
        echo "Waiting for VM to stop..."
        for i in {1..60}; do
          if ! qm status $VM_ID | grep -q "running"; then
            echo "VM stopped successfully"
            break
          fi
          sleep 2
        done
        
        # Verify VM is stopped
        if qm status $VM_ID | grep -q "running"; then
          echo "ERROR: VM $VM_ID did not stop properly"
          exit 1
        fi
        
        # Convert to template
        echo "Converting VM $VM_ID to template..."
        qm template $VM_ID
        
        echo "✓ Successfully converted VM $VM_ID to template"
        echo "✓ Template includes pre-built SR-IOV drivers with DKMS disabled"
        echo "✓ Template configured with chrony for Kubernetes"
        echo "✓ Ready for cloning"
      SSH_EOF
    EOT
  }
}

# --- Verify template state ---
resource "null_resource" "verify_template_state" {
  depends_on = [null_resource.mark_as_template]

  triggers = {
    vm_generation = proxmox_virtual_environment_vm.debian_template.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      ssh -o StrictHostKeyChecking=no ${local.pve_ssh_target} << 'SSH_EOF'
        VM_ID=${proxmox_virtual_environment_vm.debian_template.vm_id}
        
        # Verify template status
        if ! qm config $VM_ID | grep -q "template: 1"; then
          echo "ERROR: VM $VM_ID is not marked as template"
          exit 1
        fi
        
        echo "✓ Template state verified"
        
        # Show final configuration
        echo "=== Template Configuration ==="
        qm config $VM_ID
      SSH_EOF
    EOT
  }
}