data "external" "password_hash" {
  program = [
    "sh", "-c", 
    "echo '{\"password\": \"'$(openssl passwd -6 \"${var.vm_password}\")'\"}'"
  ]
}

locals {
  vm_password_hashed = trimspace(data.external.password_hash.result["password"])
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "resources"
  node_name    = "pve01"

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: base-debian
    users:
      - default
      - name: debian
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
        passwd: ${local.vm_password_hashed}

      - name: root
        shell: /bin/bash
        lock_passwd: false
        passwd: ${local.vm_password_hashed}
        ssh_authorized_keys:
          - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}

    ssh_pwauth: true

    # Install essential and monitoring packages
    packages:
      - apt-transport-https
      - btrfs-progs
      - containerd
      - curl
      - dstat
      - dnsutils
      - e2fsprogs
      - ethtool
      - fio
      - git
      - gnupg
      - gzip
      - htop
      - inxi
      - iperf3
      - iproute2
      - iptables
      - iputils-ping
      - iotop
      - jq
      - lshw
      - lsof
      - lvm2
      - make
      - mc
      - mtr-tiny
      - net-tools
      - nmap
      - openssl
      - parted
      - procps
      - qemu-guest-agent
      - rsync
      - smartmontools
      - strace
      - sysstat
      - tar
      - tcpdump
      - traceroute
      - unzip
      - util-linux
      - wget
      - xfsprogs

    # Commands to configure and start services
    runcmd:
        - apt update
        - apt upgrade -y
        - timedatectl set-timezone America/Los_Angeles
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = "user-data-cloud-config.yaml"
  }
}
