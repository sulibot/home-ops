#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

users:
  - name: debian
    groups: sudo, frr, frrvty
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    # Password: debian (for console access)
    passwd: $6$rounds=4096$saltsalt$N8YMmLxkpW7oSbZ3Q4Kh6p5FqJpPH7mD7cPnTk8nJwLm0v2xH7rK8L4V3M2Y9N6W5X4Z3A2S1D0F9G8H7J6K5
    lock_passwd: false
%{ if ssh_public_key != "" ~}
    ssh_authorized_keys:
      - ${ssh_public_key}
%{ endif ~}

# Enable root SSH access with public key
%{ if ssh_public_key != "" ~}
ssh_authorized_keys:
  - ${ssh_public_key}
%{ endif ~}
disable_root: false
ssh_pwauth: false

# Set passwords for console access
chpasswd:
  expire: false
  list:
    - debian:debian
    - root:debian

package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose
  - gobgpd
  - qemu-guest-agent
  - curl
  - jq
  - vim
  - htop
  - tcpdump
  - iproute2
  - iputils-ping

write_files:
  # Disable cloud-init network management after first boot
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: |
      network: {config: disabled}
    owner: root:root
    permissions: '0644'

  # EVPN sysctl settings
  - path: /etc/sysctl.d/99-evpn-notify.conf
    content: |
      net.ipv6.conf.all.ndisc_notify=1
      net.ipv6.conf.default.ndisc_notify=1
      net.ipv4.conf.all.arp_notify=1
      net.ipv4.conf.default.arp_notify=1
      net.ipv4.ip_forward=1
      net.ipv6.conf.all.forwarding=1
    owner: root:root
    permissions: '0644'

%{ if frr_enabled && frr_config != null ~}
  # FRR extension config file (Talos format)
  # This file is mounted into the container at /etc/frr/frr.yaml
  - path: /var/lib/frr/frr.yaml
    content: |
      network:
        interface_mtu: 1450
        veth_names:
          frr_side: veth-frr
          cilium_side: veth-cilium

      bgp:
        local_asn: ${frr_config.local_asn}
        router_id: "${frr_config.router_id}"

%{ if frr_config.veth_enabled ~}
        # Cilium local peering configuration
        cilium:
          enabled: true
          namespace: ${frr_config.veth_namespace}
          peering:
            ipv4:
              local: "${frr_config.veth_ipv4_local}"
              remote: "${frr_config.veth_ipv4_remote}"
              prefix: 31
            ipv6:
              local: "${frr_config.veth_ipv6_local}"
              remote: "${frr_config.veth_ipv6_remote}"
              prefix: 126
%{ endif ~}

        # Upstream BGP peer configuration
        upstream:
          enabled: true
          peer_address: "${frr_config.upstream_peer}"
          peer_asn: ${frr_config.upstream_asn}
%{ if loopback != null ~}
          loopbacks:
            ipv4: "${loopback.ipv4}"
            ipv6: "${loopback.ipv6}"
