# Draft: CWWK support inquiry (not sent)

Related: [pve-q670-dimm-smbus-conflict.md](pve-q670-dimm-smbus-conflict.md)

## Subject
CW-NAS-Q670-2L-Black-8SATA: Controller1-ChannelA/DDR5_2 fails on two independent boards, reproducible with single-DIMM isolation test

## Body

Hello,

We have two CW-NAS-Q670-2L-Black-8SATA boards (BIOS 5.27 / 2024-05-13),
both running Proxmox, each populated with 2x Crucial CP48G56C46U5
(48GB DDR5-5600 U-DIMM) and a Mellanox ConnectX-4 Lx dual-port NIC in
the PCIe x16 slot.

**Original symptom (both boards):** with the ConnectX-4 installed,
`dmidecode -t memory` shows only Controller0-ChannelA-DIMM0 (48GB);
Controller1-ChannelA-DIMM0 reports "No Module Installed." This matches
the SMBus conflict described in your FAQ (page 235, "插上PCIe网卡或者显卡
就有一个内存不识别了") — the ConnectX-4's management sideband shares
SMBus with DIMM SPD detection via PCIe edge pins B5/B6. We applied the
documented tape fix (masking B5/B6, B-side only, verified against your
own reference photo) to both boards.

**Finding 1 — dropout persists with the card fully removed.** On
pve01, with the ConnectX-4 completely out of the slot, both DIMMs
installed, Controller1-ChannelA-DIMM0 still reports "No Module
Installed." Swapping the two physical DIMMs between slots showed the
"missing" status stays with the slot, not the module.

**Finding 2 — reproducible on a second, independent board.** We
applied the same tape fix to pve02 and ran the same tests. Identical
result: Controller1-ChannelA-DIMM0 not detected with both DIMMs
installed, regardless of card presence.

**Finding 3 — single-DIMM isolation test fails POST outright, on both
boards.** With only one known-good DIMM installed — moved into
Controller1-ChannelA/DDR5_2 alone (DDR5_1 left empty) — both pve01 and
pve02 fail POST with the identical beep pattern: **1 long beep followed
by 3 beeps** (base 64K RAM failure on standard AMI codes), no splash.

**Finding 4 — not resolved by frequency capping, including your
documented recommended value.** Per your FAQ's guidance for 2R/4R
memory boot failures (page 235: cap speed to 4200MHz or lower via
"Maximum Memory Frequency"), we tested both 4400MHz and the exact
4200MHz value you recommend. Our DIMMs are confirmed 2-rank
(`Number of Ranks: 2` in BIOS) — matching the profile your FAQ flags.
Neither speed allows Controller1-ChannelA/DDR5_2 to be detected, either
in isolation (still 1+3 beep failure at 4200MHz) or alongside DDR5_1.

For reference, our board's advertised spec is dual-channel U-DIMM DDR5
with a 96GB max (2x48GB) — we're configured at exactly the advertised
maximum, not beyond it.

We also found one community report (NAS Compares review comments,
CWWK Q670/H670 8-Bay board) of a related but distinct issue: a user
running the H670 variant with 96GB (2x48GB) and a single-port
100GbE ConnectX-4 reported the second memory bank being ignored only
while that specific high-bandwidth card was installed, resolved by
switching to a lower-bandwidth NIC. That case is card-dependent and
resolved by a card swap; ours reproduces with the card fully removed,
so it doesn't look like the same root cause, but we mention it as
another data point of memory-channel/PCIe-card interaction reports on
this board family.

Given this reproduces identically across two independent units,
purchased about a month apart (different likely manufacturing
batches), under identical isolation conditions and across the full
range of speeds your own documentation suggests trying, we don't
believe this is two coincidentally defective boards — it looks like a
board-model-level issue specific to the Controller1-ChannelA/DDR5_2
channel, either in BIOS memory training/init or a board design
characteristic, distinct from (or compounding) the documented
SMBus/PCIe-card conflict.

**Tape fix status:** separately, we saw one instance of a long delay
and beep with no console after reinstalling a B5/B6-taped ConnectX-4,
which resolved after repositioning the tape and retrying. We're not
fully confident that was a real tape/seating issue rather than normal
extended memory retraining after a hardware change (which we've
since learned can also present as a long beep and delay before a
successful boot) — we didn't control for that at the time. Not raising
this as a confirmed open issue either way, just flagging we can't
positively confirm the tape fix caused the improvement. Separately, we
did see independent forum confirmation of the same documented SMBus
fix working for a different PCIe card (HBA) in your thread
"Cannot use pcie HBA on Q670 motherboard?" (topicId 18440).

Questions:
1. Is a hard POST failure (1+3 beep, base 64K RAM failure) on
   Controller1-ChannelA/DDR5_2 in isolation, persisting across the full
   documented frequency range (Auto, 4400, 4200MHz), a known issue with
   this board model? Is there a BIOS setting beyond memory frequency
   (training algorithm, safe mode, etc.) that resolves it?
2. With both channels populated, is there a required population order
   or complementary setting for 2-DIMM configs on the 2-slot variant,
   similar to what your FAQ documents for the 4-slot Q670 boards
   (page 235, DIMM 1-4 slot-preference table)? We couldn't find
   equivalent guidance for the 2-slot ("2L") variant.
3. Is this a known issue with a fix in a newer board revision, or in
   BIOS newer than 5.27 (2024-05-13)? We see a Sep 2025 image
   (CW-NAS-Q670-2L-Black-CWLOGO.iso) on your file server but no BIOS
   changelog — before we flash (we're aware there's no dual-BIOS
   recovery on this board, so we want to confirm it's worth the risk
   first), can you confirm whether that build addresses
   Controller1-ChannelA/DDR5_2 detection, or point us to a changelog?
4. We're evaluating whether to continue troubleshooting these two
   units or replace them, and would rather not buy the same board
   revision if the issue is already fixed in current production.

We're holding off on further hardware purchases until we hear back,
since this now looks like something you may already have a fix,
revision change, or BIOS update for.

Thanks,
[name / contact]
