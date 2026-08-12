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

## Records to create

Values marked `<from provider>` come from the sending provider's dashboard
after you add the domain. Use a subdomain (`mail.sulibot.com` or
`send.sulibot.com`) as the sending domain rather than the apex, so a
deliverability problem with Plumb never affects mail from `sulibot.com` itself.

| Type | Name | Value | Proxy |
|---|---|---|---|
| TXT | `send.sulibot.com` | `v=spf1 include:<provider-spf> ~all` | n/a |
| TXT | `<selector>._domainkey.send` | `<from provider>` | n/a |
| CNAME | `<selector>._domainkey.send` | `<from provider>` (SES/Resend often use CNAME) | **DNS only** |
| TXT | `_dmarc.sulibot.com` | `v=DMARC1; p=none; rua=mailto:dmarc@sulibot.com; fo=1` | n/a |
| MX | `send.sulibot.com` | `feedback-smtp.<region>.amazonses.com` (SES/Resend bounce handling) | n/a |

Notes that matter:

- **Never proxy a DKIM CNAME.** Cloudflare's proxy rewrites the answer and DKIM
  validation fails. The zone runs with `--cloudflare-proxied` as the
  external-dns default, but that only applies to records external-dns creates;
  set these to DNS-only explicitly.
- **Start DMARC at `p=none`.** It reports without quarantining, so a
  misconfigured DKIM shows up in the aggregate reports rather than sending real
  password resets to spam. Move to `p=quarantine` once reports are clean.
- `~all` (softfail) not `-all` on SPF, for the same reason. Tighten after
  observation.

---

## Supabase configuration

Custom SMTP on Supabase Cloud is **dashboard/API config, not `config.toml`** —
the local file governs only the local stack. In the Plumb project:

*Authentication → Emails → SMTP Settings*

```
Host        <provider smtp host>
Port        587
Username    <from provider>
Password    <from provider>
Sender email no-reply@send.sulibot.com
Sender name  Plumb
```

The sender name and address must match `supabase/config.toml` in the Plumb
repo, which already sets `sender_name = "Plumb"` and
`admin_email = "no-reply@plumb.sulibot.com"` for local. Pick one address and
use it in both, so a local test and a production email look the same.

Email templates are already written and live in `supabase/templates/` in the
Plumb repo. **They are not uploaded automatically** — Supabase Cloud keeps its
own copies, so paste each one into *Authentication → Emails → Templates* and
keep the repo as the source of truth.

---

## Credentials

Store in the **1Password Kubernetes vault**, matching the shape used for the
Google OAuth items:

```
Title      Plumb SMTP
Category   API Credential
Fields     username, credential (concealed), host, port,
           sender_email, sender_name, provider
```

---

## Verification

Not "the dashboard is green" — send a real message and read the headers.

```sh
# 1. Records are live and unproxied
dig +short TXT send.sulibot.com
dig +short TXT _dmarc.sulibot.com
dig +short CNAME <selector>._domainkey.send.sulibot.com

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
