#data "external" "password_hash" {
#  program = [
#    "sh", "-c", 
#    "echo '{\"password\": \"'$(openssl passwd -6 \"${local.vm_password}\")'\"}'"
#  ]
#}
#
#locals {
#  vm_password_hashed = trimspace(data.external.password_hash.result["password"])
#}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "resources"
  node_name    = "pve01"

source_raw {
  file_name = "user-data-cloud-config.yaml"
  data = <<-EOF
    #cloud-config
    preserve_hostname: false
    
    users:
      - default
      - name: debian
#        passwd: ${local.vm_password_hashed}
        groups: sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
        
    
      - name: root
#        passwd: ${local.vm_password_hashed}
        shell: /bin/bash
        lock_passwd: false
        ssh_authorized_keys:
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com
    
    ssh_pwauth: true
    
      #package_update: true
      #package_upgrade: true
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
    
    runcmd:
    #  - sysctl -w net.ipv6.conf.all.disable_ipv6=1  # Disable IPv6 temporarily
    #  - apt-get update -o Acquire::ForceIPv4=true
      - apt-get upgrade -y
      - apt-get install -y linux-headers-$(uname -r) linux-image-$(uname -r)
      - timedatectl set-timezone America/Los_Angeles
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo 'blacklist xe' >> /etc/modprobe.d/blacklist.conf
      - echo 'options i915 enable_guc=3' > /etc/modprobe.d/i915.conf
      - apt-get update
      - apt-get upgrade -y
      - dpkg --configure -a
      - apt install -f -y
      - mkdir -p /opt/i915-sriov && cd /opt/i915-sriov
      - wget https://github.com/strongtz/i915-sriov-dkms/releases/download/2025.01.22/i915-sriov-dkms_2025.01.22_amd64.deb
      - apt install -y ./i915-sriov-dkms_2025.01.22_amd64.deb
      - update-grub
      - update-initramfs -u
    #  - sysctl -w net.ipv6.conf.all.disable_ipv6=0  # Re-enable IPv6
      - echo "done" > /tmp/cloud-config.done
    
    power_state:
      mode: reboot
      message: "Reboot triggered by cloud-init after package installation"
      timeout: 30
      condition: true
    EOF

    file_name = "user-data-cloud-config.yaml"
  }
}