%{ endif ~}
    owner: root:root
    permissions: '0644'

  # FRR extension container service (mimics Talos environment)
  - path: /etc/systemd/system/frr-container.service
    content: |
      [Unit]
      Description=FRR Extension Container (mimics Talos)
      After=docker.service
      Requires=docker.service

      [Service]
      Type=simple
      ExecStartPre=/usr/bin/docker pull ghcr.io/sulibot/frr-talos-extension:v1.1.25
      ExecStart=/usr/bin/docker run --rm \
        --name frr-extension \
        --privileged \
        --pid=host \
        -v /var/lib/frr:/etc/frr:rw \
        -v /var/run/frr:/tmp:rw \
        ghcr.io/sulibot/frr-talos-extension:v1.1.25
      ExecStop=/usr/bin/docker stop frr-extension
      Restart=always
      RestartSec=10

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'

  # Namespace diagnostic script for debugging
  - path: /usr/local/bin/debug-namespace.sh
    content: |
      #!/bin/bash
      # Interactive debugging of namespace operations

      echo "=== Container PID Info ==="
      CONTAINER_PID=$$(docker inspect -f '{{.State.Pid}}' frr-extension 2>/dev/null)
      if [ -z "$$CONTAINER_PID" ] || [ "$$CONTAINER_PID" = "0" ]; then
          echo "ERROR: FRR container not running"
          exit 1
      fi
      echo "FRR container PID: $$CONTAINER_PID"

      echo ""
      echo "=== Namespace Comparison ==="
      echo "Host (PID 1) network namespace:"
      readlink /proc/1/ns/net
      echo "Container network namespace:"
      readlink /proc/$$CONTAINER_PID/ns/net
      echo "Are they same? $$([ $$(readlink /proc/1/ns/net) = $$(readlink /proc/$$CONTAINER_PID/ns/net) ] && echo YES || echo NO)"

      echo ""
      echo "=== Veth Interfaces ==="
      echo "In host namespace:"
      ip link show | grep veth || echo "  No veth interfaces"

      echo ""
      echo "In container namespace:"
      nsenter -t $$CONTAINER_PID -n ip link show | grep veth || echo "  No veth interfaces"

      echo ""
      echo "=== Routing in Host Namespace ==="
      if ip addr show veth-cilium &>/dev/null; then
          CILIUM_IP=$$(ip addr show veth-cilium | grep "inet6.*fd00:65:c111" | awk '{print $$2}' | cut -d/ -f1)
          if [ -n "$$CILIUM_IP" ]; then
              echo "Testing route to Cilium peering IP ($$CILIUM_IP):"
              ip route get $$CILIUM_IP
          fi
      fi

      echo ""
      echo "=== Container Logs (last 20 lines) ==="
      docker logs --tail 20 frr-extension
    owner: root:root
    permissions: '0755'
%{ endif ~}

  # FRR daemons configuration
  - path: /etc/frr/daemons
    content: |
      zebra=yes
      bgpd=yes
      ospfd=no
      ospf6d=no
      ripd=no
      ripngd=no
      isisd=no
      pimd=no
      ldpd=no
      nhrpd=no
      eigrpd=no
      babeld=no
      sharpd=no
      pbrd=no
      bfdd=yes
      fabricd=no
      vrrpd=no
      pathd=no
    owner: root:root
    permissions: '0640'

%{ if frr_enabled && frr_config != null ~}
  # FRR BGP configuration
  - path: /etc/frr/frr.conf
    content: |
      ! FRR Configuration for ${hostname}
      ! Dual-stack BGP test setup
      !
      frr version 10.2
      frr defaults datacenter
      hostname ${hostname}
      log syslog informational
      service integrated-vtysh-config
      !
      ! BFD Configuration
      bfd
       profile normal
        detect-multiplier 3
        receive-interval 300
        transmit-interval 300
       exit
      exit
      !
%{ if frr_config.veth_enabled ~}
      ! ========================================
      ! MP-BGP Configuration for local Cilium peering
      ! Single IPv6 session carries both IPv4 and IPv6 routes
      ! Uses extended-nexthop capability (RFC 5549)
      ! ========================================
%{ endif ~}
      ! ========================================
      ! Upstream BGP peering (to RouterOS gateway)
      ! ========================================
      ip prefix-list DEFAULT-ONLY-v4 seq 10 permit 0.0.0.0/0
      ipv6 prefix-list DEFAULT-ONLY-v6 seq 10 permit ::/0
      !
      route-map IMPORT-DEFAULT-v4 permit 10
       match ip address prefix-list DEFAULT-ONLY-v4
      exit
      route-map IMPORT-DEFAULT-v4 deny 90
      exit
      !
      route-map IMPORT-DEFAULT-v6 permit 10
       match ipv6 address prefix-list DEFAULT-ONLY-v6
      exit
      route-map IMPORT-DEFAULT-v6 deny 90
      exit
      !
      ! ========================================
      ! Fix #1: IPv6 Loopback Redistribution
      ! Use address-family-aware prefix-lists instead of generic interface matching
      ! ========================================
