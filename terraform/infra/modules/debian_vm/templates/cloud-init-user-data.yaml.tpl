#cloud-config
hostname: ${hostname}
fqdn: ${hostname}

users:
  - name: root
    ssh_authorized_keys:
      - ${ssh_public_key}

# Update and upgrade system
package_update: true
package_upgrade: true

# Install packages
packages:
%{ for pkg in initial_packages ~}
  - ${pkg}
%{ endfor ~}

# Run setup script if provided
runcmd:
%{ if setup_script != "" ~}
  - |
    ${indent(4, setup_script)}
%{ endif ~}
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
