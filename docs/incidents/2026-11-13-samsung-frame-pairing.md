# Samsung Frame pairing from Home Assistant

## Result

The 2026 Samsung Frame (`QN65LS03HWFXZA`, `10.30.0.33`) is paired with
Home Assistant's native Samsung TV integration. The integration is loaded;
its media player and remote both report `on`. The user accepted the TV prompt.
No power, playback, volume, or input commands were sent during verification.

## Cause and repair

The TV's HTTP API and control ports were reachable from Home Assistant, but
pairing immediately returned `auth_missing` and the TV displayed no prompt.
RouterOS connection tracking showed Talos-originated traffic reaching the TV
with source `10.104.0.4`, outside the TV's subnet. Samsung's integration
[documents this subnet restriction](https://www.home-assistant.io/integrations/samsungtv/#subnetvlan-restrictions).

Added one RouterOS source NAT rule:

- Source: `10.104.0.4` (Cilium's masqueraded cluster-104 node address).
- Destination: `10.30.0.33`, TCP ports `8001,8002` only.
- Translated source: `10.30.0.254`.
- Comment: `HA Samsung Frame control same-subnet compatibility`.

After translation, pairing displayed the prompt and completed successfully.
The source match covers traffic from that node, not an individual pod, because
Cilium has already translated the pod source before the router receives it.
No general VLAN routing or firewall access policy was changed.

The live rule (`*4`) was imported into
`routeros_ip_firewall_nat.rules["2"]` in the RouterOS Terragrunt state.
A targeted plan returned no changes. The module now supports optional
`protocol` and `dst_port` NAT selectors. No full-device apply was run.
If the TV address changes, update the integration host and this NAT destination.

Rollback: disable the rule by its unique comment, then remove this desired
rule and reconcile its state deliberately. Cross-subnet pairing/control will
stop working; existing Cast/Music Assistant entries are independent.

## Home Assistant records

- Integration entry: `01M7C5NKCEQPM8RDE5V6ZFCF8B`.
- Media player: `media_player.65_the_frame_qn65ls03hwfxza`.
- Remote: `remote.65_the_frame_qn65ls03hwfxza`.
- Pairing token is stored only in Home Assistant's integration storage.

The preceding cleanup removed seven retired Hisense/older Frame device
registrations and eleven entities. Old Frame Music Assistant players were
configured with `expose_player_to_ha=false` after discovery recreated them;
the retired devices and entities were then absent from HA's live registries.
The 2026 Frame Cast/Music Assistant entries and Apple TV were retained.
