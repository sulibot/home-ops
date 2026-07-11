# Home Assistant Voice, Room, and Sonos Naming

## Purpose

This runbook documents the approved naming and voice-control model for Home
Assistant, Google Home, and Sonos.

The goal is predictable household voice control:

- Google room names should match what people naturally say.
- Home Assistant areas should match physical rooms.
- Sonos player names should avoid duplicates while staying natural.
- Google should not see duplicate Sonos targets from both Sonos and Home
  Assistant.
- Home Assistant should expose scripts/scenes for routines, not every raw Sonos
  media player.

## Approved Principles

Use human room names, not infrastructure names.

Use `Sebby Bedroom` for the child's room. This is the expected spoken room name
and avoids the parsing ambiguity of possessive names such as `Sebby's Bedroom`.

Use `Master Bedroom`, not `Master`, so Google, Home Assistant, and Sonos all
have an explicit room phrase.

Use `Portable` for the portable Sonos room/player. In Sonos, a "room" is the
playable target name, so `Portable` is clearer than `Portable Speaker` or
`Roam Speaker`.

Use one plain room name for the primary Sonos player in a room. Add a role
suffix only for the second independent player in that same physical room.

Do not expose raw Home Assistant Sonos media players to Google Assistant while
Sonos is also directly linked to Google Home. That creates duplicate targets and
ambiguous voice commands.

Expose Home Assistant scripts to Google for fixed routines such as grouping,
repeat, playlists, and stop-all behavior.

## Room Names

Use these room names across Home Assistant areas, Google Home rooms, and Sonos
where applicable:

| Room | Use |
| --- | --- |
| `Living Room` | Main living room devices and primary Sonos target |
| `Master Bedroom` | Primary bedroom devices and Sonos target |
| `Sebby Bedroom` | Child bedroom devices and primary Sonos target |
| `Dining Room` | Dining room lights and Sonos target |
| `Kitchen` | Kitchen display and Sonos target |
| `Hallway` | Hallway devices |
| `Portable` | Portable Sonos Roam target |

## Light Naming

Prefer room-level groups for voice control and individual names for diagnostics.

| Entity intent | Display name |
| --- | --- |
| Living room all lights | `Living Room Lights` |
| Living room couch pair | `Living Room Couch Lights` |
| Living room TV-side bulb | `Living Room TV Right` |
| Living room couch bulbs | `Living Room Couch Left`, `Living Room Couch Right` |
| Master bedroom all lights | `Master Bedroom Lights` |
| Master bedroom bulbs | `Bed Left`, `Bed Right` |
| Sebby bedroom all lights | `Sebby Bedroom Lights` |
| Sebby bedroom sofa pair | `Sebby Bedroom Sofa Lights` |
| Sebby bedroom sofa bulbs | `Sofa Left`, `Sofa Right` |
| Sebby bedroom standing lamp | `Sebby Bedroom Standing Lamp` |
| Dining room all lights | `Dining Room Lights` |
| Dining room fan light | `Dining Room Fan` |
| Dining room desk lamp | `Dining Room Desk Lamp` |

`Sebby Bedroom Standing Lamp` is singular because it is one physical lamp with
two smart bulbs.

Wall dimmers and physical buttons should not be exposed as Google Assistant
voice targets. They are controls and automation inputs, not household voice
destinations.

## IKEA Button Naming

There are six physical IKEA BILRESA buttons: two green, two orange, and two
white.

Use the physical color in the maintenance name, but use the room/function to
show what the button controls.

| Button | Assignment |
| --- | --- |
| `Master Bedroom Green Button` | Master bedroom lights |
| `Master Bedroom Orange Button` | Master bedroom lights |
| `Sebby Bedroom White Button` | Sebby bedroom lights |
| `Living Room White Button` | Living room lights |
| `Dining Room Orange Button` | Dining room fan and desk lights |
| `Unassigned Green Button` | Spare / no current automation |

Do not assign the unassigned green button to Master Bedroom just because it was
previously named that way. Older Home Assistant registry names and automation
aliases may be stale from pairing or migration.

## Sonos Naming

Sonos does not have Home Assistant-style areas. A Sonos "room" is the playable
target name. Therefore, Sonos names should be natural playback targets.

Use this scheme:

| Physical location | Sonos / HA display name | HA area |
| --- | --- | --- |
| Living Room primary/front | `Living Room` | `Living Room` |
| Movable Living Room / Patio speaker | `Patio` | `Living Room` |
| Sebby Bedroom primary/front | `Sebby Bedroom` | `Sebby Bedroom` |
| Sebby Bedroom secondary/rear | `Sebby Bedroom Rear` | `Sebby Bedroom` |
| Master Bedroom | `Master Bedroom` | `Master Bedroom` |
| Dining Room | `Dining Room` | `Dining Room` |
| Kitchen | `Kitchen` | `Kitchen` |
| Roam / portable speaker | `Portable` | `Portable` |

Avoid duplicate Sonos names in the same physical room. For example, do not name
two independent Living Room players both `Living Room`.

The movable speaker that often lives in the Living Room but may be taken to the
patio should be named `Patio`. Keep its Home Assistant area as `Living Room`
while it normally lives there. If it later permanently moves outside, update the
HA area at that time.

Avoid adding `Speaker` to every Sonos name. It is redundant in Sonos, and it
makes spoken names longer without improving routing.

## Sonos Grouping

Use Sonos grouping for synchronized playback.

Use Home Assistant scripts to create repeatable grouped routines. This gives a
stable voice target while leaving Sonos as the playback engine.

## Music Assistant

Music Assistant runs on `talos01` in `cluster-104` and is the automation layer
for curated playback, grouping, and future playlist/radio bridges. It does not
fix Google Assistant's open-ended search/play limitation for third-party Sonos
targets; native Sonos voice services still own open-ended music requests.

Music Assistant "players" are the playback targets it controls, such as
`Living Room`, `Patio`, `Kitchen`, `Master Bedroom`, `Sebby Bedroom`, and
`Sebby Bedroom Rear`.

The server is deployed on VLAN30 at `10.30.0.252` / `fd00:30::252`, because the
current Sonos players live on VLAN30. If future players move to VLAN31, add a
second Multus attachment and verify Music Assistant's published stream address
still points at an address reachable by the target players.

Access the UI internally at:

- `https://music-assistant.sulibot.com`
- direct VLAN address for player reachability checks: `http://10.30.0.252:8095`

After first boot, configure Music Assistant in its UI:

1. Set Core -> Streams -> Published IP address to `10.30.0.252` if it auto-picks
   the Kubernetes pod IP.
2. Add the Sonos provider and confirm every Sonos player is discovered.
3. Add the streaming/music providers in use.
4. Create curated favorites/playlists with a clear prefix such as `mavoice_*`.
5. Add the Music Assistant integration in Home Assistant, pointing it at
   `http://music-assistant.default.svc.cluster.local:8095` or
   `http://10.30.0.252:8095`.

Recommended Home Assistant scripts:

| Script | Behavior |
| --- | --- |
| `Group Living Room Speakers` | Group `Living Room` and `Patio`; does not start playback |
| `Stop Living Room Music` | Stop both Living Room players |
| `Living Room KQED` | Group `Living Room` and `Patio`, then play RadioBrowser station `KQED 128 AAC` |
| `Kitchen KQED` | Play RadioBrowser station `KQED 128 AAC` on `Kitchen` |
| `Dining Room KQED` | Play RadioBrowser station `KQED 128 AAC` on `Dining Room` |
| `Master Bedroom KQED` | Play RadioBrowser station `KQED 128 AAC` on `Master Bedroom` |
| `Sebby Bedroom KQED` | Group `Sebby Bedroom` and `Sebby Bedroom Rear`, then play RadioBrowser station `KQED 128 AAC` |
| `Group Sebby Bedroom Speakers` | Group `Sebby Bedroom` and `Sebby Bedroom Rear`; does not start playback |
| `Sebby Sleep Music` | Group `Sebby Bedroom` and `Sebby Bedroom Rear`, start Plex playlist `Sebby Sleep Music`, set repeat |
| `Sebby White Noise` | Group `Sebby Bedroom` and `Sebby Bedroom Rear`, start Plex playlist `Sebby White Noise`, set repeat |
| `Stop Sebby Music` | Stop both Sebby Bedroom players |
| `Downstairs Music` | Group shared downstairs playback targets, if desired |
| `Stop All Music` | Stop all Sonos players |

