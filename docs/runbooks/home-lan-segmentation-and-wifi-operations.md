# Home LAN Segmentation and Wi-Fi Operations Runbook

## Purpose

This runbook documents the current home LAN access model for personal devices, IoT devices, RouterOS, and the Synology access point.

It covers three things:

- Configuration: which parts are managed in Terraform versus manually on the access point.
- Infrastructure: VLANs, SSIDs, IPv4, IPv6, multicast discovery, and traffic policy.
- Operations: how to validate, troubleshoot, change, and recover the network without losing the management path.

This is the operational source of truth for the current SSID and VLAN design, not a generic MikroTik or Synology guide.

## Scope

This runbook covers:

- RouterOS on `10.30.0.254`
- Synology AP on `10.30.0.1`
- Personal SSID `io`
- IoT SSID `europa`
- VLANs `30` and `31`
- Related LAN VLAN interfaces and IPv6 delegated-prefix handling
- Discovery protocols required for Home Assistant, TVs, Sonos, printers, and similar devices

## Design Goals

The current network design is intentional.

- Personal devices live on `vlan30`.
- IoT and media devices live on `vlan31`.
- Personal devices must be able to reach IoT devices.
- IoT devices must not be able to initiate arbitrary new connections back into the personal network.
- Discovery from IoT devices must still reach the personal network so Home Assistant and controller apps can find them.
- The AP management path should survive an AP reset without requiring VLAN tagging to be rebuilt first.

## Current Topology

### Personal network

- SSID: `io`
- VLAN: `30`
- Intended clients:
  - phones
  - tablets
  - laptops
  - desktops
- Radio placement:
  - `5 GHz-1`
  - `5 GHz-2`
- Not carried on:
  - `2.4 GHz`

### IoT network

- SSID: `europa`
- VLAN: `31`
- Intended clients:
  - thermostat
  - vacuum
  - Google Home / Nest devices
  - printer
  - lights
  - switches
  - Sonos
  - TV
- Radio placement:
  - `2.4 GHz`
  - `5 GHz-1`
- Not carried initially on:
  - `5 GHz-2`

### AP uplink model

The Synology AP uplink is intentionally not a fully tagged trunk.

- Native / untagged network on AP uplink: `vlan30`
- Tagged network on AP uplink: `vlan31`

This is the right recovery trade for this environment.

If the AP is wiped or factory reset:

- the AP still comes back on the native management path
- the AP remains reachable on the personal LAN
- only the tagged IoT SSID mapping needs to be rebuilt

## Current Radio Plan

### Fixed channels

Current target channel plan on the Synology AP:

- `2.4 GHz`
  - channel `11`
  - width `20 MHz`
- `5 GHz-1`
  - channel `149`
  - width `20/40/80 MHz`
- `5 GHz-2`
  - channel `44`
  - width `20/40/80 MHz`

### Rationale

- `2.4 GHz` must use only non-overlapping channels `1`, `6`, or `11`. Channel `7` was previously in use and is operationally wrong.
- `5 GHz-1` on `149` was the cleanest observed 5 GHz radio in live counters.
- `5 GHz-2` was moved off `Auto` and off DFS-adjacent behavior to reduce drift and client instability.
- `160 MHz` width was removed earlier because it was hurting stability more than helping throughput.

### Operational guidance

While debugging Wi-Fi issues:

- keep channels fixed
- keep DFS auto-switch disabled
- prefer explicit SSID-to-band mapping over SmartConnect-style abstractions
- do not add extra SSIDs unless there is a measured reason to do so

## Source of Truth

### Git-managed

Primary RouterOS declarative configuration:

- `/Users/sulibot/repos/github/home-ops/terraform/infra/live/routeros/terragrunt.hcl`
- `/Users/sulibot/repos/github/home-ops/terraform/infra/modules/routeros/firewall.tf`
- `/Users/sulibot/repos/github/home-ops/terraform/infra/modules/routeros/variables.tf`
- `/Users/sulibot/repos/github/home-ops/terraform/infra/modules/routeros/ipv6_lan.tf`
- `/Users/sulibot/repos/github/home-ops/terraform/infra/modules/routeros/l2_lan.tf`

These files now manage:

- bridge objects
- bridge ports
- bridge VLAN membership
- VLAN interfaces
- IPv4 LAN addresses
- IPv6 LAN addresses
- IPv6 neighbor discovery / router advertisements
- IPv6 DHCP clients for delegated prefixes
- asymmetric firewall policy between personal and IoT VLANs
- mDNS / SSDP / IGMP-related firewall allowances

