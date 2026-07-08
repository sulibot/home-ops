# Proxmox ACME

This stack adopts Proxmox ACME account and DNS plugin configuration only.

Node certificate orders are intentionally not managed here yet. Each node already
has ACME domain metadata in Proxmox, and certificate issuance/renewal can restart
or alter node UI/API certificate handling.

Existing live objects:

- ACME account: `default`
- DNS plugin: `cloudflare`

Cloudflare credentials are read from `common/secrets.sops.yaml`.

## Certificate Reissue Test

Test certificate reissue later as a controlled maintenance action, one node at a
time:

1. Add a temporary `proxmox_acme_certificate` for one node only.
2. Plan and confirm it will touch only that node certificate.
3. Apply during a maintenance window.
4. Verify the Proxmox UI/API and `pveproxy` health on that node.
5. Repeat for the remaining nodes after the first node is boring.

Do not enable `force = true` except for an explicit one-time renewal test.

## Reissue Test Result

`pve03` was tested on July 7, 2026 with:

```sh
pvenode acme cert order --force 1
```

The DNS-01 challenge completed successfully through the `cloudflare` plugin,
`pveproxy` reloaded successfully, and the node-local TLS endpoint served the new
certificate:

- subject: `CN=pve03.sulibot.com`
- issuer: Let's Encrypt `YR2`
- not before: July 7, 2026 22:18:06 UTC
- not after: October 5, 2026 22:18:05 UTC
- SHA-256 fingerprint:
  `D9:25:A7:D3:5D:26:A9:7A:1D:51:70:1B:84:5D:19:C7:F2:D6:75:35:D7:40:1F:70:10:A4:9F:9A:C0:B5:1C:85`

Note: from the workstation, `pve03.sulibot.com` resolved to `fd00:10::3`, while
`pve03` itself resolved the same name to `fd00:0:0:ffff::3`. The node-local
check against `127.0.0.1:8006` verified the new certificate on the actual
Proxmox node.

`pve01` and `pve02` were tested the same way on July 7, 2026. The DNS-01
challenge, certificate install, and `pveproxy` restart completed successfully on
both nodes. Let's Encrypt returned the already-installed certificates:

- `pve01.sulibot.com`: valid June 5, 2026 09:21:19 UTC through September 3,
  2026 09:21:18 UTC, SHA-256 fingerprint
  `26:BF:06:18:5E:1D:6E:ED:CA:00:3C:71:55:DB:9E:4A:1A:03:46:1D:93:36:DA:5B:A0:26:86:A8:5F:46:1D:CF`
- `pve02.sulibot.com`: valid June 5, 2026 10:32:41 UTC through September 3,
  2026 10:32:40 UTC, SHA-256 fingerprint
  `36:FC:1E:57:14:3A:2E:C1:77:6A:48:6E:48:DD:E8:99:9E:8D:E5:44:33:BE:2A:B3:90:54:BE:FB:BB:D5:4B:E5`

The RouterOS DNS records for `pve01.sulibot.com`, `pve02.sulibot.com`, and
`pve03.sulibot.com` should point at the infra loopbacks
`fd00:0:0:ffff::1/2/3`, matching the node-local Proxmox resolver view.
