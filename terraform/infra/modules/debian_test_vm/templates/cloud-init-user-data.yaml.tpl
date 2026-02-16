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
  - bird2
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

%{ if frr_enabled && frr_config != null ~}
  - path: /etc/bird/bird.conf
    content: |
      # bird2 BGP daemon configuration for ${hostname}
      # Router ID uses the loopback (.254)
      router id ${frr_config.router_id};

      # Logging
      log syslog all;

      # Device protocol - learns about network interfaces
      protocol device {
        scan time 10;
      }

      # Direct protocol - imports directly connected routes
      protocol direct {
        interface "dummy0", "lo";
        ipv4;
        ipv6;
      }

      # Kernel protocol for IPv4 - exports routes learned from upstream to kernel
      protocol kernel kernel_v4 {
        ipv4 {
          import none;
          export filter {
            if proto = "upstream" then accept;
            reject;
          };
        };
        merge paths on;
      }

      # Kernel protocol for IPv6 - exports routes learned from upstream to kernel
      protocol kernel kernel_v6 {
        ipv6 {
          import none;
          export filter {
            if proto = "upstream" then accept;
            reject;
          };
        };
        merge paths on;
      }

      # BFD protocol
      protocol bfd {
        interface "*" { multiplier 3; interval 300 ms; };
      }

      # BGP - GoBGP Cilium Simulation via localhost
      # bird2 is passive, GoBGP connects from ::1 (matching production Cilium pattern)
      protocol bgp cilium_sim {
        description "GoBGP Cilium Simulation";
        passive on;
        multihop 2;
        local as ${frr_config.local_asn};
        neighbor ::1 as ${frr_config.local_asn + 10000000};

        ipv4 {
          import all;
          export none;  # One-way: GoBGP -> bird2 (matches production)
          extended next hop on;
        };

        ipv6 {
          import all;
          export none;
        };
      }

      # BGP - Upstream Peering (PVE ULA Anycast Gateway / FRR)
      protocol bgp upstream {
        description "PVE ULA Anycast Gateway";
        local as ${frr_config.local_asn};
        source address ${network.ipv6_address};
        neighbor ${frr_config.upstream_peer} as ${frr_config.upstream_asn};
        bfd on;

        ipv4 {
          import all;
          export filter {
            # Tag routes from GoBGP (simulates Cilium) with Internal community
            if from = cilium_sim then {
              bgp_large_community.add((${frr_config.upstream_asn}, 0, 100));  # CL_K8S_INTERNAL
              accept;
            }
            # Tag Loopbacks (protocol direct) as Public community
            if from = direct1 then {
              bgp_large_community.add((${frr_config.upstream_asn}, 0, 200));  # CL_K8S_PUBLIC
              accept;
            }
            accept;
          };
          next hop self;
          extended next hop on;
        };

        ipv6 {
          import filter {
            # Reject the local node subnet - nodes use direct kernel routes
            if net ~ ${join(":", slice(split(":", network.ipv6_address), 0, 2))}::/64 then reject;
            accept;
          };
          export filter {
            # Tag routes from GoBGP (simulates Cilium) with Internal community
            if from = cilium_sim then {
              bgp_large_community.add((${frr_config.upstream_asn}, 0, 100));  # CL_K8S_INTERNAL
              accept;
            }
            # Tag Loopbacks (protocol direct) as Public community
            if from = direct1 then {
              bgp_large_community.add((${frr_config.upstream_asn}, 0, 200));  # CL_K8S_PUBLIC
              accept;
            }
            accept;
          };
          next hop self;
        };
      }
    owner: root:root
    permissions: '0644'

  - path: /etc/gobgpd-cilium.conf
    content: |
      [global.config]
        as = ${frr_config.local_asn + 10000000}
        router-id = "${frr_config.router_id}"
        local-address-list = ["::1"]
        port = -1

      # GoBGP connects TO bird2 at port 179 from ::1 (matches production Cilium pattern)

      [[neighbors]]
        [neighbors.config]
          neighbor-address = "::1"
          peer-as = ${frr_config.local_asn}
        [neighbors.transport.config]
          local-address = "::1"
          remote-port = 179

      # Define large communities (matching production)
      [[defined-sets.bgp-defined-sets.community-sets]]
        community-set-name = "CL_K8S_INTERNAL"
        community-list = ["${frr_config.upstream_asn}:0:100"]

      [[defined-sets.bgp-defined-sets.community-sets]]
        community-set-name = "CL_K8S_PUBLIC"
        community-list = ["${frr_config.upstream_asn}:0:200"]

      # Pod CIDR prefixes (simulates Cilium pod CIDR advertisements)
      # Use IPv6 addressing matching production: fd00:XXX:224:YY::/64
      [[defined-sets.prefix-sets]]
        prefix-set-name = "pod-cidrs"
        [[defined-sets.prefix-sets.prefix-list]]
          ip-prefix = "${replace(loopback.ipv6, ":fe::", ":224:")}::/64"

      # LoadBalancer IP prefixes (simulates Cilium LB-IPAM)
      [[defined-sets.prefix-sets]]
        prefix-set-name = "lb-ipv4"
        [[defined-sets.prefix-sets.prefix-list]]
          ip-prefix = "${replace(loopback.ipv4, "254.", "250.")}/32"

      [[defined-sets.prefix-sets]]
        prefix-set-name = "lb-ipv6"
        [[defined-sets.prefix-sets.prefix-list]]
          ip-prefix = "${replace(loopback.ipv6, ":fe::", ":254::")}/128"

      [[policy-definitions]]
        name = "advertise-routes"
        # Pod CIDRs with Internal community
        [[policy-definitions.statements]]
          name = "accept-pod-cidrs"
          [policy-definitions.statements.conditions.match-prefix-set]
            prefix-set = "pod-cidrs"
            match-set-options = "any"
          [policy-definitions.statements.actions]
            route-disposition = "accept-route"
            [policy-definitions.statements.actions.bgp-actions.set-community]
              options = "add"
              [policy-definitions.statements.actions.bgp-actions.set-community.set-community-method]
                communities-list = ["${frr_config.upstream_asn}:0:100"]

        # LoadBalancer IPs with Public community
        [[policy-definitions.statements]]
          name = "accept-lb-ipv4"
          [policy-definitions.statements.conditions.match-prefix-set]
            prefix-set = "lb-ipv4"
            match-set-options = "any"
          [policy-definitions.statements.actions]
            route-disposition = "accept-route"
            [policy-definitions.statements.actions.bgp-actions.set-community]
              options = "add"
              [policy-definitions.statements.actions.bgp-actions.set-community.set-community-method]
                communities-list = ["${frr_config.upstream_asn}:0:200"]

        [[policy-definitions.statements]]
          name = "accept-lb-ipv6"
          [policy-definitions.statements.conditions.match-prefix-set]
            prefix-set = "lb-ipv6"
            match-set-options = "any"
          [policy-definitions.statements.actions]
            route-disposition = "accept-route"
            [policy-definitions.statements.actions.bgp-actions.set-community]
              options = "add"
              [policy-definitions.statements.actions.bgp-actions.set-community.set-community-method]
                communities-list = ["${frr_config.upstream_asn}:0:200"]

      [global.apply-policy.config]
        export-policy-list = ["advertise-routes"]
    owner: root:root
    permissions: '0644'

  - path: /usr/local/bin/inject-gobgp-routes.sh
    content: |
      #!/bin/bash
      # Wait for GoBGP to be ready
      sleep 10
      # Inject pod CIDR and LoadBalancer routes into GoBGP RIB (simulates Cilium)
      while true; do
        gobgp global rib add -a ipv6 ${replace(loopback.ipv6, ":fe::", ":224:")}::/64 nexthop ${loopback.ipv6} 2>/dev/null && \
        gobgp global rib add -a ipv4 ${replace(loopback.ipv4, "254.", "250.")}/32 nexthop ${frr_config.router_id} 2>/dev/null && \
        gobgp global rib add -a ipv6 ${replace(loopback.ipv6, ":fe::", ":254::")}/128 nexthop ${loopback.ipv6} 2>/dev/null && \
        break
        sleep 5
      done
    owner: root:root
    permissions: '0755'

  - path: /etc/systemd/system/gobgpd-cilium.service
    content: |
      [Unit]
      Description=GoBGP daemon (simulates Cilium BGP)
      After=bird.service
      Requires=bird.service

      [Service]
      Type=simple
      ExecStart=/usr/bin/gobgpd -f /etc/gobgpd-cilium.conf --disable-stdlog --syslog yes
      ExecStartPost=/usr/local/bin/inject-gobgp-routes.sh
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'

