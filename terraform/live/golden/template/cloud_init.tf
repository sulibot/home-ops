resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "resources"
  node_name    = var.node_name

  source_raw {
    file_name = "debian13-template-user-data.yaml"
    data = <<-EOF
#cloud-config
preserve_hostname: false
ssh_pwauth: true
disable_root: false
manage_etc_hosts: true
timezone: America/Los_Angeles
locale: en_US.UTF-8
ssh_deletekeys: true
ssh_genkeytypes: ['rsa', 'ed25519']

output:
  all: '| tee -a /var/log/cloud-init-template.log'

package_update: true
package_upgrade: true

system_info:
  network:
    renderers: ['netplan']

apt:
  preserve_sources_list: true
  conf: |
    Dpkg::Options {
      "--force-confdef";
      "--force-confold";
    };

chpasswd:
  list:
    - debian:${var.vm_password}
    - root:${var.vm_password}
    - sulibot:${var.vm_password}
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
  - name: sulibot
    lock_passwd: false
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com
    sudo: ALL=(ALL) NOPASSWD:ALL

write_files:
  - path: /etc/apt/sources.list.d/99-backports.list
    permissions: "0644"
    owner: root:root
    content: |
      deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware

  - path: /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
    permissions: "0644"
    owner: root:root
    content: |
      [Service]
      ExecStart=
      ExecStart=/lib/systemd/systemd-networkd-wait-online --timeout=20 --any

  - path: /etc/sysctl.d/99-template-performance.conf
    permissions: "0644"
    owner: root:root
    content: |
      # Performance tuning for VM template
      vm.swappiness = 10
      vm.dirty_ratio = 15
      vm.dirty_background_ratio = 5
      net.core.rmem_max = 16777216
      net.core.wmem_max = 16777216

  - path: /etc/sysctl.d/99-security.conf
    permissions: "0644"
    owner: root:root
    content: |
      # IP spoofing protection
      net.ipv4.conf.all.rp_filter = 1
      net.ipv4.conf.default.rp_filter = 1
      
      # Ignore ICMP redirects
      net.ipv4.conf.all.accept_redirects = 0
      net.ipv6.conf.all.accept_redirects = 0
      
      # Ignore send redirects
      net.ipv4.conf.all.send_redirects = 0
      
      # Disable source packet routing
      net.ipv4.conf.all.accept_source_route = 0
      net.ipv6.conf.all.accept_source_route = 0
      
      # Log Martians
      net.ipv4.conf.all.log_martians = 1

  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    permissions: "0644"
    owner: root:root
    content: |
      PermitRootLogin prohibit-password
      PasswordAuthentication no
      ChallengeResponseAuthentication no
      UsePAM yes
      X11Forwarding no
      PrintMotd no
      AcceptEnv LANG LC_*
      ClientAliveInterval 300
      ClientAliveCountMax 2
      Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
      MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
      KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

  - path: /etc/chrony/chrony.conf
    permissions: "0644"
    owner: root:root
    content: |
      # Chrony configuration for Kubernetes
      # Use multiple reliable time sources
      pool time.cloudflare.com iburst maxsources 4
      pool time.google.com iburst maxsources 4
      pool pool.ntp.org iburst maxsources 4
      
      # Record rate at which system clock gains/losses time
      driftfile /var/lib/chrony/drift
      
      # Allow system clock to be stepped in first three updates if offset > 1s
      makestep 1.0 3
      
      # Enable kernel synchronization of RTC
      rtcsync
      
      # Serve time to local network (for K8s pods)
      allow 10.0.0.0/8
      allow fc00::/7
      allow fd00::/8
      
      # Log statistics
      logdir /var/log/chrony
      log measurements statistics tracking

  - path: /etc/logrotate.d/custom-logs
    permissions: "0644"
    owner: root:root
    content: |
      /var/log/cloud-init-template.log
      /var/log/sriov-install.log {
          daily
          rotate 7
          compress
          missingok
          notifempty
          create 0644 root root
      }

  - path: /etc/modules-load.d/98-k8s-modules.conf
    permissions: "0644"
    owner: root:root
    content: |
      # Kubernetes/SR-IOV Modules
      overlay
      br_netfilter
      i915

  - path: /etc/sysctl.d/99-kubernetes.conf
    permissions: "0644"
    owner: root:root
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

  - path: /etc/containerd/config.toml
    permissions: "0644"
    owner: root:root
    content: |
      version = 2
      
      [plugins."io.containerd.grpc.v1.cri"]
        sandbox_image = "registry.k8s.io/pause:3.9"
      
      [plugins."io.containerd.grpc.v1.cri".containerd]
        snapshotter = "overlayfs"
        default_runtime_name = "runc"
      
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
      
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true

  - path: /etc/sriov-config
    permissions: "0644"
    owner: root:root
    content: |
      SRIOV_VERSION="2025.07.22"
      SRIOV_REPO_URL="https://github.com/strongtz/i915-sriov-dkms"
      
  - path: /etc/modprobe.d/i915-sriov.conf
    permissions: "0644"
    owner: root:root
    content: |
      blacklist xe
      options i915 enable_guc=3
      options i915 max_vfs=7

  - path: /usr/local/bin/install-sriov.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      set -e
      
      source /etc/sriov-config
      LOG_FILE="/var/log/sriov-install.log"
      
      log() {
          echo "$$(date -Iseconds) - $$*" | tee -a "$$LOG_FILE"
      }
      
      check_current_version() {
          if dkms status | grep -q "i915-sriov"; then
              dkms status | grep "i915-sriov" | cut -d',' -f2 | cut -d':' -f1 | tr -d ' '
          else
              echo "none"
          fi
      }
      
      remove_old_version() {
          local old_ver="$$1"
          if [ "$$old_ver" = "none" ]; then
              return 0
          fi
          
          log "Removing old SR-IOV version: $$old_ver"
          dkms remove i915-sriov-dkms/"$$old_ver" --all || true
          dpkg -P i915-sriov-dkms || true
      }
      
      download_package() {
          local version="$$1"
          local deb_file="i915-sriov-dkms_$${version}_amd64.deb"
          local download_url="$${SRIOV_REPO_URL}/releases/download/$${version}/$$deb_file"
          local temp_file="/tmp/$$deb_file"
          
          log "Downloading SR-IOV package version: $$version"
          
          local attempt=1
          local max_attempts=3
          local download_success=0
          
          while [ $$attempt -le $$max_attempts ]; do
              log "Download attempt $$attempt/$$max_attempts"
              
              if wget -O "$$temp_file" "$$download_url" 2>&1 | tee -a "$$LOG_FILE"; then
                  log "Download successful"
                  download_success=1
                  break
              fi
              
              log "Download failed on attempt $$attempt"
              
              if [ $$attempt -eq $$max_attempts ]; then
                  log "ERROR: Failed to download after $$max_attempts attempts"
                  return 1
              fi
              
              sleep 5
              attempt=$$((attempt + 1))
          done
          
          if [ $$download_success -eq 0 ]; then
              log "ERROR: Download never succeeded"
              return 1
          fi
          
          if [ ! -f "$$temp_file" ]; then
              log "ERROR: Downloaded file does not exist"
              return 1
          fi
          
          if [ ! -s "$$temp_file" ]; then
              log "ERROR: Downloaded file is empty"
              return 1
          fi
          
          log "Download verification passed"
          return 0
      }
      
      install_dkms_package() {
          local version="$$1"
          local deb_file="i915-sriov-dkms_$${version}_amd64.deb"
          local temp_file="/tmp/$$deb_file"
          
          log "Installing DKMS package"
          
          if dpkg -i "$$temp_file" 2>&1 | tee -a "$$LOG_FILE"; then
              log "Package installed successfully"
          else
              log "dpkg failed, fixing dependencies"
              apt-get install -f -y 2>&1 | tee -a "$$LOG_FILE"
              
              if dpkg -i "$$temp_file" 2>&1 | tee -a "$$LOG_FILE"; then
                  log "Package installed after fixing dependencies"
              else
                  log "ERROR: Failed to install package"
                  return 1
              fi
          fi
          
          return 0
      }
      
      build_dkms_module() {
          local version="$$1"
          local kernel_ver=$$(uname -r)
          
          log "Building DKMS module for kernel: $$kernel_ver"
          
          if dkms autoinstall -k "$$kernel_ver" 2>&1 | tee -a "$$LOG_FILE"; then
              log "DKMS autoinstall succeeded"
              return 0
          fi
          
          log "DKMS autoinstall failed, attempting recovery"
          apt-get update 2>&1 | tee -a "$$LOG_FILE"
          apt-get install -y linux-headers-generic 2>&1 | tee -a "$$LOG_FILE" || true
          
          if dkms autoinstall -k "$$kernel_ver" 2>&1 | tee -a "$$LOG_FILE"; then
              log "DKMS autoinstall succeeded after installing headers"
              return 0
          fi
          
          log "Second autoinstall failed, trying manual build"
          
          if dkms build i915-sriov-dkms/"$$version" -k "$$kernel_ver" 2>&1 | tee -a "$$LOG_FILE"; then
              log "Manual DKMS build succeeded"
          else
              log "ERROR: Manual DKMS build failed"
              return 1
          fi
          
          if dkms install i915-sriov-dkms/"$$version" -k "$$kernel_ver" 2>&1 | tee -a "$$LOG_FILE"; then
              log "Manual DKMS install succeeded"
          else
              log "ERROR: Manual DKMS install failed"
              return 1
          fi
          
          return 0
      }
      
      verify_installation() {
          log "Verifying DKMS installation"
          
          depmod -a
          
          if dkms status | grep -q "i915-sriov.*installed"; then
              log "SUCCESS: SR-IOV DKMS installed and verified"
              return 0
          fi
          
          log "ERROR: DKMS installation verification failed"
          dkms status | tee -a "$$LOG_FILE"
          return 1
      }
      
      install_sriov() {
          local version="$$1"
          local deb_file="i915-sriov-dkms_$${version}_amd64.deb"
          local temp_file="/tmp/$$deb_file"
          
          if ! download_package "$$version"; then
              return 1
          fi
          
          if ! install_dkms_package "$$version"; then
              return 1
          fi
          
          if ! build_dkms_module "$$version"; then
              return 1
          fi
          
          if ! verify_installation; then
              return 1
          fi
          
          rm -f "$$temp_file"
          log "SR-IOV installation completed successfully"
          return 0
      }
      
      ensure_kernel_headers() {
          local kernel_ver=$$(uname -r)
          
          if [ -d "/lib/modules/$$kernel_ver/build" ]; then
              log "Kernel headers already present"
              return 0
          fi
          
          log "Installing kernel headers for $$kernel_ver"
          apt-get update 2>&1 | tee -a "$$LOG_FILE"
          
          if apt-get install -y "linux-headers-$$kernel_ver" 2>&1 | tee -a "$$LOG_FILE"; then
              log "Installed specific kernel headers"
              return 0
          fi
          
          log "Specific headers not available, trying generic"
          
          if apt-get install -y linux-headers-amd64 2>&1 | tee -a "$$LOG_FILE"; then
              log "Installed generic kernel headers"
              return 0
          fi
          
          log "ERROR: Failed to install kernel headers"
          return 1
      }
      
      main() {
          log "========================================="
          log "Starting SR-IOV installation script"
          log "========================================="
          
          if ! command -v dkms >/dev/null 2>&1; then
              log "ERROR: DKMS not installed"
              exit 1
          fi
          
          if ! ensure_kernel_headers; then
              exit 1
          fi
          
          local current_version=$$(check_current_version)
          log "Current SR-IOV version: $$current_version"
          log "Target SR-IOV version: $$SRIOV_VERSION"
          
          if [ "$$current_version" = "$$SRIOV_VERSION" ]; then
              log "SR-IOV version $$SRIOV_VERSION already installed"
          else
              remove_old_version "$$current_version"
              
              if ! install_sriov "$$SRIOV_VERSION"; then
                  log "ERROR: SR-IOV installation failed"
                  exit 1
              fi
          fi
          
          log "Testing i915 module load"
          if modprobe i915 2>&1 | tee -a "$$LOG_FILE"; then
              log "i915 module loaded successfully"
              lsmod | grep i915 | tee -a "$$LOG_FILE"
          else
              log "Note: i915 module load failed (may require reboot)"
          fi
          
          log "========================================="
          log "SR-IOV installation script completed"
          log "========================================="
      }
      
      main "$$@"

  - path: /usr/local/bin/update-sriov.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      if [ -n "$$1" ]; then
          sed -i "s/SRIOV_VERSION=.*/SRIOV_VERSION=\"$$1\"/" /etc/sriov-config
          echo "Updated SR-IOV target version to: $$1"
      fi
      /usr/local/bin/install-sriov.sh

  - path: /usr/local/bin/verify-template-ready.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      # Template readiness verification script
      
      echo "=== Template Readiness Check ==="
      
      EXIT_CODE=0
      
      # Check SR-IOV drivers
      if dkms status | grep -q "i915-sriov.*installed"; then
        echo "✓ SR-IOV drivers: INSTALLED"
      else
        echo "✗ SR-IOV drivers: NOT FOUND"
        EXIT_CODE=1
      fi
      
      # Check DKMS service
      if systemctl is-enabled dkms.service 2>&1 | grep -q "masked"; then
        echo "✓ DKMS service: DISABLED"
      else
        echo "✗ DKMS service: NOT DISABLED"
        EXIT_CODE=1
      fi
      
      # Check module files
      KERNEL_VER=$$(uname -r)
      if [ -d "/lib/modules/$$KERNEL_VER/updates/dkms" ] && ls /lib/modules/$$KERNEL_VER/updates/dkms/i915*.ko >/dev/null 2>&1; then
        echo "✓ Module files: PRESENT"
      else
        echo "✗ Module files: MISSING"
        EXIT_CODE=1
      fi
      
      # Check GRUB
      if grep -q "intel_iommu=on" /etc/default/grub; then
        echo "✓ GRUB config: CONFIGURED"
      else
        echo "✗ GRUB config: NOT CONFIGURED"
        EXIT_CODE=1
      fi
      
      # Check qemu-guest-agent
      if systemctl is-active qemu-guest-agent >/dev/null 2>&1; then
        echo "✓ Guest agent: RUNNING"
      else
        echo "✗ Guest agent: NOT RUNNING"
        EXIT_CODE=1
      fi
      
      # Check containerd
      if systemctl is-enabled containerd >/dev/null 2>&1; then
        echo "✓ Containerd: ENABLED"
      else
        echo "✗ Containerd: NOT ENABLED"
        EXIT_CODE=1
      fi
      
      # Check chrony
      if systemctl is-active chrony >/dev/null 2>&1; then
        echo "✓ Time sync (chrony): ACTIVE"
        # Check time synchronization status
        if chronyc tracking 2>/dev/null | grep -q "Normal\|Leap status"; then
          echo "  ✓ Clock synchronized"
        fi
      else
        echo "✗ Time sync (chrony): NOT ACTIVE"
        EXIT_CODE=1
      fi
      
      # Verify systemd-timesyncd is disabled
      if systemctl is-enabled systemd-timesyncd 2>&1 | grep -q "masked\|disabled"; then
        echo "✓ systemd-timesyncd: DISABLED (correct for K8s)"
      else
        echo "⚠ systemd-timesyncd: NOT DISABLED (conflicts with chrony)"
      fi
      
      echo "==========================="
      
      if [ $$EXIT_CODE -eq 0 ]; then
        echo "Template is ready for conversion"
      else
        echo "Template has issues that need attention"
      fi
      
      exit $$EXIT_CODE

  - path: /usr/local/bin/check-k8s-time-sync.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      # Check if time synchronization is adequate for Kubernetes
      
      echo "=== Kubernetes Time Sync Check ==="
      
      # Check chrony is running
      if ! systemctl is-active chrony >/dev/null 2>&1; then
        echo "✗ CRITICAL: chrony is not running"
        exit 1
      fi
      
      # Check time source availability
      sources=$$(chronyc sources 2>/dev/null | grep -c "^\^\*")
      if [ "$$sources" -eq 0 ]; then
        echo "✗ WARNING: No synchronized time sources"
        chronyc sources
        exit 1
      fi
      
      echo "✓ Chrony is running with $$sources synchronized source(s)"
      
      # Check offset (should be < 500ms for K8s)
      offset=$$(chronyc tracking 2>/dev/null | grep "System time" | awk '{print $$4}')
      if [ -n "$$offset" ]; then
        # Convert to milliseconds (handle scientific notation)
        offset_ms=$$(echo "$$offset * 1000" | bc 2>/dev/null | cut -d. -f1)
        
        if [ -n "$$offset_ms" ] && [ "$$offset_ms" -lt 500 ] 2>/dev/null; then
          echo "✓ Time offset acceptable: $${offset}s ($${offset_ms}ms)"
        else
          echo "⚠ Time offset: $${offset}s"
          echo "  Note: K8s requires offset < 500ms for optimal operation"
        fi
      fi
      
      # Show current status
      echo ""
      echo "Current time sources:"
      chronyc sources -v
      
      echo ""
      echo "Tracking status:"
      chronyc tracking

bootcmd:
  - sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' /etc/locale.gen
  - locale-gen
  - update-locale LANG=en_US.UTF-8
  - modprobe overlay
  - modprobe br_netfilter

packages:
  - build-essential
  - dkms
  - linux-headers-amd64
  - curl
  - wget
  - bind9-dnsutils
  - gzip
  - htop
  - iproute2
  - iputils-ping
  - locales
  - lsof
  - make
  - mc
  - net-tools
  - netplan.io
  - openssl
  - parted
  - procps
  - rsync
  - strace
  - sysstat
  - tar
  - unzip
  - util-linux
  - btrfs-progs
  - e2fsprogs
  - lvm2
  - smartmontools
  - xfsprogs
  - nvme-cli
  - hdparm
  - fio
  - iotop
  - inxi
  - pv
  - bpfcc-tools
  - ethtool
  - frr
  - iperf3
  - iperf
  - mtr-tiny
  - ndisc6
  - tcpdump
  - traceroute
  - nmap
  - sipcalc
  - whois
  - netcat-openbsd
  - bridge-utils
  - nftables
  - freeradius-utils
  - containerd
  - qemu-guest-agent
  - clinfo
  - ocl-icd-libopencl1
  - intel-gpu-tools
  - usbutils
  - pciutils
  - lshw
  - git
  - gnupg
  - jq
  - bash-completion
  - tmux
  - chrony
  - arping
  - bc

runcmd:
  - echo "Template cloud-init started" >> /var/log/cloud-init-template.log
  - date >> /var/log/cloud-init-template.log
  - apt-get install -y netplan.io || true
  - apt-get purge -y ifupdown ifupdown2 || true
  - apt-get update -o Acquire::ForceIPv4=true
  - DEBIAN_FRONTEND=noninteractive apt-get -y install openssh-server
  - DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
  - DEBIAN_FRONTEND=noninteractive apt-get -y install linux-headers-$(uname -r) || true
  - systemctl enable ssh
  - systemctl restart ssh
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent || true
  - systemctl add-wants multi-user.target qemu-guest-agent.service || true
  - systemctl disable frr || true
  - echo "Configuring time synchronization for Kubernetes" >> /var/log/cloud-init-template.log
  - systemctl stop systemd-timesyncd || true
  - systemctl disable systemd-timesyncd || true
  - systemctl mask systemd-timesyncd || true
  - systemctl enable chrony
  - systemctl start chrony
  - sleep 5
  - chronyc makestep || true
  - systemctl enable containerd
  - systemctl restart containerd
  - echo "Installing SR-IOV" >> /var/log/cloud-init-template.log
  - date >> /var/log/cloud-init-template.log
  - /usr/local/bin/install-sriov.sh
  - echo "Disabling DKMS service (drivers pre-built in template)" >> /var/log/cloud-init-template.log
  - systemctl disable dkms.service
  - systemctl mask dkms.service
  - echo "Configuring GRUB" >> /var/log/cloud-init-template.log
  - date >> /var/log/cloud-init-template.log
  - |
    if ! grep -q "intel_iommu=on" /etc/default/grub; then
      sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on i915.enable_guc=3 /' /etc/default/grub
      update-grub
    fi
  - echo "GRUB configured and updated" >> /var/log/cloud-init-template.log
  - touch /tmp/golden-cloud-config.done
EOF
  }
}