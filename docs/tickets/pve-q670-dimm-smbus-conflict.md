# pve01/02: Second DIMM Not Detected with ConnectX-4 Installed (SMBus Conflict)

## Firmware-reported capacity ceiling (2026-07-22, pve01)

Full `dmidecode -t memory` on pve01 (still on original BIOS 5.27,
05/13/2024) shows, in the Physical Memory Array (type 16) structure:

    Maximum Capacity: 64 GB
    Number Of Devices: 2

This is a firmware-reported SMBIOS value, not marketing copy, and
directly contradicts the advertised spec (96GB per CWWK's own site,
128GB per StoneStorm's Amazon listing).

**Checked against existing test data — this does NOT explain the
observed failure.** If a real 64GB total-capacity ceiling were the
cause, a single 48GB DIMM in DDR5_2 alone (well under 64GB) should
work fine. It doesn't — that's the isolation test that produces a hard
POST failure (1+3 beep) on both boards. A capacity-ceiling theory
predicts that config should succeed; it fails instead. So this is
most likely stale/incorrect SMBIOS metadata (a known, common firmware
bug pattern — vendors frequently ship wrong "Maximum Capacity" values
that aren't tied to any real enforced limit) rather than the actual
root cause. The real fault still looks specific to the
DDR5_2/Controller1-ChannelA channel's training/detection logic,
independent of total capacity.

Still worth raising with CWWK as a separate, real discrepancy between
their firmware's self-report and their advertised spec — just not as
"the" explanation for the core issue.

Confirmed pve02 (Nov 2024 BIOS, post-flash) reports the identical
`Maximum Capacity: 64 GB` — value is unchanged by the BIOS update
CWWK provided, consistent across both boards and both firmware
versions tested.

## Both boards flashed (2026-07-22)

pve01 has now also been flashed to the 11/27/2024 build (previously
only pve02 was updated). Confirmed via SSH: both nodes report
`bios-version 5.27`, `bios-release-date 11/27/2024`. With both DIMMs
installed on both boards, both still show `Controller1-ChannelA-DIMM0:
No Module Installed`, `Controller0-ChannelA-DIMM0` at 48GB, and the
identical `Maximum Capacity: 64 GB` value. Fully symmetric result
across both boards on the new firmware — closes the last remaining
gap in the test matrix below (previously pve01 was only tested on the
original BIOS).

## Test matrix (complete as of 2026-07-20)

| Config | pve01 | pve02 |
|---|---|---|
| Card out, both DIMMs, Auto speed | fails (original baseline) | — |
| Card out, both DIMMs, DIMM swap | fails (follows slot) | — |
| Card out, both DIMMs, 4200MHz cap | — | **fails** (confirmed 2026-07-20) |
| Card in, both DIMMs, Auto speed | fails | fails |
| Card in, both DIMMs, 4400MHz cap | — | fails |
| Card in, both DIMMs, 4200MHz cap | fails | fails |
| Card in, single DIMM in DDR5_2 alone | hard fail, 1+3 beep | hard fail, 1+3 beep |
| Card in, single DIMM in DDR5_1 alone | works | — |

Every tested combination of {card in/out} x {Auto/4400/4200 speed}
fails to detect Controller1-ChannelA/DDR5_2 with both DIMMs installed.
The only working configuration found is a single DIMM in DDR5_1 alone.

## BIOS update test (2026-07-22, pve02)

CWWK support (Jessica) sent a BIOS build via WeTransfer after the
warranty/support inquiry, dated 11/27/2024 (build `CW-MB-Q670-2L-Black-2024.11.27.iso`,
firmware payload `1.bin`, SHA256
`bdea87199e18b358c71980adb71feb3bee399f009520e6ab80ac77eb57c77670`).
Note: a first file they sent (`CW-NAS-Q670-2L-PQ.iso`) was verified as
incorrect before flashing — wrong board variant (`PQ` not `Black`) and
identical BIOS date to what was already installed; caught via
pre-flash inspection of the embedded `motherboard.txt`, flagged to
Jessica, and she re-sent the correct file.

Flashed the corrected 11/27/2024 build to pve02 via physical USB
(FAT32, EFI Shell flash per CWWK's documented procedure — not the ISO
mount/CD approach that failed earlier over JetKVM). Flash completed
cleanly: `FPT Operation Successful`, verify pass confirmed "data is
identical." Confirmed post-flash via BIOS setup and `dmidecode`:
`BIOS Vendor: American Megatrends`, `Build Date and Time: 11/27/2024`
(setup screen) / `dmidecode -s bios-release-date` → `11/27/2024`
(SSH). SR-IOV Support confirmed still `[Enabled]` post-flash
(Advanced → PCI Settings Common for all Devices).

**Result: issue NOT fixed.** With both DIMMs installed, card in,
`Controller1-ChannelA-DIMM0` still reports "No Module Installed" —
identical to every pre-flash test. The new BIOS did not change this
outcome.

Worth flagging to CWWK: the build they sent (11/27/2024) is actually
*older* than the Sep 2025 build already on their own public file
server (`drive.x86pi.cn`, verified earlier this session) — this wasn't
their latest available firmware. Worth asking for the actual newest
build if one exists beyond what was sent.

pve01 not yet flashed — holding at BIOS 5.27 (05/13/2024) as a known
baseline pending CWWK's response to this result.

## Status (2026-07-18)

Open, reopened. Kapton tape (B5/B6, ConnectX-4 B-side only) applied to
both pve01 and pve02 and tested. **Root cause reframed**: this is not a
per-unit physical defect. Isolation testing (single DIMM in
Controller1-ChannelA/DDR5_2 alone, memory frequency capped to 4400MHz)
produces an identical hard POST failure (1 long beep + 3 beeps, base
64K RAM failure) on both independent boards. This is a reproducible,
board-model-level issue with the DDR5_2/Controller1-ChannelA channel,
not a broken slot on one unit. Recommend sending the CWWK support
inquiry with this cross-board evidence. Linear issue not created
(workspace free-issue limit reached).

## 2026-07-18 findings (pve01)

1. **Controller1-ChannelA-DIMM0 shows "No Module Installed" even with
   the ConnectX-4 fully removed.** `dmidecode -t memory` on pve01 with
   no card installed still reports only Controller0-ChannelA-DIMM0 at
   48GB; Controller1-ChannelA-DIMM0 is absent. This means the missing
   second DIMM is not solely a card-present symptom, contradicting (or
   at least incomplete relative to) the original SMBus-conflict theory.

2. **DIMM swap test: problem follows the slot, not the module.** Swapped
   the two 48GB Crucial DIMMs between physical slots. The "No Module
   Installed" status stayed on Controller1-ChannelA-DIMM0 regardless of
   which physical stick was in it. Rules out a bad/marginal DIMM;
   points at the Controller1-ChannelA slot/board (bent pin, bad solder
   joint, seating) as a contributing or separate issue from the SMBus
   conflict.

3. **With Kapton tape applied to ConnectX-4 B5/B6 and the card
   reinstalled, pve01 fails to boot** — POST beep, no console output.
   Confirmed B-side only was taped (verified: 4 untaped contacts from
   bracket end, then 2 taped = B5/B6 correctly positioned). Suspected
   cause: tape shifting/lifting during card insertion (edge-connector
   insertion friction can fold or drag tape out of clean placement),
   producing a noisy/partial SMBus contact rather than a clean open
   circuit — this can hang the whole SMBus segment during POST memory
   init (beep, no console) rather than just dropping one DIMM cleanly.
   Not yet resolved; card pulled back out, tape to be inspected/redone
   before retry.

## Reference material

- Local scrape of CWWK FAQ page 235 (`doc.x86pi.cn` space
  `VXCQuW3XQSosL8RRJL2ixp`, page URL now 404s upstream): `doc235.html`,
  `wb18348.html`, `docmain.js` in repo root (untracked, 2026-07-16).
  Contains the vendor's own reference photo for the B5/B6 tape fix,
  confirming pin position (2 adjacent pins several contacts in from B1,
  well before the B11/notch boundary) — matches the placement applied
  to pve01 (4 untaped contacts from bracket end, then 2 taped).
- Same page also documents a DIMM slot-population-order quirk for
  CWWK's 4-slot Q670 variant (prefer slots 2/4 for 1-2 sticks; slots
  1/3 "may fail to boot"). Doesn't directly apply to this 2-slot board
  (one DIMM per memory controller), but confirms Q670-platform-wide
  memory-slot idiosyncrasies are a known vendor-acknowledged pattern.
- Draft support inquiry to CWWK (not yet sent):
  [pve-q670-cwwk-support-draft.md](pve-q670-cwwk-support-draft.md)

4. **Single-DIMM isolation test on DDR5_2 (Controller1-ChannelA) fails
   POST outright.** With only one DIMM installed — the known-good
   module (confirmed working in DDR5_1 during the earlier swap test) —
   moved into DDR5_2 alone, pve01 produces a 1-beep-then-3-beep
   sequence and does not reach splash. On classic AMI beep codes, 3
   beeps = base 64K RAM failure (fundamental memory POST failure), a
   different and more severe failure class than the earlier
   "boots fine, one channel just not detected" symptom seen with both
   DIMMs installed. Combined with the DIMM-swap result (fault follows
   the slot, not the module), this is strong evidence of a physical
   defect specific to the Controller1-ChannelA/DDR5_2 slot on pve01 —
   not a BIOS quirk, not a bad module, not (solely) the SMBus/card
   conflict. Recommend treating this as a hardware fault and
   escalating to CWWK rather than further reseating/troubleshooting.

## Cross-board confirmation (2026-07-18, pve02)

Applied the same Kapton tape fix (B5/B6) to pve02's ConnectX-4 and
tested with both DIMMs installed. **Same symptom reproduces exactly**:
`Controller1-ChannelA-DIMM0` (DDR5_2) shows "No Module Installed" while
`Controller0-ChannelA-DIMM0` (DDR5_1) is fine at 48GB. This is a
different physical board and (need to confirm) potentially different
DIMM in that slot — so this is no longer explainable as a single
defective unit or a single defective stick.

Also tested capping `Maximum Memory Frequency` to 4400 MHz on pve02
(same fix attempted on pve01): `Configured Memory Speed` confirms the
cap took effect (4400 MT/s), but Controller1-ChannelA-DIMM0 still shows
"No Module Installed." Frequency capping does not fix detection on
either board.

**Isolation test on pve02 (confirms cross-board reproduction):** single
DIMM moved into MC1/DDR5_2 alone (DDR5_1 empty), `Maximum Memory
Frequency` capped at 4400MHz — produces the exact same hard POST
failure as pve01: **1 long beep followed by 3 beeps** (base 64K RAM
failure), no splash. Identical failure signature, identical test
conditions, second independent board.

**Root cause reframed:** this is a reproducible board-model-level
issue with the Controller1-ChannelA/DDR5_2 channel, not a per-unit
physical defect — two independent boards fail identically under
identical isolation testing, which is not plausible as coincidental
hardware defects on both units. Still open: whether swapping which
physical DIMM occupies DDR5_2 changes anything (would fully rule out a
matched-pair DIMM compatibility angle), though given the identical
beep-code signature across two boards with likely-different DIMMs in
that slot, this is now a low-priority check rather than the leading
theory.

## Forum research (2026-07-18)

Checked the x86Pi community forum (`bbs.x86pi.com`; live site currently
500s on direct thread fetch, retrieved via Wayback Machine snapshots).

- Topic 18470, "Crucial DDR5-5600 only at 5200 MHz on
  CW-NAS-Q670-2L-8P-4M2" (this exact board model, officially answered
  by CWWK staff): OP describes moving a single DIMM between slots as a
  normal troubleshooting step for a speed/downclock issue; CWWK's own
  reply also suggests slot-swapping as valid troubleshooting and never
  flags any slot restriction. No indication a specific slot is required
  for single-DIMM operation.
