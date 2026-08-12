# Browser tasks for the Plumb deploy

Two dashboard changes that cannot be done through an API, because each requires
a credential the automation does not hold. Everything else is already done.

Paste everything below the line into ChatGPT with browser access.

---

You have browser access. Complete both tasks below in the signed-in Cloudflare
and Google Cloud consoles, then report back in the exact format at the end.

Do not create anything new. Both tasks are edits to existing objects. If
something does not match what is described here, stop and say so rather than
improvising — a wrong guess is worse than an unfinished task.

## Task 1 — Add two permissions to an existing Cloudflare API token

Go to **https://dash.cloudflare.com/profile/api-tokens**

Find the token named exactly **`sulibot-home-ops`**. Its Permissions column
currently reads something like "Account.Cloudflare Tunnel, Account.Zero Trust
+5" and its Resources column says "All accounts".

Do **not** touch any other token. In particular leave these alone:
`Cloudflare Workers Deploy`, `Cloudflare Agent (auto-generated)`, the three
tokens named `Edit zone DNS`, `Argo Tunnel API Token for sulibot.com in
Sulibot`, and `Proxmox`.

Click the `⋯` menu at the right of the `sulibot-home-ops` row, choose **Edit**,
then under **Permissions** add two new rows:

| Scope | Group | Level |
|---|---|---|
| `Zone` | `Workers Routes` | `Edit` |
| `Zone` | `Email Routing Rules` | `Edit` |

Leave every existing permission exactly as it is — add, never replace.

Under **Zone Resources**, make sure the new permissions apply to
**`sulibot.com`**. If the token's existing zone resource is already
"All zones" or specifically `sulibot.com`, leave it; do not narrow it.

Save with **Continue to summary**, then **Save token**.

**The token value does not change and will not be shown again — that is
expected. Do not regenerate or roll it.** Rolling it would break the
infrastructure automation that uses it.

Before you finish, note the exact wording of the two permission rows as they
appear in the summary — the group names differ slightly between Cloudflare UI
versions and I need to know what they actually said.

## Task 2 — Add a redirect URI to a Google OAuth client

Go to **https://console.cloud.google.com/apis/credentials**

Make sure the project selector at the top is set to the **Plumb** project. If
you cannot find a project named Plumb, list the projects you can see and stop.

Under **OAuth 2.0 Client IDs**, open the client used by Plumb. Its
**Authorised redirect URIs** currently contains a localhost entry, something
like `http://127.0.0.1:54321/auth/v1/callback`.

**Add** this URI, exactly:

```
https://fprczipdwiydbnmbizje.supabase.co/auth/v1/callback
```

Keep the existing localhost entry — local development still needs it. Add, do
not replace.

Save.

## Report back in this format

```
TASK 1 — Cloudflare
status: done | failed | skipped
token edited: sulibot-home-ops
permissions added (exact wording from the summary screen):
  - ...
  - ...
zone resource: ...
notes: ...

TASK 2 — Google
status: done | failed | skipped
project: ...
client name: ...
redirect URIs now present:
  - ...
  - ...
notes: ...
```

If either task failed, say exactly what you saw — the screen, the error, or the
thing that did not match. Do not report success for a step you did not
complete, and do not substitute a similar-looking option for one you could not
find.