Expose these scripts to Google Assistant if voice control is needed. Do not
expose the raw `media_player.*` Sonos entities from Home Assistant unless the
Sonos direct Google link is intentionally removed.

## Google Home Model

Keep the Sonos direct Google Home integration for flexible music playback.

Set each Google Home / Nest Hub default music speaker to the room's primary
Sonos target:

| Google device spoken to | Default music speaker |
| --- | --- |
| Living Room Hub | `Living Room` |
| Sebby Bedroom speaker/hub | `Sebby Bedroom` |
| Master Bedroom display | `Master Bedroom` |
| Kitchen display | `Kitchen` |

This fixes the common problem where a command such as "play KQED" plays from
the Google Hub's internal speaker instead of Sonos.

Use Google Home routines for friendlier script phrases if needed:

| Natural phrase | Routine action |
| --- | --- |
| `group Living Room speakers` | Activate `Group Living Room Speakers` |
| `group Living Room and Patio` | Activate `Group Living Room Speakers` |
| `activate Living Room KQED` | Activate `Living Room KQED` |
| `activate Kitchen KQED` | Activate `Kitchen KQED` |
| `activate Dining Room KQED` | Activate `Dining Room KQED` |
| `activate Master Bedroom KQED` | Activate `Master Bedroom KQED` |
| `activate Sebby Bedroom KQED` | Activate `Sebby Bedroom KQED` |
| `stop living room music` | Activate `Stop Living Room Music` |
| `group Sebby Bedroom speakers` | Activate `Group Sebby Bedroom Speakers` |
| `play sleep music` | Activate `Sebby Sleep Music` |
| `play white noise` | Activate `Sebby White Noise` |
| `play sleep noise` | Activate `Sebby White Noise` |
| `stop all music` | Activate `Stop All Music` |

## Rollout Order

Do this in order to avoid duplicate or stale voice targets.

1. Rename Sonos players first.

   Update names in the Sonos app to match the Sonos naming table. This is the
   foundation for Google Home music targets.

2. Set Google Home default music speakers.

   For each Google Home / Nest Hub, set its default music speaker to the
   corresponding primary Sonos target.

3. Update Home Assistant areas and display names.

   Rename HA areas to `Master Bedroom`, `Sebby Bedroom`, and `Portable`.
   Assign each Sonos entity, light, dimmer, and button to the correct area.

4. Update Home Assistant light groups and friendly names.

   Apply the GitOps configuration for room-level light groups, including the
   singular `Sebby Bedroom Standing Lamp`.

5. Correct IKEA button automation names.

   Rename stale automation aliases so they match actual assignments. Leave
   `Unassigned Green Button` unassigned until a real use is chosen.

6. Add Home Assistant Sonos scripts.

   Create scripts for grouping, sleep playback, repeat, and stop-all behavior.

7. Expose only HA scripts/scenes to Google.

   Keep HA Sonos media players hidden from Google Assistant unless the Sonos
   direct Google link is intentionally removed.

8. Resync Google Assistant devices.

   Use "Hey Google, sync my devices" or trigger the Home Assistant Google
   Assistant sync button after HA naming/exposure changes.

9. Test voice commands by room.

   Verify:

   - "Activate Living Room KQED" groups `Living Room` and `Patio`,
     then starts KQED.
   - "Activate Kitchen KQED" starts KQED on `Kitchen`.
   - "Activate Sebby Bedroom KQED" groups the Sebby Bedroom Sonos
     players, then starts KQED.
   - "Activate Group Living Room Speakers" groups `Living Room` and `Patio`.
   - "Activate Group Sebby Bedroom Speakers" groups the Sebby Bedroom Sonos players.
   - "Activate Sebby Sleep Music" groups Sebby Bedroom players and starts the
     `Sebby Sleep Music` Plex playlist.
   - "Activate Sebby White Noise" groups Sebby Bedroom players and starts the
     `Sebby White Noise` Plex playlist.
   - "Activate Stop All Music" stops playback.

## Notes

Changing Home Assistant display names and areas may update UI behavior, but
Google's view of exposed entities may remain stale until a Google Assistant
sync is run.

If Google voice commands become ambiguous, check for duplicate devices in
Google Home. The most likely cause is exposing the same Sonos player both from
Sonos direct integration and from Home Assistant.
