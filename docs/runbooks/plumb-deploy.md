# Deploying Plumb to Cloudflare Workers

`plumb.sulibot.com`, running on Workers Paid ($5/mo), with Supabase Cloud for
auth and database. Tracked as ENG-495.

Everything that can be done without your credentials is done. What remains is
listed under **What needs you** and is the only reason this is not live.

---

## Why Workers and not Containers or Vercel

Workers have no cold start. Containers scale to zero and take 1–3 seconds to
wake, and Plumb's traffic during validation — ten people, once every few days —
means almost every visit would be the first after idle. The slow path would be
the only path anyone experienced.

Vercel works unchanged and costs $20/mo once Plumb has a price on it, because
the Hobby plan prohibits "advertising the sale of a product or service".

## What had to change to make Workers possible

`proxy.ts` is gone. Next 16 forces it onto the Node runtime and
`@opennextjs/cloudflare` cannot run Node middleware — permanently, per the
maintainer. See ADR-028 in the plumb repo for what that cost (almost nothing,
and not what was predicted).

---

## The split

| Thing | Owned by | Where |
|---|---|---|
| Worker script | wrangler | `pnpm cf:deploy` in the plumb repo |
| DNS record, Worker route | Terragrunt | `services/cloudflare-plumb` |
| Email DNS | Terragrunt | `services/cloudflare-email-dns` |
| Secrets | `wrangler secret` | sourced from 1Password |

The script is a build artifact and belongs with the code. Terraform managing a
bundled JS blob would mean rebuilding it on every plan and storing it in state.

The **route** is deliberately in Terragrunt rather than wrangler's `routes`
config: a route has a blast radius across the zone and should be reviewable in
a plan, not applied as a side effect of a developer running a deploy.

**No Cloudflare Access in front of it.** Plumb is a public product; its own
Supabase auth is the gate. Access would lock out every real user, since none of
them are in the Zero Trust directory. This is the one hostname in the zone
where that is correct.

---

## Order of operations

The Terragrunt route references a Worker by name, so the script must exist
first. Applying before deploying leaves a route pointing at nothing.

```
1. Create the Supabase Cloud project        (needs you)
2. Create a Workers-scoped API token        (needs you)
3. wrangler secret put …                    (needs you, values from 1Password)
4. pnpm cf:deploy                            from ~/code/plumb/apps/web
5. terragrunt apply                          services/cloudflare-plumb
6. Verify
```

---

## What needs you

### 1. Supabase Cloud project

Does not exist. Create it, then:

- Run the migrations: `supabase link --project-ref <ref>` then `supabase db push`
- **Auth → Emails → SMTP**: `smtp.resend.com:587`, username the literal
  `resend`, password from 1Password `Plumb SMTP`. Sender per ENG-493.
- **Auth → Emails → Templates**: paste the five from `supabase/templates/` —
  Cloud keeps its own copies and does not read the repo.
- **Auth → URL Configuration**: site URL `https://plumb.sulibot.com`, and add
  `https://plumb.sulibot.com/auth/callback` to the redirect allow-list.
- **Auth → Providers → Google**: client ID and secret from 1Password
  `Plumb Google OAuth`. Then add the Cloud callback
  `https://<ref>.supabase.co/auth/v1/callback` to the authorised redirect URIs
  in the Google Cloud console — the stored value there is currently the local
  one, and Google will refuse anything not listed.
- **Auth hook**: enable `before_user_created` →
  `pg-functions://postgres/public/before_user_created_gate`. Without it the
  public signup endpoint is open (ENG-491).

### 2. Cloudflare API tokens — TWO gaps, and they are different

Both were found by testing, not by reading docs.

**a. The Terragrunt token needs Workers Routes.** The token in
`common/secrets.sops.yaml` can edit DNS but is refused on Workers routes:

```
DNS read:        200
Workers routes:  403
Workers scripts: 403
```

So `terragrunt apply` on `services/cloudflare-plumb` fails on
`cloudflare_workers_route` unless this is fixed first.

