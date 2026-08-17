# Deploying Plumb to Cloudflare Workers

> **Status 2026-08-12.** Supabase project `fprczipdwiydbnmbizje` created,
> configured, migrated and verified. Cloudflare tokens in place, Worker built,
> secrets uploaded. **Blocked on one thing: the Cloudflare account is on the
> Workers Free plan.** See the last section.

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
1. sops-edit secrets                         (needs you: Supabase PAT + org id)
2. terragrunt apply                          services/supabase-plumb
3. supabase db push                          from ~/code/onward
4. Add the Google redirect URI               (needs you: value from tf output)
5. Cloudflare tokens                         (needs you)
6. wrangler secret put …
7. pnpm cf:deploy                            from ~/code/onward/apps/web
8. terragrunt apply                          services/cloudflare-plumb
9. Verify
```

---

## What needs you

### 1. Supabase Cloud project — now Terraform, not a dashboard checklist

`services/supabase-plumb` creates the project and manages its auth
configuration through the official `supabase/supabase` provider. Site URL,
redirect allow-list, SMTP, the Google provider and the `before_user_created`
hook are all in the plan.

**One value to fill in by hand. Everything else is derived.**

On the `Supabase Plumb` item in the Kubernetes vault, set `credential` to a
Supabase personal access token from
https://supabase.com/dashboard/account/tokens.

**Expiry: choose Custom, ~12 months.** "Never" is only offered when no
never-expiring token exists, and the single slot is held by
`cli_sulibot@ganymede` — which is your **CLI login**, used by `supabase link`
and `supabase db push`. Deleting it to free the slot logs your CLI out, and
re-running `supabase login` just mints another one. An expiry you have written
down beats a token that dies when you reinstall a CLI.

Then:

```sh
./scripts/plumb-secrets.sh --dry-run
./scripts/plumb-secrets.sh
```

The script derives the rest:

- **organization_id** is fetched from the Management API, not transcribed. The
  dashboard shows a slug in some places and an id in others; the provider wants
  the id. If the account has more than one organization it stops and asks,
  rather than silently putting the project somewhere with different billing.
- **The token is validated** against the API before anything is written, so a
  bad paste fails here rather than at `terraform apply` with `Unauthorized`.
- **open-brain's sops copy is refreshed** with the same token. Both repos hold
  Supabase PATs and both currently hold the same *dead* one — open-brain's
  terraform cannot run today. A PAT cannot be scoped, so a second token would
  add rotation burden without shrinking blast radius.

`db_password` is already generated. Terraform sets it at project creation and
Supabase does not let you read it back, so it stays in 1Password.

Then:

```sh
cd terraform/infra/live/services/supabase-plumb
terragrunt apply
terragrunt output project_ref
terragrunt output google_redirect_uri
```

**What Terraform deliberately does NOT own:**

- **Migrations.** `supabase link --project-ref <ref>` then `supabase db push`
  from the plumb repo. Schema is versioned SQL and belongs with the code;
  Terraform holding it would be two sources of truth for the same tables.
- **Email templates.** The auth API takes them as inline strings, and the five
  live in `plumb/supabase/templates/*.html`. Inlining ~9KB of HTML into a
  terragrunt.hcl to satisfy a principle would make both files worse. Push them
  with the migrations.

**Order matters:** apply Terraform first to get `project_ref`, then push
migrations. The `before_user_created` hook points at
`public.before_user_created_gate`, which does not exist until the migrations
run — the hook is configured but inert until then, and the signup endpoint is
open in that window. Push migrations promptly.

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

**Extend the existing token** rather than minting another. Add both
**Zone → Workers Routes → Edit** and **Zone → Email Routing Rules → Edit**,
scoped to `sulibot.com`. The second is for the DMARC forwarding rule, which is
now Terraform too and is refused by the current token (403, tested). This does not
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
cd ~/code/onward/apps/web
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

> **Stale above, as of ENG-532.** `vars` in `wrangler.jsonc` no longer holds
> only `NEXT_PUBLIC_SITE_URL`, and the auth provider flags are no longer
> secrets. `vars` now also carries `SITE_URL`, `MCP_SERVER_URL`,
> `AUTH_GOOGLE_ENABLED`, `AUTH_LINKEDIN_ENABLED` and `ANALYTICS_ENABLED`.
> `scripts/cf-deploy.sh --sync-secrets` is the current way to push the actual
> secrets; the hand-run list above is kept for the "recreate a Worker from
> nothing" case.

### 4. Feature flags are `vars`, not secrets

Boolean deployment flags live in `vars` in `wrangler.jsonc`, in git, where
their state shows up in a diff. They are not credentials, and putting them in
`wrangler secret put` would hide the one thing worth reviewing about them.

They are also deliberately **not** `NEXT_PUBLIC_*`. Next inlines that prefix at
build time, so the value would come from whichever laptop ran the deploy — which
is exactly how one unreachable 1Password item once shipped a bundle with the
LinkedIn button compiled out, with no error anywhere.

| Var | Meaning |
|---|---|
| `AUTH_GOOGLE_ENABLED` | Offer Google sign-in. Must agree with `external_google_enabled` in the Supabase Terragrunt stack. |
| `AUTH_LINKEDIN_ENABLED` | Offer LinkedIn sign-in. Same agreement requirement. |
| `ANALYTICS_ENABLED` | **Off.** Whether the app records product-analytics events. |

**`ANALYTICS_ENABLED` — what turning it on means.**

ENG-532 built a product-event pipeline for the applications tracker: five
events, written server-side to the `product_events` table in Postgres, with a
strict property allowlist (no free text, no PII, no resume or job-description
content) and RLS. It exists to answer whether the queue's nine hardcoded time
estimates are honest, whether the rules engine surfaces the right items, and
whether users really do build an evidence inventory.

It is **off by default and ships off**, so the pipeline could land and be
reviewed before writing a single row about a real person. Setting it to `"true"`
starts collection for everyone — collection is unconditional and disclosed in
the terms of service rather than gated behind a per-user toggle, so this is the
switch, and there is no second one.

```jsonc
// apps/web/wrangler.jsonc → vars
"ANALYTICS_ENABLED": "false"   // "true" to collect
```

Exactly the string `"true"` enables it. `"1"`, `"yes"`, `"TRUE"` and a trailing
space are all off, on purpose: a permissive parse is how a gate gets flipped by
a typo, and the failure would be silent in the direction that starts writing.
Deploy the change (`./scripts/cf-deploy.sh`) for it to take effect — it is read
at request time, but the var reaches the Worker with the deploy.

Locally the same flag is written to `apps/web/.env.local` by
`scripts/dev-env.sh`, also `false`. Set it to `true` by hand to exercise the
events against the local stack; that script regenerates the file, so the edit
cannot quietly become the default.

---

## Deploy

```sh
cd ~/code/onward/apps/web
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

---

## The sender address, decided by constraint

Isolating Plumb's reputation onto `plumb.sulibot.com` was the intent. Resend
refuses it:

```
403 {"message":"Your plan includes 1 domain. Upgrade to add more."}
```

`sulibot.com` already occupies the single slot, so a from-address on any
subdomain is rejected as unverified. Plumb sends as `no-reply@sulibot.com` and
shares sending reputation with everything else the zone sends — cluster
alerting included. If Plumb is ever marked as spam, alert delivery degrades
with it.

Revisit only if Resend is upgraded. `supabase/config.toml` in the plumb repo
has been corrected to match, and verified: `Plumb <no-reply@sulibot.com>`.

## DMARC report delivery

`rua` points at `dmarc@sulibot.com`, and that address must actually receive
mail or `p=none` reports nothing while looking like it works.

The forwarding rule is now Terraform —
`cloudflare_email_routing_rule.dmarc` in `services/cloudflare-email-dns`.

**One manual prerequisite that cannot be automated:** the destination
(`sulibot@gmail.com`) must be a *verified* destination address on the account.
Cloudflare verifies by emailing a link. If it is already verified from earlier
Email Routing setup, nothing to do.

---

## Facts established during the first deploy

**Supabase project:** `fprczipdwiydbnmbizje`, org `Sulibot`
(`vsqdkrwdzgsljcmafkrf`), region `eu-west-2`. API at
`https://fprczipdwiydbnmbizje.supabase.co`.

**The direct database host is IPv6-only, and this machine has no IPv6 egress.**
`supabase link` fails with a dial timeout that names an IPv6 address and does
not explain itself. Use the session pooler, which is IPv4:

```sh
supabase db push --db-url \
  "postgresql://postgres.fprczipdwiydbnmbizje:<pw>@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
```

Port 5432 on the pooler host is *session* mode. The 6543 the API advertises is
*transaction* mode and is the wrong one for DDL.

**Verified after migrating**, rather than assumed:

| Check | Result |
|---|---|
| Auth settings actually applied | all 15 keys read back correctly from the config API |
| Migrations | 12 applied, 40 tables |
| RLS | enabled on all 40 |
| `before_user_created_gate` exists | yes |
| Live signup gate | `422 User already registered` for a brand-new address |
| Refresh-token reuse (ADR-028) | same token twice, 15s apart, 200 both times |

The auth block is opaque JSON to the Terraform provider, so a misspelled key
would be silently dropped rather than rejected. Reading it back is the only way
to know it took.

The refresh-token reuse check is the one that mattered most: the entire
no-middleware design rests on it, and Cloud runs a different GoTrue build from
the local stack — visible in the tokens themselves, ES256 on Cloud versus HS256
locally.

---

## Blocked: the account is on Workers Free

`wrangler deploy` fails:

```
CPU limits are not supported for the Free plan.  [code: 100328]
```

Removing `limits.cpu_ms` from `wrangler.jsonc` would get past that error and
then fail worse. **Free allows 10ms of CPU per request**, and a Next.js SSR
render exceeds that immediately — the deploy would succeed and every page would
error at runtime. The `cpu_ms` line is not the problem; it is what surfaced the
problem before users did, which is the better failure.

**Upgrade to Workers Paid ($5/mo):**
https://dash.cloudflare.com/089ac5ef7a1525cb7d7129cdde5873cd/workers/plans

Nothing else is waiting. After the upgrade:

```sh
cd ~/code/onward/apps/web && pnpm cf:deploy
cd ~/code/home-ops/terraform/infra/live/services/cloudflare-plumb && terragrunt apply
cd ../cloudflare-email-dns && terragrunt apply     # DMARC forwarding rule
```
