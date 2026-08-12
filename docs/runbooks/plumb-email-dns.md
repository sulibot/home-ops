# Plumb transactional email — DNS and SMTP

Tracked as ENG-493. Needed before anyone outside the Supabase project team can
sign up for Plumb at `plumb.sulibot.com`.

Supabase Cloud's built-in email sender delivers **only to project team members**
and is capped near **2 messages per hour** with no delivery SLA. Plumb's
sign-up, password reset, magic link and email change all send mail, so without
custom SMTP the product works for you and silently fails for everyone else.

---

## The landmine: external-dns will not carry these records

`sulibot.com` is managed by external-dns
(`kubernetes/apps/tier-1-infrastructure/cloudflare-dns/app/helmrelease.yaml`)
with:

```yaml
- --default-targets=0977043f-80e9-4549-a6f0-0af145a17f27.cfargotunnel.com
- --force-default-targets
- --managed-record-types=CNAME
- --managed-record-types=TXT
policy: sync
```

`--force-default-targets` is documented as *"Force the application of
--default-targets, **overriding any targets provided by the source**"*. A
`DNSEndpoint` CRD is a source. So an SPF or DMARC TXT record declared as a CRD
would have its value replaced by the tunnel hostname — the record would exist,
point at nothing meaningful, and mail authentication would fail in a way that
looks like a deliverability problem rather than a config error.

**So: create the email records outside external-dns**, in the Cloudflare
dashboard or via the API.

They are safe from `policy: sync` reaping. external-dns only deletes records it
owns, tracked by companion TXT records using `txtPrefix: k8s.` and
`txtOwnerId: default`. A record with no matching ownership TXT is left alone.
Do not add one for these.

There is currently no Terraform module managing public Cloudflare DNS for this
zone — `terraform/infra/live/routeros` only sets the DHCP search domain. If you
want these in git later, that module has to exist first.

---

## What already exists

Discovered rather than assumed — checked against the live zone and the Resend API.

| Thing | State |
|---|---|
| Resend account | **exists**, API key in 1Password item `smtp-relay` (field `SMTP_RELAY_PASSWORD`) |
| `sulibot.com` in Resend | **verified**, region `us-east-1` |
| DKIM `resend._domainkey.sulibot.com` | **published** |
| Return-path SPF `send.sulibot.com` | **published** — `v=spf1 include:amazonses.com ~all` |
| Apex SPF | `v=spf1 include:_spf.mx.cloudflare.net ~all` — Cloudflare Email Routing, inbound only |
| MX | Cloudflare Email Routing (`route1/2/3.mx.cloudflare.net`) |
| `_dmarc.sulibot.com` | **MISSING** |

So the account-creation and domain-verification work is already done. What is
left is much smaller than it first appeared.

## The in-cluster relay cannot serve Plumb

`smtp-relay.sulibot.com` (maddy, `tier-2-applications/smtp-relay`) is a
LoadBalancer on `fd00:101:250::122` / `10.101.250.122` — ULA and RFC1918, so
reachable from inside the cluster only. Supabase Cloud is an external service
and cannot connect to it.

Plumb therefore points at **`smtp.resend.com:587` directly**, using the same
Resend credentials the relay already uses. The relay stays as-is for in-cluster
senders (Alertmanager, Authentik, Firefly); Plumb is simply a second consumer of
the same upstream account.

## DMARC is missing, and that is not just a Plumb problem

`_dmarc.sulibot.com` does not exist. Every domain that sends mail should publish
one — without it, receivers have no stated policy for handling messages that
fail SPF or DKIM, and no reporting channel to tell you when they do.

```
Type   TXT
Name   _dmarc.sulibot.com
Value  v=DMARC1; p=none; rua=mailto:dmarc@sulibot.com; fo=1
```

Start at `p=none`: it reports without quarantining, so a misconfiguration shows
up in aggregate reports rather than sending real password resets to spam. Move
to `p=quarantine` once the reports are clean. `dmarc@sulibot.com` needs to be a
routable address — Cloudflare Email Routing already handles inbound for this
zone.

## Sender address: one decision

Resend verifies a specific domain. `sulibot.com` is verified; `plumb.sulibot.com`
is not, and Resend's guidance is that subdomains are added and verified
individually.

