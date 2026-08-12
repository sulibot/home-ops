# pve01/02: CWWK Q670 BIOS Upgrade (Optional — ACPI Errors, Dead I226-V Port)

## Status (2026-07-16)

Open, deliberately deferred. NOT required for the DIMM/SMBus issue (see
pve-q670-dimm-smbus-conflict.md — that fix is hardware-level). Only worth
doing if the symptoms below become painful. CWWK explicitly warns against
casual BIOS updates: no dual-BIOS, no flash recovery short of an SPI
programmer. Linear issue not created (workspace free-issue limit reached).

## Current State

- Both nodes: BIOS 5.27, dated 2024-05-13 (board CW-Q670-NAS, rev
  CW2024-511). `dmidecode` Form Factor `DIMM` rules out the SO-DIMM
  `-8P-4M2` variant (wrong image, do not flash it). Owner confirms the
  boards have 8 discrete SATA ports (not 2x SFF-8643), which matches the
  **CW-NAS-Q670-2L-Black-8SATA** variant (black PCB; compare
  `~/Desktop/black_board.png`), NOT the white "Plus" board.

## Symptoms a newer BIOS may fix

1. Kernel ACPI error spam (`ACPI BIOS Error ... AE_NOT_FOUND`) — CWWK
   ships a dedicated fix image for exactly this.
2. `enp3s0` (onboard Intel I226-V) is DOWN/dead on both nodes — forum
   thread 18348 attributes this symptom class to old/wrong BIOS.

## BIOS Source (vendor file server)

drive.x86pi.cn (ZFile; also mirrors to Aliyun OSS with signed URLs).
Correct folder for this board (Black 8-SATA variant):
`BIOS/5.NAS-BIOS/Q670-H670-NAS/CW-NAS-Q670-2L-Black-8SATA/`

- `CW-NAS-Q670-2L-Black-CWLOGO.iso` — Black-8SATA build (Sep 2025)

(The white "Plus"/SFF-8643 variant images live in `CW-NAS-Q670-2L/`:
`CW-NAS-Q670-2L-8P.iso`, `CW-NAS-Q670-Plus-2L-ACPI-fix.iso` — do NOT
flash those on the Black board without CWWK confirming compatibility.
If in doubt, email cwwkstore@gmail.com with a photo of the board
silkscreen and current BIOS version.)

API to re-fetch fresh download URLs:

    curl -s -X POST 'https://drive.x86pi.cn/api/storage/files' \
      -H 'Content-Type: application/json' \
      -d '{"storageKey":"BIOS","path":"/5.NAS-BIOS/Q670-H670-NAS/CW-NAS-Q670-2L-Black-8SATA","password":""}'

Both ISOs are bootable EFI flashers (boot from USB → auto-runs
`Fpt.efi -F 1.bin`).

## Procedure (when/if executed)

1. Physically confirm board matches reference photo (black PCB, 2
   vertical U-DIMM slots, 8 stacked right-angle SATA ports on right
   edge, x16 slot on bottom edge) — `~/Desktop/black_board.png`.
2. BIOS → Chipset → PCH-IO Configuration → Security Configuration →
   **BIOS Lock → Disabled** (flash fails "write prohibited" otherwise).
3. Write ISO to USB, boot it (F11), let the flasher run; do NOT cut
   power mid-flash.
4. Load BIOS defaults (F5), reconfigure, verify:
   `dmidecode -s bios-version` and `dmesg | grep -i acpi` and
   `ip -br link` (I226-V state).

Remote options: board has vPro/AMT (I226-LM) — if AMT is provisioned,
MeshCommander gives KVM + virtual-media boot of the flash ISO. Intel FPT
for Linux can flash from the running OS but has zero recovery margin;
prefer AMT or physical.

## Related

- docs/tickets/pve-q670-dimm-smbus-conflict.md
