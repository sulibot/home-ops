# Cloudflare Application Security mTLS

## Purpose

Migrate browser-facing applications from a Cloudflare Access WARP requirement
to Free-plan Application Security mTLS without exposing an application during
the transition.

This is not Cloudflare Access mTLS. Application Security mTLS accepts
certificates issued by Cloudflare's managed CA through either of two supported
device workflows:

1. a manually issued certificate installed directly in the operating-system
   or browser certificate store; or
2. the per-device certificate automatically provisioned by an enrolled
   Cloudflare One Client.

The same hostname association and WAF rule accept both certificate workflows.
The user's device profile determines whether the installed client runs in
Posture-only mode (certificate, no tunnel) or WARP mode (certificate plus the
narrow private application routes).

## Endpoint model

| Endpoint | Edge control | Client |
|---|---|---|
| `immich.sulibot.com` | Application Security mTLS, then Immich auth | Browser |
| `immich-app.sulibot.com` | Private DNS and WARP private routing | Immich native app |
| `freshrss.sulibot.com` | Application Security mTLS, then FreshRSS OIDC | Browser |
| `freshrss-app.sulibot.com` | Private DNS and WARP private routing | Google Reader/Fever client |
| Other approved browser candidates | Application Security mTLS after individual validation | Browser |
| Native/API endpoints without client-certificate support | WARP private routing | Native/API client |

Do not add `*-app.sulibot.com` endpoints to public Cloudflare DNS or a
Cloudflare Access application.

## User access profiles

Both certificate enrollment choices are intentionally available. Select the
least-capable profile that meets a user's needs:

| User/device need | Installation | Device profile | Network behavior |
|---|---|---|---|
| Browser mTLS only; no Cloudflare client desired | Manually issued client identity | Not enrolled | No Cloudflare tunnel |
| Browser mTLS only; automatic certificate lifecycle desired | Cloudflare One Client enrollment | Posture only | No application traffic or DNS is routed through WARP |
| Browser mTLS plus native/API apps | Cloudflare One Client enrollment | App access (WARP Include mode) | Only private `*-app.sulibot.com` gateway destinations use WARP |
| Infrastructure administration | Cloudflare One Client enrollment | Admin access (WARP Include mode) | App gateway destinations plus approved SSH, Kubernetes, OpenBao, storage, and management routes use WARP |

Device profiles use first-match precedence. Put the narrowly assigned
**Admin access** profile first, **App access** next, and **Posture only** after
them; leave the default profile at Posture only. Match the WARP profiles by
enrolled identity email or IdP group. A person who chooses a manual certificate
does not enroll and therefore does not match any device profile.

Do not reuse the consumer App access profile for infrastructure
administration. Narrowing the existing default profile to only application
gateways without first separating administrators would break SSH, `kubectl`,
`talosctl`, OpenBao, MinIO, and other private-network workflows.

### Split-horizon `*-app` routing

WARP does not connect in response to a URL. It remains connected, and Include
mode decides which destination traffic enters the tunnel.

For each private app endpoint:

1. Cloudflare Gateway DNS returns that app's private Cilium gateway address.
2. The App access profile includes only the exact gateway IPv4 `/32` and IPv6
   `/128` destinations used by those DNS overrides.
3. All other traffic bypasses WARP.

The policy intent is `*-app.sulibot.com`, but DNS overrides remain explicit
because names on cluster 101 and cluster 104 resolve to different gateways.
Do not use a single wildcard override for the zone.

Current mappings are:

| Private hostname | Remote/WARP destination |
|---|---|
| `hass-app.sulibot.com` | `10.104.250.11`, `fd00:104:250::11` |
| `immich-app.sulibot.com` | `10.101.250.11`, `fd00:101:250::11` |
| `freshrss-app.sulibot.com` | `10.101.250.11`, `fd00:101:250::11` |
| `vikunja-app.sulibot.com` | `10.101.250.11`, `fd00:101:250::11` |

Because multiple private apps share a gateway IP, including that gateway makes
the other routed hostnames on the same gateway network-reachable. TLS hostname
validation and application authentication remain required; this is routing
minimization, not per-host network isolation.

## GitOps source of truth

`terraform/infra/live/services/cloudflare-access/terragrunt.hcl` defines:

- the approved mTLS candidate inventory;
- `application_mtls_cutover_hostnames`, the per-host cutover set (currently
  piloting `immich.sulibot.com`);