**Extend the existing token** rather than minting another. Add
**Zone → Workers Routes → Edit**, scoped to `sulibot.com`. This does not
meaningfully widen it: anything that can edit DNS for the zone can already
repoint every hostname on it, so route editing adds no capability an attacker
did not already have. One token, one thing to rotate.

**b. wrangler needs a NEW token.** Create one with
**Account → Workers Scripts → Edit**, and store it in the Kubernetes vault as
`Cloudflare Workers Deploy`.

Do **not** fold this into the Terragrunt token, for a reason that is not
tidiness. Workers Scripts is an **account-level** permission, while everything
the Terragrunt token holds is **zone-level**. Merging them means one leaked
value can both replace the running application *and* repoint the entire zone —
two failures that should stay independent. They also have different lifecycles:
the Terragrunt token is used by planned infrastructure changes, the deploy token
by a laptop or CI on every ship.

Scope it to the account only. It needs no zone permissions to publish a script.

**Worth noting while you are in there:** the Terragrunt token in sops is a
*third* Cloudflare token — it is not the `Cloudflare API Zone.DNS Token` item in
1Password, which is a different value. There are now several, and it is not
obvious which is which. Naming them for their purpose when you next touch them
would help.

### 3. Secrets on the Worker

`vars` in `wrangler.jsonc` holds only `NEXT_PUBLIC_SITE_URL`. Everything else
is a secret and must never be in the file:

```sh
cd ~/code/plumb/apps/web
wrangler secret put NEXT_PUBLIC_SUPABASE_URL
wrangler secret put NEXT_PUBLIC_SUPABASE_ANON_KEY
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_SERVICE_ROLE_KEY
wrangler secret put ANTHROPIC_API_KEY      # 1Password: Anthropic
wrangler secret put GOOGLE_CLIENT_ID       # 1Password: Plumb Google OAuth
wrangler secret put GOOGLE_CLIENT_SECRET
wrangler secret put NEXT_PUBLIC_GOOGLE_ENABLED   # "true"
```

`NEXT_PUBLIC_*` values are compiled into the client bundle and are not secret in
the cryptographic sense, but they differ per environment, so they live here
rather than in the committed config.

**The service-role key is the one that matters.** It bypasses RLS entirely. It
belongs only on the Worker and never in a client bundle — there is a build-time
scan for it (ADR-003), and it should stay passing.

---

## Deploy

```sh
cd ~/code/plumb/apps/web
pnpm cf:build      # OpenNext bundle, no deploy
pnpm cf:preview    # run it locally in workerd first
pnpm cf:deploy
```

Then the infrastructure:

```sh
cd ~/code/home-ops/terraform/infra/live/services/cloudflare-plumb
terragrunt plan     # expect: 2 to add
terragrunt apply
```

---

## Verify

Not "it returned 200" — drive the paths that break in interesting ways.

```sh
curl -sI https://plumb.sulibot.com/auth/sign-in | grep -i "content-security-policy\|strict-transport"
```

Then in a browser:

1. Sign in with a password. Land on `/dashboard`.
2. Load every authenticated screen.
3. Add an evidence record — that is a Server Action, a different code path from
   rendering, and the one most likely to break on a new runtime.
4. **Wait an hour, close the tab, and load `/dashboard` cold.** This is the
   session-refresh path that removing `proxy.ts` changed. It must render the
   dashboard, not bounce to sign-in. If it bounces, the refresh-token reuse
   property differs on Cloud — see ADR-028 and
   `tests/auth/session-refresh.test.ts`.
5. Run a calibration. ~110s, and the reason `cpu_ms` is set explicitly: Workers
   have no wall-clock limit while the client stays connected, and `fetch()` wait
   does not count as CPU.
6. Sign up from a Gmail address and check `Authentication-Results` for
   `spf=pass dkim=pass dmarc=pass` (ENG-493).

## Rollback

`wrangler rollback` reverts the script. The route and DNS are Terraform, so
reverting those is a revert-and-apply. The two are independent: rolling back the
script does not touch the route.