- **Send as `no-reply@sulibot.com`** — works today, no DNS. Plumb's sending
  reputation is then shared with everything else the zone sends.
- **Add `plumb.sulibot.com` to Resend** — two records (DKIM TXT, and SPF on
  `send.plumb.sulibot.com`), and Resend explicitly recommends a subdomain to
  isolate reputation. A deliverability problem with Plumb then cannot affect
  cluster alerting, and vice versa.

`supabase/config.toml` in the Plumb repo currently says
`admin_email = "no-reply@plumb.sulibot.com"`, which assumes the second option.
**If you pick the first, that value must change or Resend will reject the
send** — the from-address has to be on a verified domain.

## Supabase configuration

Custom SMTP on Supabase Cloud is **dashboard/API config, not `config.toml`** —
the local file governs only the local stack. In the Plumb project:

*Authentication → Emails → SMTP Settings*

```
Host          smtp.resend.com
Port          587                  (STARTTLS)
Username      resend
Password      <Resend API key — 1Password: smtp-relay / SMTP_RELAY_PASSWORD>
Sender email  no-reply@sulibot.com          (or @plumb.sulibot.com once verified)
Sender name   Plumb
```

Username is the literal string `resend` for every Resend SMTP connection; the
API key is the password. Same credentials the in-cluster maddy relay already
uses — see its `maddy.conf`, which does `auth plain` against
`tcp://smtp.resend.com:587`.

The sender address must match `admin_email` in `supabase/config.toml` in the
Plumb repo, so a local test and a production email look identical.

Email templates are already written and live in `supabase/templates/` in the
Plumb repo. **They are not uploaded automatically** — Supabase Cloud keeps its
own copies, so paste each one into *Authentication → Emails → Templates* and
keep the repo as the source of truth.

---

## Credentials — what actually exists

**Nothing new to create.** Verified against 1Password and against
`smtp.resend.com:587` (AUTH only, no message sent — all three log in
successfully):

| 1Password item (Kubernetes vault) | Field | Key | SMTP auth |
|---|---|---|---|
| `smtp-relay` | `SMTP_RELAY_PASSWORD` | **A** | OK |
| `API Credential - resend` | `credential` | **A** — same key | OK |
| `Resend` | `API_KEY` | **B** — different key | OK |

Resend itself lists two keys: `home-ops` (2026-02-23) and `ops` (2026-08-12).

### Two things worth fixing while you are here

**`smtp-relay` and `API Credential - resend` hold the same key.** Rotate one
and the other silently goes stale, still looking authoritative. One of them
should go — `smtp-relay` is the one External Secrets reads, so keep that.

**The `Resend` item is a LOGIN holding the account password alongside key B.**
An account credential and a service credential in one item means anything that
needs the key gets shown the password too. Key B belongs in its own
API Credential item.

### Which key Plumb should use

**Key B**, moved into a dedicated item — the same isolation argument as the
sender address. If Plumb's key is ever compromised or rate-limited, cluster
alerting keeps working; if the cluster's key is rotated, Plumb keeps sending.

```
Title      Plumb SMTP
Category   API Credential
Fields     credential (concealed)  <- key B
           username = resend
           host     = smtp.resend.com
           port     = 587
```

`username` is the literal string `resend` for every Resend SMTP connection —
the API key is the password.

---

## Verification

Not "the dashboard is green" — send a real message and read the headers.

```sh
# 1. Records are live and unproxied
dig +short TXT send.sulibot.com            # already present
dig +short TXT resend._domainkey.sulibot.com   # already present
dig +short TXT _dmarc.sulibot.com          # the one that is missing

# 2. Sign up from an address on a domain you do NOT control
#    (gmail is the useful test — it is the strictest common receiver)
```

Then open the received message and check `Authentication-Results`:

```
spf=pass  dkim=pass  dmarc=pass
```

Anything less than all three passing means real users' password resets land in
spam, which fails exactly as badly as not sending them.

Finally: confirm it arrived in **Inbox**, not Promotions or Spam.

---

## Why this gates ENG-486

The concierge validation — running calibration by hand with 10 real people —
depends on those people being able to receive a sign-in. Until this is done,
Supabase will refuse to mail anyone outside the project team with
`Email address not authorized`.