%{ if loopback != null ~}
      ip prefix-list LOOPBACK-v4 seq 10 permit ${loopback.ipv4}/32
      ipv6 prefix-list LOOPBACK-v6 seq 10 permit ${loopback.ipv6}/128
%{ endif ~}
      !
      route-map LOOPBACKS-v4 permit 10
       match ip address prefix-list LOOPBACK-v4
      exit
      !
      route-map LOOPBACKS-v6 permit 10
       match ipv6 address prefix-list LOOPBACK-v6
      exit
      !
      router bgp ${frr_config.local_asn}
       bgp router-id ${frr_config.router_id}
       no bgp ebgp-requires-policy
       no bgp default ipv4-unicast
       bgp bestpath as-path multipath-relax
       timers bgp 10 30
       !
%{ if frr_config.veth_enabled ~}
       ! Local Cilium neighbor (MP-BGP over IPv6)
       neighbor ${frr_config.veth_ipv6_local} remote-as ${frr_config.local_asn}
       neighbor ${frr_config.veth_ipv6_local} description Cilium-MP-BGP
       neighbor ${frr_config.veth_ipv6_local} update-source veth-frr
       neighbor ${frr_config.veth_ipv6_local} capability extended-nexthop
       !
%{ endif ~}
       ! Upstream neighbor (RouterOS gateway)
       neighbor ${frr_config.upstream_peer} remote-as ${frr_config.upstream_asn}
       neighbor ${frr_config.upstream_peer} description RouterOS-ULA-Gateway
       neighbor ${frr_config.upstream_peer} capability extended-nexthop
       neighbor ${frr_config.upstream_peer} bfd profile normal
       !
       address-family ipv4 unicast
%{ if frr_config.veth_enabled ~}
        ! Cilium neighbor carries IPv4 routes over IPv6 session
        neighbor ${frr_config.veth_ipv6_local} activate
        neighbor ${frr_config.veth_ipv6_local} next-hop-self
%{ endif ~}
        neighbor ${frr_config.upstream_peer} activate
        neighbor ${frr_config.upstream_peer} route-map IMPORT-DEFAULT-v4 in
        redistribute connected route-map LOOPBACKS-v4
       exit-address-family
       !
       address-family ipv6 unicast
%{ if frr_config.veth_enabled ~}
        ! Cilium neighbor also carries IPv6 routes
        neighbor ${frr_config.veth_ipv6_local} activate
        neighbor ${frr_config.veth_ipv6_local} next-hop-self
%{ endif ~}
        neighbor ${frr_config.upstream_peer} activate
        neighbor ${frr_config.upstream_peer} route-map IMPORT-DEFAULT-v6 in
        redistribute connected route-map LOOPBACKS-v6
       exit-address-family
      exit
      !
      line vty
      !
    owner: root:root
    permissions: '0640'

