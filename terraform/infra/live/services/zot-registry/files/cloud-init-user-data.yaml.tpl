#cloud-config
hostname: zot01
fqdn: zot01.local
manage_etc_hosts: true

users:
  - name: debian
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
%{ if ssh_public_key != "" ~}
    ssh_authorized_keys:
      - ${ssh_public_key}
%{ endif ~}

%{ if ssh_public_key != "" ~}
ssh_authorized_keys:
  - ${ssh_public_key}
%{ endif ~}
disable_root: false
ssh_pwauth: false

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl
  - jq

write_files:
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: |
      network: {config: disabled}
    owner: root:root
    permissions: '0644'

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

final_message: "Zot registry VM zot01 ready after $UPTIME seconds"
