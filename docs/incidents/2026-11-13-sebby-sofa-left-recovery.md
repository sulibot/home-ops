# Sebby Bedroom Sofa Left recovery attempt, 2026-11-13

## Result

Sofa Left remains unavailable. Its existing Home Assistant entity, Matter node,
and pairing credentials are preserved. Sebby Bedroom Standing Lamp 1 and Standing
Lamp 2 recovered during the controller recovery. Direct Matter reads succeeded
for Sofa Right and both standing lamps; Sofa Left did not reply.

The user confirmed Sofa Left is physically lit and imposed a 20-minute limit.
A single 10-second power-off/on was requested, without a factory reset or
recommissioning. Completion of that physical step was not confirmed during the
investigation. The room's Kasa wall dimmer reported brightness 2/255; whether it
actually supplies power to this lamp is unknown. Its setting was not changed.

## Identity and observations

- Cluster: `cluster-104`, Talos node `talos01`.
- Entity: `light.kajplats_e26_ws_globe_1600lm_6`, name `Sofa Left`.
- Matter node: decimal 16, logged as `@1:10`; device firmware 1.2.0.
- Thread extended address from cached diagnostics: `0a091c07d11f27b3`.
  It was absent from the inspected OTBR router/neighbor tables.
- Old commissioning hint: `fd09:7aa3:6ab9:0:1254:cff4:60e9:c6c1`.
- Cached mesh-local address: `fdf1:49b9:b55e:5844:dcbe:e227:aca0:1c20`.
- Current Thread OMR prefix: `fd55:ae20:5b9c:1::/64`; the old address followed
  the host's normal LAN default route. Fresh mDNS lookup supplied no replacement.
- OTBR remained leader and other Thread bulbs answered Matter requests.

## Work performed

1. Verified HA's entity and device registrations and compared Sofa Left with
   working Sofa Right. Targeted reads and an interview initially returned
   `Operation aborted`.
2. Restarted only Matter Server, preserving its PVC and fabric data.
3. Tested a temporary `/128` route for the old address through `wpan0`; the read
   still failed. Removed that route in the test's `finally` handler.
4. Located the earlier address-seeding recovery in
   `docs/tickets/cluster-104-matter-server-migration.md`.
5. Tested storage access on a private copy. This server uses WAL storage, unlike
   the flat-file layout described in the July incident. Opening with the Node.js
   default driver migrates the copy to `file`; explicitly select `wal` for live
   maintenance. No migration was applied to live storage.
6. Scaled Matter Server to zero and waited for its pod to exit. Backed up the
   complete `server-1-fff1` directory to
   `/data/repair-backups/20261113-sofa-left/server-1-fff1` on its PVC.
7. Used the installed Matter.js `StorageService` with `configuredDriver` and
   `defaultDriver` both set to `wal`. Changed only
   `nodes / peer16 / endpoints / 0 / commissioning / addresses` to the mesh-local
   UDP address above, port 5540. Original/new values are recorded in
   `/data/repair-backups/20261113-sofa-left/address-change.json`.
8. Closed storage and restored the deployment to one replica in a `finally`
   handler. Verified readiness and that logs used the repaired address.
9. Removed the temporary maintenance pod. No physical light commands, fabric
   resets, commissioning changes, or OTBR restarts were issued.

For a future address rollback, stop the server and use the same WAL API to restore
only the recorded `addresses` value. Do not replace the entire fabric store with
the backup after the server has resumed writing. The old address was unrouted,
so restoring it is not expected to repair current connectivity.
