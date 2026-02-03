#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

users:
  - name: debian
    groups: sudo, frr, frrvty
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    passwd: $6$rounds=4096$saltsalt$N8YMmLxkpW7oSbZ3Q4Kh6p5FqJpPH7mD7cPnTk8nJwLm0v2xH7rK8L4V3M2Y9N6W5X4Z3A2S1D0F9G8H7J6K5
    lock_passwd: false
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

chpasswd:
  expire: false
  list:
    - debian:debian
    - root:debian

package_update: true
package_upgrade: true

packages:
  - frr
  - frr-pythontools
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
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: |
      network: {config: disabled}
    owner: root:root
    permissions: '0644'

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

  - path: /etc/frr/daemons
    content: |
      zebra=yes
      bgpd=yes
      bgpd_options=" -p 1790"
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
  - path: /etc/frr/frr.conf
    content: |
      ! FRR Configuration for ${hostname} (TALOS PATTERN - Host netns, loopback peering)
      frr version 10.2
      frr defaults datacenter
      hostname ${hostname}
      log syslog informational
      service integrated-vtysh-config
      !
      bfd
       profile normal
        detect-multiplier 3
        receive-interval 300
        transmit-interval 300
       exit
      exit
      !
      ! Prefix lists for Cilium routes
      ip prefix-list CILIUM-ALL-v4 seq 10 permit 0.0.0.0/0 le 32
      ipv6 prefix-list CILIUM-ALL-v6 seq 10 permit ::/0 le 128
      !
      ! Route maps for Cilium import (accept all Cilium routes)
      route-map IMPORT-FROM-CILIUM-v4 permit 10
       match ip address prefix-list CILIUM-ALL-v4
       set ip next-hop ${network.ipv4_gateway}
      exit
      !
      route-map IMPORT-FROM-CILIUM-v6 permit 10
       match ipv6 address prefix-list CILIUM-ALL-v6
       set ipv6 next-hop global ${network.ipv6_gateway}
      exit
      !
      ! Upstream route filtering
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
%{ if loopback != null ~}
      ! Loopback prefix-lists (FRR IP + GoBGP IP + LoadBalancer IPs)
      ip prefix-list LOOPBACK-v4 seq 10 permit ${loopback.ipv4}/32
      ip prefix-list LOOPBACK-v4 seq 20 permit ${replace(loopback.ipv4, "254.", "253.")}/32
      ip prefix-list LOOPBACK-v4 seq 30 permit ${replace(loopback.ipv4, "254.", "250.")}/32
      ipv6 prefix-list LOOPBACK-v6 seq 10 permit ${loopback.ipv6}/128
      ipv6 prefix-list LOOPBACK-v6 seq 20 permit ${replace(loopback.ipv6, "fe::", "fd::")}/128
      ipv6 prefix-list LOOPBACK-v6 seq 30 permit ${replace(loopback.ipv6, "fe::", "250::")}/128
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
       ! FRR listens on port 1790, GoBGP connects TO FRR
       !
       ! Cilium peer-group (GoBGP connects to FRR:1790)
       neighbor CILIUM peer-group
       neighbor CILIUM remote-as ${frr_config.local_asn + 10000000}
       neighbor CILIUM description Cilium-BGP-Control-Plane
       !
       ! Dynamic neighbors - accept GoBGP connections from dummy0 IPs
       bgp listen range ${replace(loopback.ipv4, "254.", "253.")}/32 peer-group CILIUM
       bgp listen range ${replace(loopback.ipv6, "fe::", "fd::")}/128 peer-group CILIUM
       !
       ! Upstream neighbor (PVE gateway) - bind to FRR loopback
       neighbor ${frr_config.upstream_peer} remote-as ${frr_config.upstream_asn}
       neighbor ${frr_config.upstream_peer} description PVE-ULA-Gateway
       neighbor ${frr_config.upstream_peer} capability extended-nexthop
       neighbor ${frr_config.upstream_peer} bfd profile normal
       neighbor ${frr_config.upstream_peer} update-source ${loopback.ipv6}
       !
       address-family ipv4 unicast
        neighbor CILIUM activate
        neighbor CILIUM route-map IMPORT-FROM-CILIUM-v4 in
        neighbor ${frr_config.upstream_peer} activate
        neighbor ${frr_config.upstream_peer} route-map IMPORT-DEFAULT-v4 in
        redistribute connected route-map LOOPBACKS-v4
       exit-address-family
       !
       address-family ipv6 unicast
        neighbor CILIUM activate
        neighbor CILIUM route-map IMPORT-FROM-CILIUM-v6 in
        neighbor CILIUM capability extended-nexthop
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

  - path: /etc/gobgpd-cilium.conf
    content: |
      [global.config]
        as = ${frr_config.local_asn + 10000000}
        router-id = "${replace(loopback.ipv4, "254.", "253.")}"
        local-address-list = ["${replace(loopback.ipv4, "254.", "253.")}", "${replace(loopback.ipv6, "fe::", "fd::")}"]
        port = -1

      # GoBGP connects TO FRR at port 1790 (active peering)

      [[neighbors]]
        [neighbors.config]
          neighbor-address = "${loopback.ipv4}"
          peer-as = ${frr_config.local_asn}
        [neighbors.transport.config]
          local-address = "${replace(loopback.ipv4, "254.", "253.")}"
          remote-port = 1790

      [[neighbors]]
        [neighbors.config]
          neighbor-address = "${loopback.ipv6}"
          peer-as = ${frr_config.local_asn}
        [neighbors.transport.config]
          local-address = "${replace(loopback.ipv6, "fe::", "fd::")}"
          remote-port = 1790

      # Advertise LoadBalancer IPs (simulates Cilium behavior)
      [[defined-sets.prefix-sets]]
        prefix-set-name = "lb-ipv4"
        [[defined-sets.prefix-sets.prefix-list]]
          ip-prefix = "${replace(loopback.ipv4, "254.", "250.")}/32"

      [[defined-sets.prefix-sets]]
        prefix-set-name = "lb-ipv6"
        [[defined-sets.prefix-sets.prefix-list]]
          ip-prefix = "${replace(loopback.ipv6, "fe::", "250::")}/128"

      [[policy-definitions]]
        name = "advertise-lb"
        [[policy-definitions.statements]]
          name = "accept-lb-ipv4"
          [policy-definitions.statements.conditions.match-prefix-set]
            prefix-set = "lb-ipv4"
            match-set-options = "any"
          [policy-definitions.statements.actions]
            route-disposition = "accept-route"

        [[policy-definitions.statements]]
          name = "accept-lb-ipv6"
          [policy-definitions.statements.conditions.match-prefix-set]
            prefix-set = "lb-ipv6"
            match-set-options = "any"
          [policy-definitions.statements.actions]
            route-disposition = "accept-route"

      [global.apply-policy.config]
        export-policy-list = ["advertise-lb"]
    owner: root:root
    permissions: '0644'

  - path: /etc/systemd/system/gobgpd-cilium.service
    content: |
      [Unit]
      Description=GoBGP daemon (simulates Cilium BGP in host netns)
      After=frr.service
      Requires=frr.service

      [Service]
      Type=simple
      ExecStart=/usr/bin/gobgpd -f /etc/gobgpd-cilium.conf --disable-stdlog --syslog yes
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'

  - path: /etc/systemd/system/gobgp-inject-lb.service
    content: |
      [Unit]
      Description=Inject LoadBalancer routes into GoBGP (simulates Cilium)
      After=gobgpd-cilium.service
      Requires=gobgpd-cilium.service

      [Service]
      Type=oneshot
      ExecStartPre=/bin/sleep 3
      ExecStart=/usr/bin/gobgp global rib add -a ipv4 ${replace(loopback.ipv4, "254.", "250.")}/32 nexthop ${replace(loopback.ipv4, "254.", "253.")}
      ExecStart=/usr/bin/gobgp global rib add -a ipv6 ${replace(loopback.ipv6, "fe::", "250::")}/128 nexthop ${replace(loopback.ipv6, "fe::", "fd::")}
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'
%{ endif ~}