- No forum or vendor-doc report found of a slot detecting the DIMM
  intermittently or failing POST outright with a known-good single
  DIMM, matching what pve01 is doing on DDR5_2/Controller1-ChannelA.

Conclusion: single-DIMM-in-either-slot is the expected, vendor-endorsed
configuration for this board. pve01's DDR5_2 hard POST failure (1
beep + 3 beeps, base-64K RAM failure) with a known-good module is not
documented/expected behavior anywhere found — further supports a
board-level physical defect specific to this unit.

## Revised open questions

- Is Controller1-ChannelA-DIMM0's dropout (with no card installed) a
  pre-existing slot fault unrelated to the ConnectX-4/SMBus issue, or
  was the original bug report only ever observed with the card
  installed (i.e. did this baseline failure exist before any of this
  troubleshooting)?
- Does the same slot-independent-of-card symptom reproduce on pve02, or
  is this pve01-specific (physical slot defect)?
- Retest with freshly cut, well-burnished tape and careful straight-line
  card insertion to rule out tape displacement as the cause of the
  boot-hang/beep.

## Problem

Both Proxmox nodes (pve01 = 10.10.0.1, pve02 = 10.10.0.2; CWWK
CW-Q670-NAS 8-bay boards — Black 8-SATA U-DIMM variant
(CW-NAS-Q670-2L-Black-8SATA), BIOS 5.27 / 2024-05-13) detect
only one of two 48 GB Crucial DDR5-5600 U-DIMMs (CP48G56C46U5) while the
Mellanox ConnectX-4 Lx dual-port NIC is installed in the PCIe x16 slot.
`dmidecode -t memory` reports `Controller1-ChannelA-DIMM0: No Module
Installed` — an SPD-level non-detection, identical on both nodes.

