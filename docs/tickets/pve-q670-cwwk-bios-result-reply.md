# SENT: Amazon seller-message reply to Jessica (2026-07-22)

Context: this is the NEXT message in the existing Amazon seller-message
thread with StoneStorm/Jessica — not a fresh email. The prior message
(BIOS flash results on pve02 only, sent Jul 22 2:40 AM) has already
been sent; do not resend that content. This reply only needs to:
answer her CPU question, and add what's changed since (pve01 also now
flashed, plus the byte-identical "latest" file finding). Amazon
message box has a 4000 character limit — this draft is well under it.

Related: [pve-q670-dimm-smbus-conflict.md](pve-q670-dimm-smbus-conflict.md), [pve-q670-cwwk-warranty-email.md](pve-q670-cwwk-warranty-email.md)

## Body

Hi Jessica,

The CPU is an Intel Core i5-14500 (RaptorLake DT, 6P-cores/8E-cores).
Per Intel ARK, it officially supports up to 192GB max memory, well
above the 96GB I'm running, so that's not a limiting factor.

Update since my last message: I've now flashed the BIOS build you
sent to both boards (not just one) — both flashes completed cleanly
(FPT "Operation Successful," verified identical), both confirmed
running Build Date 11/27/2024 via BIOS setup and dmidecode. Result is
unchanged on both: with both memory modules installed, the second
channel (DDR5_2 / Controller1-ChannelA) still reports "No Module
Installed" on both units.

One more data point: I checked the "latest" build currently on your
public file server, and its firmware payload is byte-for-byte
identical (same SHA256 hash) to the first mismatched file you
originally sent me — same internal "PQ"-labeled identifier, same
05/13/2024 internal BIOS date. So despite a September 2025 upload
date, it's not actually different firmware from what was already
installed.

To summarize: two independent boards, advertised-spec configuration
(2x48GB, within your stated 96-128GB max), reproducible failure across
every memory speed you've suggested (Auto, 4400MHz, 4200MHz), and now
both boards on your updated BIOS with no change. If you have a
different build that actually addresses this, I'm willing to try it —
otherwise I'd like to move forward with repair or replacement under
warranty for both units.

Thanks,
Sulaiman
