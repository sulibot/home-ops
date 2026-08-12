# Draft: reply to Jessica re: "2x48GB tested in R&D" (not sent)

Related: [pve-q670-dimm-smbus-conflict.md](pve-q670-dimm-smbus-conflict.md), [pve-q670-cwwk-bios-result-reply.md](pve-q670-cwwk-bios-result-reply.md)

## Body

Hi Jessica,

I appreciate you checking, but I don't think a memory compatibility
explanation fits what I'm actually seeing, and I want to make sure
this is clear before more time goes by waiting on tester responses.

The key test: I put a single 48GB module — by itself, nothing in the
other slot — into DDR5_2/Controller1-ChannelA alone. This isn't a
"two modules together" scenario at all. It still fails POST outright,
with a 1 long + 3 short beep code (base 64K RAM failure), on both of
my boards. If this were a compatibility issue specific to combining
two 48GB modules, a single module alone in that channel should work
fine — compatibility concerns about pairing two modules together
can't explain a single module failing alone in one specific channel.
This points at something wrong with the DDR5_2/Controller1-ChannelA
channel itself, independent of module count or pairing.

To be clear about what's been ruled out at this point:
- Not a bad DIMM (swap test: the failure follows the slot, not the
  module)
- Not a memory speed issue (fails at Auto, 4400MHz, and your
  documented 4200MHz recommendation)
- Not a BIOS issue (fails on the original BIOS and your updated
  11/27/2024 build)
- Not a single-unit defect (identical failure on two independent
  boards, purchased separately)
- Not a "two 48GB modules together" compatibility issue (fails with
  a single 48GB module alone in that channel)

I'd like to move forward with repair or replacement under warranty
for both units rather than wait on a compatibility explanation that
doesn't match the actual failure pattern. Please let me know how
you'd like to proceed.

Thanks,
Sulaiman Ahmad
sulibot@gmail.com
