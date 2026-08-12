# Draft: reply to Jessica re: wrong BIOS file (not sent)

Related: [pve-q670-cwwk-warranty-email.md](pve-q670-cwwk-warranty-email.md), [pve-q670-bios-upgrade.md](pve-q670-bios-upgrade.md)

## Body

Hi Jessica,

Thanks for the quick turnaround. Before I flash anything, I noticed a
couple of things in the file you sent (wetransfer_update-bios.zip,
CW-NAS-Q670-2L-PQ.iso) that I want to confirm before proceeding, since
this board has no dual-BIOS recovery:

1. The embedded `motherboard.txt` inside the ISO identifies the target
   board as `CW-NAS-Q670-2L-PQ-CWLOGO`. My boards are the
   `CW-NAS-Q670-2L-Black-8SATA` variant (black PCB, 8 discrete SATA
   ports, confirmed against your own reference photo previously). Is
   "PQ" a compatible/equivalent build for my board, or is this the
   wrong file for my variant?

2. The same file lists `BIOS Date: 05/13/2024` — which matches the
   BIOS I'm already running (5.27, dated 2024-05-13), not a newer
   version. The `.bin` payload's file timestamp is also May 2024. Is
   this actually a newer build that addresses the memory issue, or did
   an older/generic template get attached by mistake?

For reference, the file details:
- ISO: CW-NAS-Q670-2L-PQ.iso, volume label 20251113_091136
- Firmware payload: CW-TY-BIOS/bios/CW-Q670-NAS_0511.bin
- SHA256: 60377db8979b62f9d755e17eedb008a3f89be60c2036d942285da2d45634af36

I want to make sure I flash the correct build for
CW-NAS-Q670-2L-Black-8SATA before proceeding — could you confirm or
resend the correct file?

Thanks,
Sulaiman Ahmad
sulibot@gmail.com
