resource "proxmox_virtual_environment_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve01"

  source_file {
    # you may download this image locally on your workstation and then use the local path instead of the remote URL
    path      = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

    # you may also use the SHA256 checksum of the image to verify its integrity
    checksum = "55c687a9a242fab7b0ec89ac69f9def77696c4e160e6f640879a0b0031a08318"
  }
}

resource "proxmox_virtual_environment_file" "debian_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve01"

  source_file {
    # URL of the Debian Bookworm-backports cloud image
    path      = "https://cloud.debian.org/images/cloud/bookworm-backports/latest/debian-12-backports-generic-amd64.qcow2"
    file_name = "debian-12-backports-generic-amd64.img"

    # SHA256 checksum for image verification
    checksum = "8bc1a98da752349c0fffbc83dc9e2ad6f24b52a2a6617e9542cedeacf9bd2296"
  }
}


resource "proxmox_virtual_environment_file" "ubuntu_cloud_init_pve02" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve02"

  source_raw {
    data = <<EOF
#cloud-config

# Set the password for the ubuntu user and disable expiration
chpasswd:
  list: |
    ubuntu:ubuntu
    root:NewRootPassword  # Replace 'NewRootPassword' with the desired root password
  expire: false

# Install qemu-guest-agent for improved VM management
packages:
  - qemu-guest-agent

# Set timezone
timezone: America/Los_Angeles

# User configuration
users:
  - default
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    ssh-authorized-keys:
      - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
    sudo: ALL=(ALL) NOPASSWD:ALL

# Configure root to allow SSH access with the same key
  - name: root
    ssh-authorized-keys:
      - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
    sudo: ALL=(ALL) NOPASSWD:ALL

# Enable root SSH access in SSH configuration
runcmd:
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart ssh

# Reboot the VM after cloud-init completes
power_state:
    delay: now
    mode: reboot
    message: Rebooting after cloud-init completion
    condition: true
EOF

    file_name = "ubuntu.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "ubuntu_cloud_init_pve03" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve03"

  source_raw {
    data = <<EOF
#cloud-config

# Set the password for the ubuntu user and disable expiration
chpasswd:
  list: |
    ubuntu:ubuntu
    root:NewRootPassword  # Replace 'NewRootPassword' with the desired root password
  expire: false

# Install qemu-guest-agent for improved VM management
packages:
  - qemu-guest-agent

# Set timezone
timezone: America/Los_Angeles

# User configuration
users:
  - default
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    ssh-authorized-keys:
      - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
    sudo: ALL=(ALL) NOPASSWD:ALL

# Configure root to allow SSH access with the same key
  - name: root
    ssh-authorized-keys:
      - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
    sudo: ALL=(ALL) NOPASSWD:ALL

# Enable root SSH access in SSH configuration
runcmd:
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart ssh

# Reboot the VM after cloud-init completes
power_state:
    delay: now
    mode: reboot
    message: Rebooting after cloud-init completion
    condition: true
EOF

    file_name = "ubuntu.cloud-config.yaml"
  }
}