%{ endif ~}

runcmd:
  - sysctl -p /etc/sysctl.d/99-evpn-notify.conf

%{ if loopback != null ~}
  # Create dummy interface for loopback addresses (bird2 BGP router-id)
  - ip link add dummy0 type dummy
  - ip link set dummy0 up

  # bird2 router-id IP on dummy0 (.254 - matches node IP pattern)
  - ip addr add ${loopback.ipv4}/32 dev dummy0
  - ip addr add ${loopback.ipv6}/128 dev dummy0

  # LoadBalancer IPs on dummy0 (.254 range - simulates Cilium LB-IPAM)
  - ip addr add ${replace(loopback.ipv4, "254.", "250.")}/32 dev dummy0
  - ip addr add ${replace(loopback.ipv6, ":fe::", ":254::")}/128 dev dummy0
%{ endif ~}

  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

%{ if frr_enabled && frr_config != null ~}
  - systemctl enable bird
  - systemctl start bird
  - sleep 5
  - systemctl daemon-reload
  - systemctl enable gobgpd-cilium
  - systemctl start gobgpd-cilium
  - sleep 5
  - echo "=== bird2 BGP Status ===" && birdc show protocols all || true
  - echo "=== GoBGP Neighbor ===" && gobgp neighbor || true
  - echo "=== GoBGP Advertised Routes (IPv4) ===" && gobgp global rib -a ipv4 || true
  - echo "=== GoBGP Advertised Routes (IPv6) ===" && gobgp global rib -a ipv6 || true
  - echo "=== bird2 Routes from GoBGP ===" && birdc show route protocol cilium_sim || true
  - echo "=== Kernel Routes ===" && ip -6 route show || true
%{ endif ~}

final_message: "Debian bird2 test VM ${hostname} ready (matches production Talos pattern) after $UPTIME seconds"
