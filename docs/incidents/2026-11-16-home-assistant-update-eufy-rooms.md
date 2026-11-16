# Home Assistant update and Eufy Clean Rooms installation

## Core update

Merged Renovate PR #443 and reconciled cluster-104 Flux. Home Assistant changed
from 2026.7.2 to 2026.11.1 using the existing home-operations container:

`ghcr.io/home-operations/home-assistant:2026.11.1@sha256:c129b1e4190273254d93d413fe2a083233c9202d84cb08f84dddb01861df432e`

Core 2026.11.2 was released during this work, but the corresponding
home-operations image returned MANIFEST_UNKNOWN. The deployed version was the
available update already prepared and validated by Renovate.

HA migrated the HACS config entry to its built-in Marketplace. Existing
repositories remained registered. Marketplace's refreshed inventory found one
pending integration update: Versatile Thermostat 10.6.4 -> 10.6.5, which includes
HA 2026.11 compatibility changes. Installed it. No thermostat config entry was
present; no temperature settings were changed.

## Backup and checks

- Pre-update Kopia snapshot: `d3e0c0c3bc1378b9925012b214fff763`, root
  `ka54ac750fcd62d1db9e430cb8aff0641`.
- Local rollback directory: `/config/backups/pre-core-20261116/` contains
  `config-and-integrations.tar.gz`, a SQLite API backup of the recorder DB,
  baseline entity states, and hashes of the repaired Robovac files.
- The local archive excludes unrelated root-owned OTBR data, caches and older
  backups; the completed remote Kopia snapshot includes the full config volume.
- SQLite `quick_check` returned `ok`; HA's config check returned `valid` without
  errors or warnings after the update.
- All pre-existing config entries loaded after startup. Compared to the baseline,
  no previously available entity became unavailable after startup settled.
  Pre-existing unavailable devices remain; this is not a claim all devices are online.
- The Robovac patch hashes remained unchanged. With both vacuum integrations
  loaded, the original `vacuum.pause` followed by `vacuum.start` produced
  `paused` -> `cleaning`, leaving the current job running.

For a core rollback, restore both the old image and the pre-update database and
config state while HA is stopped. A version-only downgrade would not undo
Marketplace/config migrations. Backups contain credentials and stay on the
config volume or encrypted backup repository, never in Git.

After the final restart, Marketplace reported no pending updates and the room
list persisted. Post-update Kopia snapshot: `8a3c0b2ac1af502355eb1e1387115358`,
root `k5e7184738efc4f49fa35019b1b40b80d`.

## Eufy Clean Rooms

Installed `ajachierno/ha-eufy-clean-rooms` v0.2.5 through Marketplace, then used
HA's config flow with the existing Eufy account. No account secrets were copied
into the repository. The release tag resolves to
`6478b45f809ff4ed08c620d5a8061074b1f7b2de`.

- Config entry: `01M7K0V6SX88YF9KXP0TFQSFQA`
- Device/title: **Eufy S1 Pro Rooms**
- Model/transport: `T2080A`, Tuya cloud control/status plus local P2P room lookup
- Explicit dock/robot address: `10.31.0.149`; network scan disabled
- New vacuum entity: `vacuum.eufy_s1_pro_rooms`
- Existing local control entity retained: `vacuum.robovac`
- Room sensor: `sensor.eufy_s1_pro_rooms_rooms`
- Buttons: `button.eufy_s1_pro_rooms_vacuum_room_0` through `_7`, with matching
  `mop_room_0` through `_7` buttons

The local room lookup succeeded and discovered map **2**, with room IDs **0–7**.
The integration reports only generic names **Room 0–Room 7**. The room sensor reports 8;
battery, task and error-code sensors were created. This integration does not
provide a rendered live map.

## Kitchen identification and supervised test

The user identified the small central red region on the current Eufy Map2 as
the kitchen and confirmed it was clear and they could observe the test.
A read-only P2P map capture retrieved the room-outline bitmap and room table
for local map ID 2 (310 x 370 pixels). Decoding the bitmap's room IDs and
matching its geometry to the user's screenshot identified **room 3 as Kitchen**.
This identification used the room geometry, not the app's repeated colors.

The existing HA buttons now have display names **Vacuum Kitchen** and
**Mop Kitchen**. Their entity IDs remain
`button.eufy_s1_pro_rooms_vacuum_room_3` and
`button.eufy_s1_pro_rooms_mop_room_3`. The robot's room table still uses
generic names; service calls must use room ID 3 or `Room 3`, not `Kitchen`.
Revalidate this association if the map is recreated or its rooms are split/merged.

Sent one `eufy_clean_rooms.clean_rooms` command targeting
`vacuum.eufy_s1_pro_rooms`, `rooms: [3]`, `clean_type: vacuum`,
`fan_speed: Standard`, `clean_times: 1`. After its next status poll, HA reported
`cleaning`, task `room cleaning`, Standard suction and no error codes.
The user has been asked to confirm it physically enters and cleans the kitchen;
that observation is still pending. The integration sets `cleaning_rooms`
optimistically, so that attribute alone is not physical validation.

No new cleaning automations were created or enabled. Keep unattended cleaning
disabled until physical room targeting is confirmed. Mop targeting has not
been tested.

The integration installation and account setup live on the HA config PVC and
are covered by its scheduled backup. This document records the operation; it
is not an automatic installer or a deployment of credentials.