## Root Cause (vendor-confirmed)

SMBus conflict. DDR5 SPD presence-detection runs over SMBus; the
ConnectX-4's management sideband also drives SMBus via PCIe edge pins
**B5 (SMCLK) and B6 (SMDAT)**. On this board both share one unisolated
segment, so the SPD read for the second memory channel fails and the BIOS
drops that DIMM from the memory map.

Source: CWWK's official Q670/W680 FAQ — doc.x86pi.cn, space
`VXCQuW3XQSosL8RRJL2ixp`, page 235 ("插上PCIe网卡或者显卡就有一个内存不识别
… SMBus冲突导致"). A BIOS update does NOT fix this.

This is a board design shortcoming: reference designs isolate the PCIe
slot's SMBus pins from the DIMM SPD segment (mux/isolator or separate
segment); CWWK wired them together and documents pin-masking as the
workaround.

## Fix

Per node: full power-off, remove the ConnectX-4, apply a ~2 mm strip of
polyimide (Kapton) tape over edge-connector pins **B5 and B6** — B-side
(back) of the connector, 5th and 6th contacts from the bracket end,
before the notch. Do NOT cover B7 (wake/clock-req) or B3/B4 (power).
Reinstall, boot, verify.

Pin reference diagrams:
- https://pinouts.ru/Slots/pci_express_pinout.shtml
- https://en.wikipedia.org/wiki/PCI_Express#Pinout (B5/B6 = SMCLK/SMDAT)

## Trade-offs / Alternatives

- Taping B5/B6 keeps the NIC fully functional but prevents its low-power
  state (per CWWK; acceptable for always-on hypervisor NICs).
- Alternative 1: swap to a different NIC model (CWWK suggests Supermicro
  cards, closer to reference designs).
- Alternative 2 (worth trying FIRST — no teardown, reversible): disable
  the ConnectX-4's SMBus/NC-SI sideband in firmware via `mlxconfig` on
  the running node, if the firmware exposes the option. Same isolation,
  in software.

## Verification

    ssh root@10.10.0.1 'dmidecode -t memory | grep -E "Size|Locator"'
    ssh root@10.10.0.2 'dmidecode -t memory | grep -E "Size|Locator"'

Expected: both `...DIMM0` locators report 48 GB (96 GB total per node).

## Related

- docs/tickets/pve-q670-bios-upgrade.md (separate, optional BIOS work)