- the Cloudflare-managed CA hostname association;
- the single zone custom-WAF rule that blocks missing, invalid, or revoked
  certificates;
- conditional removal of the old Access application; and
- the explicit WARP split-tunnel list for destinations that still require WARP.

The `sulibot-home-ops` API token needs these zone permissions:

- `SSL and Certificates: Edit`
- `Zone WAF: Edit`

The hostname-association resource owns the complete Cloudflare-managed CA
association set for `sulibot.com`. Reconcile any dashboard-created associations
before applying Terraform.

## Certificate handling

Issue separate certificates for people/devices and synthetic monitoring.
Never commit a private key or unencrypted PKCS#12 bundle.

For a human device:

1. In Cloudflare, open **SSL/TLS -> Client Certificates -> Cloudflare-issued**.
2. Create a certificate with the shortest practical validity that still permits
   reliable rotation.
3. Export it as PKCS#12 and install it in the operating-system certificate
   store.
4. Confirm the browser offers or automatically selects the certificate for the
   pilot hostname.
5. Store the recovery copy in 1Password and delete temporary plaintext files.

This manual workflow does not require the Cloudflare One Client and has no
enrollment step.

For automatic per-device certificates:

1. Enable device certificate provisioning for the zone through Cloudflare's
   documented `PATCH /zones/{zone_id}/devices/policy/certificates` API.
2. Assign the user's identity to either the Posture-only or App access device
   profile.
3. Install the Cloudflare One Client and enroll it into
   `sulibot.cloudflareaccess.com` through the configured identity provider.
4. Confirm the client-created identity is present in the operating-system
   certificate store.
5. With WARP traffic disconnected or in Posture-only mode, verify the browser
   can reach an mTLS hostname.
6. For an App access user, verify each approved `*-app` native client and
   confirm unrelated Internet traffic bypasses WARP.

The automatically provisioned identity is managed by the enrolled client.
Keeping it after uninstall is not a supported certificate lifecycle. Users who
do not want the client installed should use the manual workflow instead.

For API-based issuance, generate the private key and CSR outside Terraform so
the key cannot enter state:

```bash
umask 077
openssl ecparam -name prime256v1 -genkey -noout -out tls.key
openssl req -new -key tls.key -out tls.csr \
  -subj "/CN=<owner>-<device>-<yyyy>"
```

Submit the CSR through the Cloudflare Client Certificates API or dashboard.
Keep `tls.key` out of terminal output and shell tracing. Label the resulting
certificate in Cloudflare with the owner and device role.

### Device installation notes

- **macOS:** import a password-protected PKCS#12 identity into the login
  Keychain. Safari and Chromium browsers use Keychain identities; the browser
  may ask which certificate to present on first use.
- **iOS/iPadOS:** transfer the password-protected PKCS#12 through an approved
  secure channel, install the downloaded profile, then complete trust/profile
  installation in Settings. This installs a client identity, not a VPN.
- **Windows:** import the PKCS#12 file into the current user's Personal
  certificate store. Edge and Chrome use the Windows certificate store.
- **Android:** import the PKCS#12 as a VPN and app user certificate when the
  device permits it. Browser support varies by device/vendor.
- **Firefox:** confirm whether the deployed version uses the operating-system
  trust store or its own certificate database; import the identity separately
  when required.

Installation in the operating-system store does not guarantee that a native
third-party app will present the certificate. Use the paired WARP-private
endpoint for Immich, FreshRSS, Home Assistant, and similar native clients.

For Gatus, create a dedicated certificate and store these fields on the
`Kubernetes/gatus` 1Password item:

- `CLOUDFLARE_MTLS_CERTIFICATE`
- `CLOUDFLARE_MTLS_PRIVATE_KEY`
- `CLOUDFLARE_MTLS_EXPIRES_ON`

Mount the certificate and key read-only in Gatus and configure the positive
probe with:

```yaml
client:
  timeout: 10s
  tls:
    certificate-file: /config/mtls/tls.crt
    private-key-file: /config/mtls/tls.key
```

## Per-host cutover

Use one pilot hostname at a time. `immich.sulibot.com` is the first planned
pilot; `freshrss.sulibot.com` follows after its private app route is healthy.

1. Verify a certificate-bearing request reaches the app while the existing
   Access policy is still present.
2. Add a Gatus positive probe in group `apps-external-mtls` using the monitoring
   certificate.
