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
    #hostname: base-debian
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
    package_update: true
    package_upgrade: true
    packages:
      - apt-transport-https
      - btrfs-progs
      - build-essential
      - clinfo
      - containerd
      - curl
      - dkms
      - dnsutils
      - dstat
      - e2fsprogs
      - ethtool
      - fio
      - git
      - gnupg
      - gpu-top
      - gzip
      - htop
      - intel-opencl-icd
      - intel-gpu-tools
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
      - vainfo
      - xfsprogs


    # Commands to configure and start services
    runcmd:
        - apt update
        - apt upgrade -y
        - timedatectl set-timezone America/Los_Angeles
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - echo 'blacklist xe' > /etc/modprobe.d/blacklist.conf
        - echo 'options i915 enable_guc=3' > /etc/modprobe.d/i915.conf
        - apt install -y linux-headers-$(uname -r) linux-image-$(uname -r)
        - mkdir -p /opt/i915-sriov && cd /opt/i915-sriov
        - wget https://github.com/strongtz/i915-sriov-dkms/releases/download/2025.01.22/i915-sriov-dkms_2025.01.22_amd64.deb
        - apt install -y ./i915-sriov-dkms_2025.01.22_amd64.deb
        - update-grub
        - update-initramfs -u
        - echo "done" > /tmp/cloud-config.done




        
    EOF

    file_name = "user-data-cloud-config.yaml"
  }
}