%{ if frr_config.veth_enabled ~}
  # Veth setup script (mimics Talos FRR extension)
  - path: /usr/local/bin/setup-veth.sh
    content: |
      #!/bin/bash
      set -e

      NAMESPACE="${frr_config.veth_namespace}"
      VETH_FRR="veth-frr"
      VETH_CILIUM="veth-cilium"
      MTU=1450

      echo "[veth-setup] Starting veth pair configuration..."

      # Create namespace if not exists
      if ! ip netns list | grep -q "^$NAMESPACE\$"; then
        echo "[veth-setup] Creating network namespace: $NAMESPACE"
        ip netns add "$NAMESPACE"
      else
        echo "[veth-setup] Namespace $NAMESPACE already exists"
      fi

      # Create veth pair if not exists
      if ! ip link show "$VETH_FRR" &>/dev/null; then
        echo "[veth-setup] Creating veth pair: $VETH_CILIUM <-> $VETH_FRR"
        ip link add "$VETH_CILIUM" type veth peer name "$VETH_FRR"
        ip link set "$VETH_CILIUM" netns "$NAMESPACE"
      else
        echo "[veth-setup] Veth pair already exists"
      fi

      # Configure FRR side (host namespace)
      echo "[veth-setup] Configuring $VETH_FRR (FRR side) in host namespace"
      ip addr add ${frr_config.veth_ipv4_remote}/30 dev "$VETH_FRR" 2>/dev/null || echo "[veth-setup] IPv4 already assigned to $VETH_FRR"
      ip -6 addr add ${frr_config.veth_ipv6_remote}/126 dev "$VETH_FRR" 2>/dev/null || echo "[veth-setup] IPv6 already assigned to $VETH_FRR"
      ip link set "$VETH_FRR" mtu $MTU up

      # Configure Cilium side (namespace)
      echo "[veth-setup] Configuring $VETH_CILIUM (Cilium side) in namespace $NAMESPACE"
      ip netns exec "$NAMESPACE" ip addr add ${frr_config.veth_ipv4_local}/30 dev "$VETH_CILIUM" 2>/dev/null || echo "[veth-setup] IPv4 already assigned to $VETH_CILIUM"
      ip netns exec "$NAMESPACE" ip -6 addr add ${frr_config.veth_ipv6_local}/126 dev "$VETH_CILIUM" 2>/dev/null || echo "[veth-setup] IPv6 already assigned to $VETH_CILIUM"
      ip netns exec "$NAMESPACE" ip link set "$VETH_CILIUM" mtu $MTU up
      ip netns exec "$NAMESPACE" ip link set lo up

      echo "[veth-setup] Configuration complete:"
      echo "  $VETH_FRR (host):         ${frr_config.veth_ipv4_remote}/30, ${frr_config.veth_ipv6_remote}/126"
      echo "  $VETH_CILIUM (ns=$NAMESPACE): ${frr_config.veth_ipv4_local}/30, ${frr_config.veth_ipv6_local}/126"

      # Verify connectivity
      echo "[veth-setup] Testing connectivity..."
      if ip netns exec "$NAMESPACE" ping -c1 -W1 ${frr_config.veth_ipv4_remote} &>/dev/null; then
        echo "[veth-setup] IPv4 connectivity OK"
      else
        echo "[veth-setup] WARNING: IPv4 connectivity test failed"
      fi
      if ip netns exec "$NAMESPACE" ping6 -c1 -W1 ${frr_config.veth_ipv6_remote} &>/dev/null; then
        echo "[veth-setup] IPv6 connectivity OK"
      else
        echo "[veth-setup] WARNING: IPv6 connectivity test failed"
      fi
    owner: root:root
    permissions: '0755'

  # Systemd service for veth setup
  - path: /etc/systemd/system/veth-setup.service
    content: |
      [Unit]
      Description=Setup veth pair for BGP testing
      Before=frr.service
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/setup-veth.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'

  # GoBGP configuration (simulates Cilium BGP)
  - path: /etc/gobgpd-cilium.conf
    content: |
      [global.config]
        as = ${frr_config.local_asn}
        router-id = "${frr_config.veth_ipv4_local}"
        local-address-list = ["${frr_config.veth_ipv6_local}"]

      [[neighbors]]
        [neighbors.config]
          neighbor-address = "${frr_config.veth_ipv6_remote}"
          peer-as = ${frr_config.local_asn}

        [[neighbors.afi-safis]]
          [neighbors.afi-safis.config]
            afi-safi-name = "ipv4-unicast"

        [[neighbors.afi-safis]]
          [neighbors.afi-safis.config]
            afi-safi-name = "ipv6-unicast"
    owner: root:root
    permissions: '0644'

  # Systemd service for GoBGP in cilium namespace
  - path: /etc/systemd/system/gobgpd-cilium.service
    content: |
      [Unit]
      Description=GoBGP daemon in cilium namespace (simulates Cilium BGP)
      After=veth-setup.service frr.service
      Requires=veth-setup.service

      [Service]
      Type=simple
      ExecStart=/usr/bin/ip netns exec ${frr_config.veth_namespace} /usr/bin/gobgpd -f /etc/gobgpd-cilium.conf --disable-stdlog --syslog yes
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'

  # Test BGP peer script
  - path: /usr/local/bin/test-bgp-peer.sh
    content: |
      #!/bin/bash
      # Test MP-BGP connectivity and route exchange

      NAMESPACE="${frr_config.veth_namespace}"

      echo "=== MP-BGP Test for ${hostname} ==="
      echo ""
      echo "1. Veth pair status:"
      ip addr show veth-frr | grep -E "inet6?|state"
      ip netns exec "$NAMESPACE" ip addr show veth-cilium | grep -E "inet6?|state"
      echo ""
      echo "2. IPv6 connectivity test:"
      ip netns exec "$NAMESPACE" ping -6 -c3 ${frr_config.veth_ipv6_remote}
      echo ""
      echo "3. FRR BGP status:"
      vtysh -c "show bgp summary"
      echo ""
      echo "4. GoBGP status:"
      ip netns exec "$NAMESPACE" gobgp neighbor
      echo ""
      echo "5. Test route advertisement (IPv4):"
      ip netns exec "$NAMESPACE" gobgp global rib add 192.168.100.0/24
      sleep 2
      vtysh -c "show bgp ipv4 unicast 192.168.100.0/24"
      echo ""
      echo "6. Test route advertisement (IPv6):"
      ip netns exec "$NAMESPACE" gobgp global rib -a ipv6 add 2001:db8:100::/48
      sleep 2
      vtysh -c "show bgp ipv6 unicast 2001:db8:100::/48"
    owner: root:root
    permissions: '0755'
