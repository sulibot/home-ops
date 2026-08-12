# Draft: CWWK/StoneStorm warranty claim (not sent)

Send via: Amazon "Contact seller" → StoneStorm (both boards sold by
this seller, per order history — not CWWK's own store, so this is the
right channel rather than cwwkstore@gmail.com or sales@cwwkpc.com)

Related: [pve-q670-dimm-smbus-conflict.md](pve-q670-dimm-smbus-conflict.md), [pve-q670-cwwk-support-draft.md](pve-q670-cwwk-support-draft.md)

## Subject
Warranty claim: 2x Q670 8-Bay NAS motherboards (orders 113-9752832-8679421, 113-9193670-0281016) — second memory channel non-functional on both units

## Body

Hello,

I'd like to file a warranty claim for two Q670 8-Bay NAS Mini-ITX
motherboards purchased from StoneStorm on Amazon:

- Order #113-9752832-8679421 (Aug 2, 2024) — the original unit from
  this order was returned unused within Amazon's 30-day window for an
  unrelated packaging issue (missing grommet), not a technical fault,
  and replaced. The replacement unit is what's showing the DDR5_2
  issue described below.
- Order #113-9193670-0281016 (Sep 9, 2024) — second unit, purchased
  new.

Both boards exhibit the identical defect, confirmed through extensive
isolated testing across both units.

**Issue 1 — second memory channel (DDR5_2) does not work.** Your
listing advertises "2x DDR5 MAX 128GB." I'm running 2x Crucial
CP48G56C46U5 48GB DDR5-5600 U-DIMM (96GB total, from the Crucial Pro
96GB kit CP2K48G56C46U5) — well within your advertised maximum, not
beyond it. On both boards, the second channel (DDR5_2) fails to be
detected under every configuration tested: NIC installed or fully
removed, memory speed at Auto, 4400MHz, and CWWK's own documented
4200MHz recommendation for 2R-rank memory. In isolation (single DIMM
in DDR5_2 alone, nothing in DDR5_1), the board fails POST outright
with a 1 long + 3 short beep code (base 64K RAM failure) — on both
units. The only working configuration is a single DIMM in DDR5_1
alone — 48GB instead of the advertised 128GB max / 96GB installed.

These are two separate physical units — one a replacement sent after
an unrelated packaging return, one purchased new — showing the
identical fault, which points to this being a systemic issue rather
than a single bad unit.

**Issue 2 — end goal: 96GB + a PCIe NIC installed simultaneously.** My
target configuration is both DIMMs populated (96GB) *and* a Mellanox
ConnectX-4 Lx NIC in the PCIe x16 slot at the same time. Even setting
the memory-channel issue aside, CWWK's own FAQ documents a separate
SMBus conflict between the PCIe slot and DIMM SPD detection when any
PCIe card is installed, requiring a physical tape mask on the card's
B5/B6 edge pins as a workaround. So there are two compounding issues
between me and the board's advertised capability: DDR5_2 not working
at all, and a documented card/memory interaction on top of that. I
need both resolved (or a working replacement) to reach the
configuration these boards are sold for.

Full test matrix, run across both boards:

- NIC out, both DIMMs, Auto speed: Board 1 fails, Board 2 not tested
- NIC out, both DIMMs, DIMM swap between slots: Board 1 fails (follows
  the slot, not the DIMM), Board 2 not tested
- NIC out, both DIMMs, 4200MHz cap: Board 1 not tested, Board 2 fails
- NIC in, both DIMMs, Auto speed: Board 1 fails, Board 2 fails
- NIC in, both DIMMs, 4400MHz cap: Board 1 not tested, Board 2 fails
- NIC in, both DIMMs, 4200MHz cap (your documented recommendation for
  2R memory): Board 1 fails, Board 2 fails
- NIC in, single DIMM in DDR5_2 alone: Board 1 hard POST failure (1+3
  beep), Board 2 hard POST failure (1+3 beep)
- NIC in, single DIMM in DDR5_1 alone: Board 1 works (48GB only),
  Board 2 not tested

Every combination of {NIC in/out} x {Auto/4400/4200MHz} fails to
detect DDR5_2 with both DIMMs installed. Swapping which physical DIMM
occupies DDR5_2 didn't change the outcome — the fault follows the
slot, not the module. In isolation, DDR5_2 alone produces a hard base
64K RAM failure (1 long + 3 short beeps) on both boards, not just a
"not detected" status. Happy to send video/photos of the beep-code
failures too.

Given both boards fail identically, I'd like to request repair or
replacement under warranty for both units. I understand your published
2-year warranty page doesn't distinguish between direct-site and
Amazon marketplace purchases — please confirm that coverage applies
here, since both units were purchased through your StoneStorm
storefront on Amazon rather than cwwk.net directly.

I'd appreciate a prompt response — the Aug 2, 2024 order is nearing
the 2-year mark from date of receipt, and I want to make sure this
claim is filed within the warranty window.

Let me know what you need from me beyond the order numbers above.

Thanks,
Sulaiman Ahmad
sulibot@gmail.com
