# Cloudflare Application Security mTLS

## Purpose

Migrate browser-facing applications from a Cloudflare Access WARP requirement
to Free-plan Application Security mTLS without exposing an application during
the transition.

This is not Cloudflare Access mTLS. Application Security mTLS accepts
certificates issued by Cloudflare's managed CA. The supported user workflow is
a manually issued certificate installed directly in the operating-system or
browser certificate store.

Cloudflare One Client device-certificate provisioning is disabled. Enrolling
the client provides WARP access to private `*-app.sulibot.com` endpoints; it
does not provide a browser mTLS identity.

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

| User/device choice | Installation | At home (`io`/`iot`) | Away from home |
|---|---|---|---|
| Manual browser identity only | Install a manually issued PKCS#12 identity | No Cloudflare client or tunnel | Browser mTLS works; private `*-app` endpoints are unavailable |
| Manual identity plus private app access | Install the manual identity and enroll Cloudflare One Client | WARP Include mode carries only configured private app routes | The manual identity serves browser mTLS and WARP serves private app/API routes |

These are the only two supported choices. There is no posture-only,
managed-network, or automatically provisioned browser-identity path.

The external default still contains the previously approved infrastructure
routes in addition to the private app gateways. A separate technical-debt issue
owns selecting a durable per-device Admin/App role signal before those
infrastructure routes can be removed from the default. Do not infer privilege
from operating system or platform.

A person who chooses a manual certificate does not need to enroll in WARP.
Enrolled devices use the same Include-mode profile on every network.

Do not reuse the consumer App access profile for infrastructure
administration. Narrowing the existing external default profile to only
application gateways without first solving device-role assignment would break
SSH, `kubectl`, `talosctl`, OpenBao, MinIO, and other private-network workflows.

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
  `immich.sulibot.com` and `freshrss.sulibot.com`);
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

The non-secret Apple device inventory is
`config/cloudflare-mtls-devices.json`. It deliberately contains stable friendly
IDs rather than Apple serial numbers or UDIDs:

| Device ID | Owner | Platform | Description |
|---|---|---|---|
| `sulibot-ganymede` | sulibot | macOS | This Mac |
| `sulibot-secondary-mac` | sulibot | macOS | Second Mac |
| `sulibot-iphone` | sulibot | iOS | iPhone |
| `sulibot-ipad` | sulibot | iPadOS | iPad |
| `ashley-mac` | ashley | macOS | Mac |
| `ashley-iphone` | ashley | iOS | iPhone |

List the authoritative inventory before operating:

```bash
scripts/cloudflare-mtls-device.sh list
```

Each device gets an independent certificate. This makes one lost device
revocable without disrupting the other five. Do not share one person's
certificate across their devices.

### One-time automation bootstrap

1. Create a narrowly scoped Cloudflare API token with `SSL and Certificates:
   Edit` for `sulibot.com`. The device script uses the Cloudflare client
   certificate API; it never puts private key material in Terraform state.
2. Run `terraform/infra/live/services/openbao/configure-integrations.sh`. This
   installs the `cloudflare-mtls` policy, the local `mtls` AppRole, and the
   GitHub OIDC role.
3. Store `cloudflare_api_token` and `cloudflare_zone_id` at
   `kv/automation/cloudflare-mtls/config`. Enter the token through a hidden
   prompt so it is not placed in shell history:

   ```bash
   read -r -s -p "Cloudflare mTLS API token: " CF_MTLS_TOKEN
   printf '\n'
   read -r -p "Cloudflare zone ID: " CF_MTLS_ZONE_ID
   config_file="$(mktemp)"
   chmod 0600 "$config_file"
   jq -n \
     --arg token "$CF_MTLS_TOKEN" \
     --arg zone "$CF_MTLS_ZONE_ID" \
     '{cloudflare_api_token:$token,cloudflare_zone_id:$zone}' \
     >"$config_file"
   bao kv put -mount=kv automation/cloudflare-mtls/config @"$config_file"
   unset CF_MTLS_TOKEN CF_MTLS_ZONE_ID
   find "$config_file" -type f -delete
   ```