runcmd:
  - sysctl -p /etc/sysctl.d/99-evpn-notify.conf

%{ if loopback != null ~}
  # Create dummy interface for loopback addresses
  - ip link add dummy0 type dummy
  - ip link set dummy0 up

  # FRR Host ID IP on dummy0 (.254 - k8s node IP)
  - ip addr add ${loopback.ipv4}/32 dev dummy0
  - ip addr add ${loopback.ipv6}/128 dev dummy0

  # GoBGP/Cilium IP on dummy0 (.253)
  - ip addr add ${replace(loopback.ipv4, "254.", "253.")}/32 dev dummy0
  - ip addr add ${replace(loopback.ipv6, "fe::", "fd::")}/128 dev dummy0

  # LoadBalancer IPs on dummy0 (.250 - simulates Cilium LB-IPAM)
  - ip addr add ${replace(loopback.ipv4, "254.", "250.")}/32 dev dummy0
  - ip addr add ${replace(loopback.ipv6, "fe::", "250::")}/128 dev dummy0
%{ endif ~}

  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

%{ if frr_enabled && frr_config != null ~}
  - systemctl enable frr
  - systemctl start frr
  - sleep 5
  - systemctl daemon-reload
  - systemctl enable gobgpd-cilium
  - systemctl start gobgpd-cilium
  - sleep 3
  - systemctl enable gobgp-inject-lb
  - systemctl start gobgp-inject-lb
  - sleep 2
  - echo "=== FRR BGP Summary ===" && vtysh -c "show bgp summary" || true
  - echo "=== GoBGP Neighbor ===" && gobgp neighbor || true
  - echo "=== GoBGP Advertised Routes (IPv4) ===" && gobgp global rib -a ipv4 || true
  - echo "=== GoBGP Advertised Routes (IPv6) ===" && gobgp global rib -a ipv6 || true
  - echo "=== FRR Routes from Cilium (IPv4) ===" && vtysh -c "show bgp ipv4 unicast neighbors ${replace(loopback.ipv4, "254.", "253.")} received-routes" || true
  - echo "=== FRR Routes from Cilium (IPv6) ===" && vtysh -c "show bgp ipv6 unicast neighbors ${replace(loopback.ipv6, "fe::", "fd::")} received-routes" || true
%{ endif ~}

final_message: "Debian FRR test VM ${hostname} ready (Talos pattern, host netns) after $UPTIME seconds"
