# Onward design review site (reviews.sulibot.com)

A small static site where invited people review a round of Onward design
options on a laptop or a phone: they create an account with email and
password, mark each option "I would use this" or "Not for me", comment, rank
them and send. The owner (sulibot@gmail.com, the admin) sees the results and
runs rounds from the site itself.

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

The first deploy (2026-10-19) shipped commit `d99227d3` of
`claude/design-review-site-0b70ea`, exported with `git archive` so an
uncommitted edit in that worktree did not go out.

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
`https://reviews.sulibot.com/**`, `https://review.sulibot.com/**` and `http://localhost:*/**`; open sign-up with
`mailer_autoconfirm = true` (no confirmation mail; the owner's choice for this
low-stakes site); passwords at least 8 characters; 1-hour JWTs with refresh
token rotation; password-reset mail through Resend as
`Onward design review <no-reply@sulibot.com>`, 100 an hour. Leaked-password
protection (`password_hibp_enabled`) is a Pro-plan feature, so the security
advisor's warning about it stays on this free project.

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