4. Create a 1Password service account that can read and write only the
   `Kubernetes` vault, then add its token to the same OpenBao configuration.
   This is the one-time trust bootstrap that lets the self-hosted runner create
   a real 1Password Document without an interactive desktop-app session:

   ```bash
   OP_MTLS_TOKEN="$(
     op service-account create cloudflare-mtls-delivery \
       --vault Kubernetes:read_items,write_items \
       --raw
   )"
   delivery_file="$(mktemp)"
   chmod 0600 "$delivery_file"
   jq -n \
     --arg token "$OP_MTLS_TOKEN" \
     --arg vault "Kubernetes" \
     '{
       onepassword_service_account_token: $token,
       onepassword_vault: $vault
     }' >"$delivery_file"
   bao kv patch -mount=kv \
     automation/cloudflare-mtls/config \
     @"$delivery_file"
   unset OP_MTLS_TOKEN
   find "$delivery_file" -type f -delete
   ```

   1Password returns a service-account token only once. Do not print it or put
   it in a GitHub secret. OpenBao holds the automation credential; the
   service account itself is restricted to the delivery vault.

5. Create a protected GitHub environment named
   `cloudflare-mtls-issuance` and a second environment named
   `cloudflare-mtls-monitoring`. Restrict both to `main`; the OpenBao JWT roles
   also verify the repository, workflow, branch, and self-hosted runner. The
   issuance role additionally binds the immutable owner/actor IDs.

### Issue and deliver a human-device identity

Run **Cloudflare mTLS Device** in GitHub Actions, choose `issue`, and select a
device ID. The workflow:

1. derives owner and platform from the committed inventory;
2. creates the private key and CSR only on the self-hosted runner;
3. asks Cloudflare to sign the CSR;
4. packages the identity in a device-specific `.mobileconfig`:
   - macOS profiles set `AllowAllAppsAccess` to `true` and
     `KeyIsExtractable` to `false`;
   - iOS/iPadOS profiles omit those macOS-only keys;
   - all Apple profiles use the legacy-compatible PKCS#12 container encoding
     required by Apple profile installation; OpenSSL 3's PBES2/AES defaults
     cause **The certificate could not be verified (authentication error)**;
5. stores the certificate, private key, password, and profile at
   `kv/automation/cloudflare-mtls/identities/<device-id>/current`, with an
   immutable certificate-ID version below `versions/`; writes a second,
   metadata-only record containing status, serial, and expiry below
   `kv/automation/cloudflare-mtls/inventory/<device-id>/`; and
6. publishes the exact `.mobileconfig` as a Document in the `Kubernetes`
   1Password vault using the restricted service account; and
7. writes no GitHub artifact and prints no private material.

The 1Password document title includes both the device ID and Cloudflare
certificate ID, for example
`Cloudflare mTLS - sulibot-ganymede - <certificate-id>`. Download that document
from 1Password on the target Mac, iPhone, or iPad and install it locally.

If issuance reached OpenBao but 1Password publication failed, rerun
**Cloudflare mTLS Device**, choose `publish`, and select the same device. The
publish action reconstructs the existing profile from OpenBao; it does not
issue another certificate. Publication is idempotent: an existing document is
accepted only when its bytes match the OpenBao profile.

For break-glass recovery only, create a temporary installation copy from an
operator workstation:

```bash
scripts/openbao-approle-exec.sh mtls \
  scripts/cloudflare-mtls-device.sh export \
  --device-id sulibot-ganymede \
  --output "${TMPDIR:-/tmp}/sulibot-ganymede.mobileconfig"
```

The local user opens the profile and explicitly approves installation. On
macOS, complete installation in **System Settings -> General -> Device
Management**. On iOS/iPadOS, complete it in **Settings -> Profile Downloaded**
(or **General -> VPN & Device Management**). Delete a downloaded installation
copy immediately afterward because the profile contains the private identity.
OpenBao remains the source of truth; the automatically created 1Password
Document is the supported human delivery/recovery copy.

Then confirm the browser offers or automatically selects the certificate for
the pilot hostname. Fully quit and relaunch Chromium-based browsers after
installing or rotating the profile so they discard any connection and
client-certificate state created before the identity was available. A
certificate chooser can still appear when multiple matching identities are
installed; remove the superseded manually installed identity before testing
the managed profile.

