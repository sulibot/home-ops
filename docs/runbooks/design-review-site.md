# Podium (reviews.sulibot.com)

Renamed to Reviewer on 2026-10-20 and to Podium on 2026-10-21, made by Sulibot; identifiers keep their old names.

Podium is a small static site, made by Sulibot, where invited people review
a round of design options (today, for Onward) on a laptop or a phone: they
create an account with email and password, mark each option "I would use this"
or "Not for me", comment, rank them and send. The owner (sulibot@gmail.com, the
admin) sees the results and runs rounds from the site itself.

![QR code for https://reviews.sulibot.com](design-review-site-qr.png)

`design-review-site-qr.png` opens https://reviews.sulibot.com; put it on a
slide or print it so reviewers can scan it with a phone.

`reviews.sulibot.com` is the public name. `review.sulibot.com`, the first
name, still serves the same Worker so links and QR codes already handed out
keep working.

## The split

| Thing | Owned by | Where |
|---|---|---|
| Site files (HTML, pictures, live mocks) | Onward repo | `tools/design-review/public/` |
| Worker `sulibot-design-review` (assets only, no script) | Wrangler | `tools/design-review/wrangler.jsonc` in the Onward repo |
| DNS records, Worker routes (reviews. and review.sulibot.com) | Terragrunt | `terraform/infra/live/services/cloudflare-sulibot-review` |
| Supabase auth settings (site URL, redirects, sign-up, SMTP) | Terragrunt | `terraform/infra/live/services/supabase-onward-review` |
| Supabase project `onward-review` (ref `tczhezpecxlqwchmyhaj`, us-east-1) | Supabase connector / dashboard | not Terraform-owned |
| Schema, RLS, rounds and options | Onward repo / the site | `tools/design-review/schema.sql`; rounds are data |

The Onward repo's `tools/design-review/README.md` is the reference for how the
site works, the admin screens and the rest of the admin SQL. It is not served:
only `public/` is.

## Deploy the site

From an Onward checkout, after changing anything in `tools/design-review/public/`:

```bash
fnm exec --using 24.20.0 npx wrangler@4 deploy --config tools/design-review/wrangler.jsonc
```

Authentication: the `cloudflare_api_token` in `common/secrets.sops.yaml` can
manage DNS and Worker routes but **not** Worker scripts (the deploy gets 403 on
`workers/scripts/.../deployments`). The deploy therefore uses the owner's
`npx wrangler login` session (OAuth, stored by Wrangler on this Mac), so run it
without `CLOUDFLARE_API_TOKEN` in the environment. To deploy from sops instead,
the token needs **Account → Workers Scripts → Edit** on the Sulibot account.

Deploy a committed revision, not a working tree: export it with
`git archive <commit> tools/design-review | tar -x -C <empty dir>` and run the
deploy from there, so an uncommitted edit in a worktree never goes out. Then
check that `/` on both hostnames is byte-identical to that commit's
`public/index.html`, and that a WebP under `/img/`, a `/live/<slug>/page.html`,
`/admin`, `/r/<slug>` and `/s/<token>` all return 200 (the last three are
routes inside `index.html`, served by the Worker's single-page fallback).

| Date | Commit | Worker version | What it carried |
|---|---|---|---|
| 2026-10-19 | `d99227d3` | `ecede6f9` | First build |
| 2026-10-19 | `1d0060b9` | `5fa69636` | Ledger design, admin area |
| 2026-10-19 | `852b914c` | `bfaf6d81` | reviews.sulibot.com as the primary name |
| 2026-10-19 | `4ddfb416` | `8f81b642` | Top five, email-confirmed sign-up, roles, round specs, share links, review emails |
| 2026-10-20 | `6e67b2de` | `d2114699` | Phase 4: every rating mode, results links (`/s/`), reminders, log, compare |
| 2026-10-20 | `33f05c60` | `eeb8c216` | "New here? Create an account" under the sign-in form |
| 2026-10-20 | `d7ef264e` | `2bf3604a` | Next and Back loop through the designs |
| 2026-10-20 | `975572b7` | `f28e291a` | Picture opens the live page, keys for every action, Open / All views, podium terminus |
| 2026-10-20 | `d8b28443` | `0d49b500` | Designer's notes float over the picture; the phone bar fits 390 px |
| 2026-10-20 | `50003feb` | `a1fb3fa7` | The gate fits a laptop window; the note grows with its text |
| 2026-10-20 | `0452726b` (Onward main, PR 8) | `deede50e` | Sulibot design review branding: title, top bar, favicons, og image |

Every file under `public/` is public. Wrangler also publishes the Worker at
`https://sulibot-design-review.sulibot.workers.dev`.

## Change routing or auth settings

```bash
cd terraform/infra/live/services/cloudflare-sulibot-review && terragrunt apply
cd terraform/infra/live/services/supabase-onward-review && terragrunt apply
```

The Cloudflare unit needs the Worker to exist first; Cloudflare refuses a route
to a missing script. The Supabase unit owns the whole auth config it sets:
anything changed in the dashboard is reverted on the next apply.

Current auth settings: site URL `https://reviews.sulibot.com`; redirects
`https://reviews.sulibot.com/**`, `https://review.sulibot.com/**` and
`http://localhost:*/**`; open sign-up validated by an email link
(`mailer_autoconfirm = false`; it was on at launch); passwords at least 8
characters; 1-hour JWTs with refresh token rotation. Confirmation,
password-reset and email-change mail go through Resend as
`Podium <no-reply@sulibot.com>`, 100 an hour, using the short
templates (subject, one sentence, one button) defined in the unit's locals.
Magic-link mail keeps Supabase's default template. Leaked-password protection
(`password_hibp_enabled`) is a Pro-plan feature, so the security advisor's
warning about it stays on this free project.

A reviewer stuck waiting for the confirmation mail can be confirmed by hand
with the "Confirm an account" SQL in the Onward README.

Check what Supabase is serving (the publishable key is public by design):

```bash
curl -s -H "apikey: sb_publishable_MAeAicJPS2lg-kbBTQNqlQ_SDfn-Jzx" https://tczhezpecxlqwchmyhaj.supabase.co/auth/v1/settings
```

## Reset someone's password

Run in the Supabase dashboard's SQL editor for `onward-review`, or with the
Supabase connector's `execute_sql` on `tczhezpecxlqwchmyhaj`, then tell the
person the new password yourself. Reviewers can also use "Forgot password" on
the site, which mails a link through Resend.

```sql
update auth.users
set encrypted_password = extensions.crypt('THE-NEW-PASSWORD', extensions.gen_salt('bf')),
    updated_at = now()
where email = lower('person@example.com');
```

## Open or close a round

On the site, signed in as the admin: account menu → Rounds and options → pick
the round → set its status. A new round starts as `draft` (only admins see it);
`open` lets reviewers read it and write their review; `closed` keeps it
readable but freezes every answer.

The same by SQL:

```sql
update public.rounds set status = 'open'   where slug = 'round-1';
update public.rounds set status = 'closed' where slug = 'round-1';
```

## Email notifications: pg_net and the Resend key in Vault

The site sends notification mail from a database trigger, through `pg_net`, to
the Resend API. Two pieces live in the `onward-review` database:

- the `pg_net` extension, enabled 2026-10-19 (migration `enable_pg_net`);
- the Resend API key in Supabase Vault under the name `resend_api_key`. It is
  the same value as `plumb_smtp_password` in `common/secrets.sops.yaml`
  (Resend uses the API key as the SMTP password). Stored by the owner on
  2026-10-20 06:10 UTC with the command below.

To store it again (for example in a new project) from home-ops, with no secret on the command line or in shell
history (run from the repo root):

```bash
F=terraform/infra/live/common/secrets.sops.yaml; TOKEN=$(sops -d --extract '["supabase_access_token"]' $F); KEY=$(sops -d --extract '["plumb_smtp_password"]' $F); jq -n --arg q "select vault.create_secret('$KEY', 'resend_api_key', 'Resend API key for review notifications');" '{query:$q}' | curl -s -X POST "https://api.supabase.com/v1/projects/tczhezpecxlqwchmyhaj/database/query" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @-; unset KEY TOKEN
```

Or in the dashboard's SQL editor, pasting the key in place of the placeholder:

```sql
select vault.create_secret('<RESEND_API_KEY>', 'resend_api_key', 'Resend API key for review notifications');
```

Check it exists (names only; never select `decrypted_secret` where it can be
logged):

```sql
select name, created_at from vault.secrets;
```

To rotate the key, change it in Resend, update `plumb_smtp_password` in sops,
apply `supabase-onward-review` (SMTP) and `supabase-plumb`, then
`select vault.update_secret(id, '<NEW_KEY>') from vault.secrets where name = 'resend_api_key';`.

The key currently has full access to the Resend account. A sending-only key
restricted to `sulibot.com` would be enough for both SMTP and these
notifications.

## Google sign-in

Reviewers can sign in with Google beside email and password. The OAuth client
`sulibot-design-review` is in Google Cloud, with the authorised redirect URI
`https://tczhezpecxlqwchmyhaj.supabase.co/auth/v1/callback` (the unit's
`google_redirect_uri` output) and the JavaScript origin
`https://reviews.sulibot.com`. Its id and secret are in 1Password (Kubernetes
vault, item "Podium Google OAuth": username = client id, credential = secret)
and in sops as `sulibot_reviews_google_client_id` and
`sulibot_reviews_google_client_secret`.

Copy them from 1Password into sops without printing either value (run from the
repo root), then apply the unit:

```bash
F=terraform/infra/live/common/secrets.sops.yaml; I=rghc4jzpcc5cnl46jvyd37sg4y; op item get $I --vault Kubernetes --fields username --reveal | tr -d '\n' | jq -Rs . | sops set --value-stdin $F '["sulibot_reviews_google_client_id"]' && op item get $I --vault Kubernetes --fields credential --reveal | tr -d '\n' | jq -Rs . | sops set --value-stdin $F '["sulibot_reviews_google_client_secret"]'
cd terraform/infra/live/services/supabase-onward-review && terragrunt apply
```

Check it with the publishable key: `/auth/v1/settings` should report
`"google": true` under `external`.

