#!/bin/bash
# Fix missing cloud-init snippet for Debian test VMs 100 and 101

set -e

echo "Creating cloud-init user-data snippet on pve01..."

# Create the cloud-init user-data file
cat > /tmp/debian13-template-user-data.yaml << 'EOF'
#cloud-config
preserve_hostname: false
ssh_pwauth: true
disable_root: false
manage_etc_hosts: true
timezone: America/Los_Angeles
locale: en_US.UTF-8

chpasswd:
  list:
    - debian:debian
    - root:debian
  expire: false

users:
  - default
  - name: debian
    lock_passwd: false
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com
    sudo: ALL=(ALL) NOPASSWD:ALL
  - name: root
    lock_passwd: false
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com

package_update: true
package_upgrade: false

packages:
  - qemu-guest-agent
  - frr
  - net-tools
  - iproute2
  - iputils-ping
  - tcpdump
  - traceroute
  - bind9-dnsutils
  - curl
  - wget
  - htop

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable frr
  - echo "Cloud-init complete" > /var/log/cloud-init-done
EOF

# Ensure the snippets directory exists
mkdir -p /mnt/pve/resources/snippets

# Copy the file to the snippets directory
cp /tmp/debian13-template-user-data.yaml /mnt/pve/resources/snippets/

# Set proper permissions
chmod 644 /mnt/pve/resources/snippets/debian13-template-user-data.yaml

echo "Cloud-init snippet created successfully!"
echo "File location: /mnt/pve/resources/snippets/debian13-template-user-data.yaml"

# Verify the file exists
if [ -f /mnt/pve/resources/snippets/debian13-template-user-data.yaml ]; then
    echo "✓ File verified"
    ls -lh /mnt/pve/resources/snippets/debian13-template-user-data.yaml
else
    echo "✗ File not found - check storage configuration"
    exit 1
fi

echo ""
echo "You can now start VMs 100 and 101"