This manual workflow does not require the Cloudflare One Client and has no
enrollment step.

The macOS PKCS#12 payload must include:

```xml
<key>PayloadType</key>
<string>com.apple.security.pkcs12</string>
<key>AllowAllAppsAccess</key>
<true/>
<key>KeyIsExtractable</key>
<false/>
```

`AllowAllAppsAccess` authorizes macOS applications to use the installed private
key without per-application Keychain ACL approval. It does not force an
application to implement client-certificate authentication, and it does not
prevent a browser certificate chooser when multiple matching identities are
installed. Remove expired and superseded identities during profile rotation.

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

- **macOS:** install the device-specific `.mobileconfig` containing the
  password-protected PKCS#12 identity, `AllowAllAppsAccess = true`, and
  `KeyIsExtractable = false`. The local user approves it in **System Settings ->
  General -> Device Management**. Safari and Chromium browsers use Keychain
  identities; the browser may ask which certificate to present when multiple
  matching identities exist. Fully quit and relaunch Chromium-based browsers
  after installing or rotating the profile before testing external access.
- **iOS/iPadOS:** transfer the password-protected PKCS#12 through an approved
  secure channel as a device-specific `.mobileconfig`, install the downloaded
  profile, then approve it in **Settings -> General -> VPN & Device
  Management**. Do not include the macOS-only `AllowAllAppsAccess` or
  `KeyIsExtractable` keys. This installs a client identity, not a VPN.
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

Use one hostname at a time. `immich.sulibot.com` and
`freshrss.sulibot.com` are cut over; apply this procedure to each additional
candidate.

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

Inventory certificate source as either `manual` or `service`. Both require
explicit expiry reminders. WARP enrollment health is monitored independently
from browser client-certificate inventory.

The negative-control probe is healthy only when the edge denies it. An
unauthenticated `2xx` or redirect is a critical security incident.

Gatus reports the public server certificate expiry, not the client certificate
expiry. Client-certificate rotation reminders must therefore come from the
OpenBao device inventory or a dedicated certificate exporter; do not mislabel
the Gatus server-certificate metric as client-certificate coverage.

The daily `Cloudflare mTLS Expiry` workflow runs:

```bash
scripts/cloudflare-mtls-device.sh audit --warning-days 30
```

It reports identities that have not yet been issued or are inactive as
warnings, and fails when an active certificate reaches the 30-day rotation
window. This is the early warning; use the 14-day and 7-day points below for
escalation.

## Rotation and revocation

At 30 days before expiry, issue and distribute a replacement. Verify it with
the positive probe before removing the old identity. At 14 days, escalate any
device that has not moved; at 7 days, treat the remaining rotation as urgent.

For a lost or decommissioned device:

1. Revoke that device's certificate in Cloudflare immediately.
2. Verify the revoked certificate receives `403`.
3. Confirm other device and monitoring certificates still work.
4. Remove the convenience copy from 1Password. Preserve the revoked OpenBao
   version for audit; never reuse its private identity.
5. Record the revocation, serial, owner, and reason in the incident or change
   record without attaching private material.

Use the same fixed device ID for revocation:

```bash
scripts/openbao-approle-exec.sh mtls \
  scripts/cloudflare-mtls-device.sh revoke \
  --device-id sulibot-ganymede
```

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
- **Profile installation failed with an authentication error:** do not retry
  the same file. Confirm the profile was generated by the current builder and
  that its embedded PKCS#12 uses the Apple-compatible legacy encoding. Revoke
  and replace identities packaged by an older builder.
- **Repeated System Keychain administrator prompts:** stop the test and deny
  queued prompts. Use the manual identity from the user's login Keychain. The
  automatically provisioned device identity is not a supported browser path.
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
- **Client remains on profile `default` at home:** verify the active interface
  is on `io` or `iot`, both TLS beacons are reachable, and run
  `warp-cli debug alternate-network`. Search the WARP service log for
  `NotValidForNameContext`; if present, verify the configured SHA-256 pin
  matches the certificate currently served by both beacon IPs.
- **TLS-inspection product or second VPN interferes:** temporarily disable that
  interception for the pilot test, then add the narrowest compatible
  exclusion. Do not export the private key to the interception product.