%{ endif ~}
%{ endif ~}

runcmd:
  # Apply sysctl settings
  - sysctl -p /etc/sysctl.d/99-evpn-notify.conf

%{ if loopback != null ~}
  # Configure loopback addresses for BGP
  - ip addr add ${loopback.ipv4}/32 dev lo
  - ip addr add ${loopback.ipv6}/128 dev lo
%{ endif ~}

  # Enable and start qemu-guest-agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

%{ if frr_enabled && frr_config != null ~}
  # Create FRR directories for container mounts
  - mkdir -p /var/lib/frr /var/run/frr
  - chmod 755 /var/lib/frr /var/run/frr

  # Enable and start Docker
  - systemctl enable docker
  - systemctl start docker

  # Pull FRR extension image
  - docker pull ghcr.io/sulibot/frr-talos-extension:v1.1.25

  # Start FRR container (mimics Talos environment)
  - systemctl daemon-reload
  - systemctl enable frr-container.service
  - systemctl start frr-container.service

  # Wait for container startup
  - sleep 10

  # Display container status and logs
  - echo "=== FRR Container Status ===" && docker ps -f name=frr-extension
  - echo "=== FRR Container Logs ===" && docker logs frr-extension || true

%{ if frr_config.veth_enabled ~}
  # Enable and start GoBGP in cilium namespace (simulates Cilium BGP)
  # NOTE: This will only work once veth namespace isolation is fixed
  - systemctl daemon-reload
  - systemctl enable gobgpd-cilium
  - systemctl start gobgpd-cilium || echo "GoBGP start failed (expected until veth works)"

  # Display namespace debugging info
  - echo "=== Namespace Debug Info ===" && /usr/local/bin/debug-namespace.sh || true
%{ endif ~}
%{ endif ~}

final_message: "Debian FRR test VM ${hostname} ready after $UPTIME seconds"
