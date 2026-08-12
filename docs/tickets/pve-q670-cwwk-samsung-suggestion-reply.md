# Draft: reply to Jessica re: "try Samsung memory" (not sent)

Related: [pve-q670-dimm-smbus-conflict.md](pve-q670-dimm-smbus-conflict.md), [pve-q670-cwwk-cwwk-r-and-d-reply.md](pve-q670-cwwk-cwwk-r-and-d-reply.md)

## Body

Hi Jessica,

I looked into the Samsung suggestion, and a genuine Samsung-branded
48GB DDR5-5600 desktop U-DIMM doesn't appear to exist as a real retail
product — Samsung's own retail DDR5 U-DIMM lineup tops out around
16GB per module. The "48GB Samsung" listings that do exist are either
third-party modules merely claiming compatibility with a Samsung part
number, or pulled server/laptop-form-factor Samsung chips (RDIMM or
SO-DIMM, not desktop U-DIMM — physically incompatible with this board
regardless). That's not something I can practically go buy and test.

It also doesn't fit the evidence I already have. The same Crucial 48GB module works perfectly when installed in
Controller0/DDR5_1 — full detection, correct size, stable, on both of
my boards. It only fails when placed in Controller1/DDR5_2, where it
hard-fails POST outright, alone, with nothing else installed. If
Crucial's compatibility were genuinely worse than Samsung's at 48GB,
the same module should show some sign of difficulty in the channel
where it currently works — not run flawlessly in one channel and fail
completely in the other. A module-compatibility explanation predicts
trouble in both channels, or neither. What I'm seeing is one channel
working perfectly and the other never working, with the identical
hardware. That points at a fault specific to the DDR5_2/Controller1-
ChannelA channel itself, not the memory module.

I'd also note that your own team has previously confirmed Crucial
memory as compatible with this board on your community forum — a
customer running a Crucial module on this same board family was told
by your staff "your current memory, motherboard, and CPU all support
up to 5600 MT/s... you are using 1R memory, which fully meets the
requirements" (x86pi forum, topic 18470). Crucial hasn't been flagged
as an unsupported brand before now.

I'd also point out that Crucial is not an obscure or boutique brand —
it's owned by Micron, one of the world's three major DRAM
manufacturers, and a 48GB DDR5-5600 U-DIMM is one of the most common
choices available right now for this capacity class.

More broadly: if your advertised memory capacity (96-128GB depending
on listing) only actually works with one specific vendor's modules,
and that requirement was never disclosed anywhere at time of purchase,
that's functionally the same as the product not performing as
advertised — regardless of the specific technical mechanism behind it.

Given everything ruled out so far (bad module, memory speed,
BIOS version, single-unit defect, and now module brand), here's what
I'm looking for, in order of preference:

1. A configuration on my current boards that actually works with the
   memory I have.
2. If that's not possible, a credit toward a different board in your
   lineup that takes U-DIMM memory and would actually work with what
   I already own — you'd know better than me which of your boards, if
   any, would fit that. A straight replacement with another unit of
   the same board isn't useful on its own, since this reproduces
   identically across two independently purchased units.
3. If neither of those is available, a full refund for both boards so
   I can purchase something that performs as advertised.

Please let me know how you'd like to proceed.

Thanks,
Sulaiman Ahmad
sulibot@gmail.com