### Manual / AP UI-managed

These remain manual on the Synology AP:

- SSID creation
- SSID-to-radio assignment
- SSID-to-VLAN mapping on the AP
- Wi-Fi channel selection UI settings
- transmit power settings
- SmartConnect and band-splitting behavior

This means the AP is not yet GitOps-managed. The RouterOS side is declarative. The Synology side is still operational state.

## Current RouterOS Layer 2 Model

### Bridges

Current bridges:

- `br-fabric`
  - `vlan-filtering=yes`
  - `igmp-snooping=yes`
- `lo_dns`
  - loopback bridge for DNS service addressing

### Bridge ports on `br-fabric`

- `pve01[ether2]`
- `pve02[ether3]`
- `pve03[ether4]`
- `luna01[ether5]`
- `wifi[ether6]`
  - `pvid=30`
- `ilom-pve03[ether7]`
- `spare[ether8]`

### Bridge VLAN membership

- `vlan1`
  - tagged: `br-fabric`
  - untagged: `pve01`, `pve02`, `pve03`, `luna01`, `ilom-pve03`, `spare`
- `vlan10`
  - tagged: `br-fabric`, `pve01`, `pve02`, `pve03`, `luna01`, `ilom-pve03`
- `vlan30`
  - tagged: `br-fabric`, `pve01`, `pve02`, `pve03`, `luna01`, `spare`
  - untagged: `wifi[ether6]`
- `vlan31`
  - tagged: `br-fabric`, `wifi[ether6]`, `pve01`, `pve02`, `pve03`, `luna01`, `spare`
- `vlan100`
  - tagged: `br-fabric`, `pve01`, `pve02`, `pve03`, `luna01`
- `vlan200`
  - tagged: `br-fabric`, `pve01`, `pve02`, `pve03`, `luna01`, `ilom-pve03`, `spare`

This is the intended AP trunk model.

## Current RouterOS Layer 3 Model

### IPv4 LAN addressing

Current static IPv4 addresses:

- `vlan1`
  - `10.1.0.254/24`
- `vlan10`
  - `10.10.0.254/24`
  - `10.0.10.254/24`
- `vlan30`
  - `10.30.0.254/24`
- `vlan31`
  - `10.31.0.254/24`
- `vlan200`
  - `10.200.0.254/24`
- `lo_dns`
  - `10.255.0.53/32`
- `lo`
  - `10.255.0.254/32`

### IPv6 LAN addressing

Current ULA / GUA state:

- `vlan10`
  - `fd00:10::fffe/64`
  - `::fffe` from pool `pd-v10`
- `vlan30`
  - `fd00:30::fffe/64`
  - `fd00:30::/128`
- `vlan31`
  - `fd00:31::fffe/64`
  - `::fffe` from pool `pd-v31`
- `vlan200`
  - `fd00:200::fffe/64`

### IPv6 delegated-prefix clients

Current DHCPv6 prefix delegation clients:

- `wan6-v10` -> `pd-v10`
- `wan6-v30` -> `pd-v30`
- `wan6-v31` -> `pd-v31`
- `wan6-v200` -> `pd-v200`
- `wan6-vnet100` -> `pd-vnet100`
- `wan6-vnet101` -> `pd-vnet101`
- `wan6-vnet102` -> `pd-vnet102`
- `wan6-vnet103` -> `pd-vnet103`

Notes:

- `wan6-v10` and `wan6-v30` currently run the RouterOS script `update-nat66-on-prefix-change`.
- The pool names are expected to exist in `/ipv6 pool` as dynamic objects once the clients are bound.
- `vlan31` previously lacked complete IPv6 LAN state. That was corrected and is now codified.
- ISP-derived `2600:1700:*` GUAs are not treated as stable literals in Terraform. Only static ULAs are hard-coded. Delegated GUAs must come from `pd-*` pools or remain unmanaged if they are purely transient operational state.

### IPv6 neighbor discovery / router advertisements

Neighbor discovery is now explicitly managed for:

- `vlan10`
- `vlan30`
- `vlan31`
- `vlan200`

This is important because delegated prefixes or static IPv6 addresses alone are not enough. Clients require ND/RA on the interface to learn:

- on-link prefixes
- default router
- optionally DNS via RA

## Traffic Policy

### Asymmetric trust model

Current intended policy:

- `vlan30 -> vlan31`: allowed
- `vlan31 -> vlan30`: blocked for new connections
- `established,related`: allowed both ways

This allows:

- personal devices to control and manage IoT devices
- Home Assistant on the personal network to reach IoT devices
- response traffic from IoT devices back to personal clients

This blocks:

- arbitrary new connections initiated from IoT devices into the personal network

### Discovery exceptions

Discovery is intentionally broader than routed trust.

Current policy supports:

- `mDNS`
- `SSDP`
- `IGMP`

This is required for:

- HomeKit / Home Assistant discovery
- Google Home / Nest device discovery
- some TV and media discovery flows
- some Sonos and printer discovery flows

Important distinction:

- discovery reflection is not the same as allowing general routed access
- multicast visibility can be allowed while still blocking ordinary new connections from IoT to personal devices

## Discovery Model

### mDNS

Current RouterOS DNS config repeats mDNS across:

- `vlan30`
- `vlan31`

This is the minimum required discovery layer for Home Assistant and HomeKit-style devices across the segmentation boundary.

### SSDP / IGMP

The RouterOS firewall now explicitly allows:

- `udp/1900` between `vlan30` and `vlan31`
- `IGMP` between `vlan30` and `vlan31`

That is intentional. It supports device classes that rely on SSDP/UPnP-style multicast discovery without opening the full personal network to IoT-initiated traffic.

### Caveat

Some consumer ecosystems still behave poorly across VLANs even with discovery allowances. Likely troublemakers:

- Sonos
- TVs / DLNA / casting devices
- Chromecast-adjacent flows depending on firmware behavior

If a specific device family remains unstable across `vlan30` and `vlan31`, move only that family if necessary. Do not weaken the entire trust model first.

## Recommended Device Placement

### `io` / `vlan30`

Use for:

- phones
- tablets
- laptops
- desktops

Do not place general-purpose personal devices on `2.4 GHz` unless testing requires it.

### `europa` / `vlan31`

Use for:

- thermostat
- vacuum
- Google Home / Nest hubs
- printer
- lights
- switches
- Sonos
- TV

Recommended band use:

- most IoT on `2.4 GHz`
- TV and higher-bandwidth media devices on `5 GHz-1`
- Sonos on `5 GHz-1` if it is supported and stable, otherwise leave it on `2.4 GHz`

## Validation Procedures

### Validate RouterOS Terraform state

From the repo root:

```bash
cd /Users/sulibot/repos/github/home-ops/terraform/infra/live/routeros
terragrunt plan
```

Expected result:

- `No changes. Your infrastructure matches the configuration.`

### Validate firewall policy

On RouterOS:

```routeros
/ip firewall filter print detail where comment~"IoT|SSDP|IGMP"
```

Expected rules:

- allow personal to IoT
- block new IoT to personal
- SSDP allowances
- IGMP allowances

### Validate IPv6 LAN state

On RouterOS:

```routeros
/ipv6 address print detail where interface~"vlan10|vlan30|vlan31|vlan200"
/ipv6 nd print detail where interface~"vlan10|vlan30|vlan31|vlan200"
/ipv6 dhcp-client print detail
/ipv6 pool print detail
```

Validate that:

- each intended VLAN has a ULA gateway
- delegated pools are bound where expected
- `vlan31` has both addressing and ND, not just a bound DHCPv6 client

### Validate AP uplink and basic upstream health

From the Synology AP shell:

```sh
ping -c 10 10.30.0.254
ifconfig eth4
ifconfig br0
```

Healthy indicators:

- low latency to RouterOS
- no packet loss
- uplink negotiated at expected speed
- no large `errors` or `dropped` counters on the wired uplink

### Validate Wi-Fi radio health

From the Synology AP shell:

```sh
ifconfig wifi0
ifconfig wifi1
ifconfig wifi2
ifconfig wlan000
ifconfig wlan100
ifconfig wlan200
```

Interpretation:

- `wifi1` / `wlan000` correspond to the `2.4 GHz` path
- `wifi2` / `wlan100` correspond to `5 GHz-1`
- `wifi0` / `wlan200` correspond to `5 GHz-2`

Operationally observed pattern:

- `2.4 GHz` is the noisiest radio path
- `5 GHz-1` is the cleanest
- `5 GHz-2` is acceptable but should remain on a fixed channel

### Validate Home Assistant and IoT discovery across VLANs

Expected behavior:

- Home Assistant on `fd00:31::251` / `10.31.0.251` can discover devices on `vlan31`
- HomeKit / mDNS devices on `vlan31` are visible to HA in the IoT plane directly
- personal devices on `vlan30` can reach device web UIs or APIs on `vlan31`
- IoT devices cannot initiate arbitrary new sessions into `vlan30`

Important limitation:

- The current Thread OMR workaround remains required.
- Moving OTBR, Home Assistant, and `matter-server` to `vlan31` simplifies the topology, but it does not by itself teach the Kubernetes pod network how to route to the Thread OMR prefix.

## Troubleshooting

### Symptom: devices on `vlan31` do not get IPv6

Check:

- `vlan31` has `fd00:31::fffe/64`
- `vlan31` has a delegated `pd-v31` address if expected
- `/ipv6 nd print detail where interface=vlan31` returns an entry

If `vlan31` has addresses but no ND entry, clients will usually only get link-local IPv6.

### Symptom: `pd-v31` is bound in DHCPv6 client view but missing in `/ipv6 pool`

This indicates stale or inconsistent dynamic PD state.

Operational recovery:

1. inspect `/ipv6 dhcp-client print detail`
2. inspect `/ipv6 pool print detail`
3. if they disagree, flap or recreate the specific DHCPv6 client cleanly
4. re-check the pool table after rebinding

Do not assume a bound DHCPv6 client means the LAN interface is actually advertising that prefix.

### Symptom: Home Assistant or controller apps cannot discover IoT devices

Check, in order:

1. device is actually on `europa` / `vlan31`
2. RouterOS mDNS repeat includes `vlan30` and `vlan31`
3. SSDP and IGMP firewall allowances are present
4. Home Assistant or controller host can still route `vlan30 -> vlan31`
5. the device itself is actually advertising on the network

Do not assume a pairing code on a device means it is emitting the correct multicast advertisement.

### Symptom: Wi-Fi feels slow but internet and RouterOS look healthy

This usually means the problem is the radio side, not upstream.

Check:

- radio counters on the Synology AP
- whether `2.4 GHz` clients are overused
- whether a personal device has fallen back onto the wrong band
- whether the AP rebooted onto the intended fixed channels

### Symptom: AP wiped or factory reset

Recovery approach:

1. reach the AP over the native untagged network on `vlan30`
2. restore management access first
3. recreate SSID `europa` with VLAN tag `31`
4. restore SSID-to-radio assignments
5. re-check channel plan

This is why `vlan30` remains native on the AP uplink.

## Change Management Guidance

### Safe change order for SSID migration

1. Apply RouterOS policy first
2. Move or create `europa` on `vlan31`
3. Move IoT devices one family at a time
4. Validate discovery and control after each family
5. Leave personal devices on `io`

Suggested order:

- thermostat
- printer
- Google Home / Nest devices
- vacuum
- lights and switches
- Sonos
- TV

### Avoid these mistakes

- do not put `io` back on `2.4 GHz` unless there is a measured reason
- do not rely on `Auto` channels while debugging Wi-Fi quality
- do not weaken the firewall broadly to solve a discovery problem without verifying multicast first
- do not assume Sonos or TV ecosystems will behave like simple IoT sensors across VLANs

## Current Gaps

RouterOS is now largely codified for this design, but some operational state still lives outside Terraform.

### Managed in Terraform now

- bridge objects
- bridge ports
- bridge VLAN membership
- VLAN interfaces
- IPv4 LAN addresses
- IPv6 LAN addresses
- IPv6 ND/RA
- IPv6 DHCPv6 clients
- firewall and multicast-discovery policy

### Still manual today

- Synology SSIDs
- Synology radio assignments
- Synology channel settings
- Synology VLAN mapping per SSID
- any Synology roaming or SmartConnect policy

### Good future candidates

- DHCPv4 pools, networks, and leases
- more RouterOS service and multicast-specific settings if required
- AP configuration automation, if Synology exposes a stable management path for it

## Operational Summary

The network design is intentionally asymmetric.

- `io` is the personal network on `vlan30`
- `europa` is the IoT network on `vlan31`
- the AP uplink uses native `vlan30` and tagged `vlan31`
- personal devices are kept off `2.4 GHz`
- IoT devices keep access to `2.4 GHz` and one clean `5 GHz` radio
- RouterOS allows discovery across the segmentation boundary while still blocking general IoT-initiated access into the personal network

This is the correct operational baseline for tomorrow's device migration and testing.