3. Add a Gatus negative-control probe in group
   `security-negative-control` without a certificate. Its success condition
   must be `[STATUS] == 403`.
4. Add only the pilot hostname to
   `application_mtls_cutover_hostnames`.
5. Run:

   ```bash
   cd terraform/infra/live/services/cloudflare-access
   terragrunt plan
   ```

6. Confirm the plan:

   - associates only the pilot hostname with the managed CA;
   - creates or updates the one mTLS WAF rule;
   - removes only the pilot's Access application;
   - removes only the pilot from the public WARP include list; and
   - does not change unrelated Access, DNS, or WAF rules.

7. Apply during a staffed window.
8. Test from a network where WARP is disconnected:

   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' \
     https://immich.sulibot.com/auth/login

   curl --cert ./tls.crt --key ./tls.key \
     -sS -o /dev/null -w '%{http_code}\n' \
     https://immich.sulibot.com/auth/login
   ```

   The first request must return `403`. The certificate-bearing request must
   reach the application (normally `2xx` or an application redirect).

9. Verify the browser flow and the app's own authentication.
10. Verify the paired `*-app` endpoint through WARP from the native client.
11. Observe Gatus, Prometheus alerts, Cloudflare security events, and origin
    health before moving the next hostname.

For FreshRSS, also verify Google Reader/Fever sync through
`freshrss-app.sulibot.com`; API clients should not use the browser hostname.

## Monitoring contract

Each cut-over hostname requires:

- one positive mTLS probe (`apps-external-mtls`);
- one negative-control probe (`security-negative-control`);
- an internal/origin probe so an edge rejection can be distinguished from an
  application outage;
- certificate inventory with owner, serial, device, and expiry date; and
- rotation reminders at 30, 14, and 7 days.

Inventory certificate source as either `manual`, `cloudflare-one-device`, or
`service`. Manual and service certificates require explicit expiry reminders.
Enrolled-device inventory must instead alert on stale enrollment, missing
device certificate, and revoked/deleted device state.

The negative-control probe is healthy only when the edge denies it. An
unauthenticated `2xx` or redirect is a critical security incident.

Gatus reports the public server certificate expiry, not the client certificate
expiry. Client-certificate rotation reminders must therefore come from the
1Password inventory/automation or a dedicated certificate exporter; do not
mislabel the Gatus server-certificate metric as client-certificate coverage.

## Rotation and revocation

At 30 days before expiry, issue and distribute a replacement. Verify it with
the positive probe before removing the old identity. At 14 days, escalate any
device that has not moved; at 7 days, treat the remaining rotation as urgent.

For a lost or decommissioned device:

1. Revoke that device's certificate in Cloudflare immediately.
2. Verify the revoked certificate receives `403`.
3. Confirm other device and monitoring certificates still work.
4. Remove the recovery bundle from the device-management/1Password inventory.
5. Record the revocation, serial, owner, and reason in the incident or change
   record without attaching private material.

## Rollback

If certificate-bearing traffic cannot reach the application:

1. Restore the hostname's prior Access map membership by removing it from
   `application_mtls_cutover_hostnames`.
2. Plan and verify that the Access application returns before mTLS enforcement
   is removed.
3. Apply.
4. Confirm WARP access is restored and unauthenticated public access is still
   denied.
5. Keep the hostname out of the cutover set until the certificate or client
   compatibility problem is understood.

Do not manually delete the hostname association or WAF rule before the Access
application is restored.

## Troubleshooting

- **No certificate chooser:** confirm the identity contains both certificate
  and private key and is in the store used by that browser.
- **Certificate is offered but Cloudflare returns `403`:** confirm it was issued
  by the active Cloudflare-managed CA, is active, is not expired/revoked, and
  the hostname is in the Terraform association set.
- **Works without a certificate:** treat this as critical. Check the Terraform
  cutover set, hostname association, WAF rule status, DNS proxy status, and
  whether traffic bypassed Cloudflare.
- **Works only while WARP is connected:** check split-tunnel/profile
  propagation and public DNS. mTLS browser endpoints should bypass WARP after
  cutover.
- **Native app fails:** move it to the paired `*-app.sulibot.com` endpoint and
  verify WARP private DNS/routing. Do not weaken the browser mTLS rule.
- **TLS-inspection product or second VPN interferes:** temporarily disable that
  interception for the pilot test, then add the narrowest compatible
  exclusion. Do not export the private key to the interception product.
