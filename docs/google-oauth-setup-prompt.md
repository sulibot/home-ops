# Prompt: set up Google OAuth clients for seven Sulibot apps

Paste everything below the line into a browser-capable agent (ChatGPT Atlas /
Operator, or similar). It is self-contained — it assumes no prior context.

---

You are configuring Google OAuth sign-in for seven applications in Google
Cloud. The projects already exist. Your job is the part that has no API: the
OAuth consent screen and the OAuth client for each project.

## Account

Sign in as **sulibot@gmail.com**. This is a personal Google account with no
Cloud organisation, which is why this work cannot be scripted.

## The seven projects

Each already exists. Do not create projects.

| Project ID | Consent screen "App name" | Publishing status when done |
|---|---|---|
| `sulibot-jobs-auth` | Plumb | **Testing** (leave in testing) |
| `sulibot-tasks-auth` | Tasks | Published |
| `sulibot-kabinett-auth` | Kabinett | Published |
| `sulibot-daycare-auth` | Daycare | Published |
| `sulibot-adult-auth` | Adult | Published |
| `sulibot-ticketing-auth` | Ticketing | Published |
| `sulibot-meals-auth` | Meals | Published |

Note `sulibot-jobs-auth` is the project for an app **called Plumb** — the
project ID and the user-facing name differ on purpose. Users see the app name.

## For each project, in order

### 1. Select the project

Go to `https://console.cloud.google.com/auth/branding?project=<PROJECT_ID>`
substituting the project ID. Confirm the project selector at the top shows the
right project before changing anything — configuring the wrong project is the
main risk here.

### 2. Configure the consent screen ("Branding")

- **App name**: from the table above.
- **User support email**: sulibot@gmail.com
- **App logo**: upload `logo-192.png` (the operator will provide it; it is a
  192×192 PNG). Same logo for every project.
- **Audience**: External
- **Developer contact information**: sulibot@gmail.com
- Leave application home page, privacy policy and terms of service **blank**.
  They are not required for the scopes below.

Save.

### 3. Check the scopes

Go to the **Data access** tab. The only scopes needed are:

```
openid
.../auth/userinfo.email
.../auth/userinfo.profile
```

These are **non-sensitive**. Do not add any others. If Google shows a warning
about verification, you have added a sensitive scope by mistake — remove it.

### 4. Create the OAuth client

Go to `https://console.cloud.google.com/apis/credentials?project=<PROJECT_ID>`
→ **Create credentials** → **OAuth client ID**.

- **Application type**: Web application
- **Name**: `<app name> local`
- **Authorised JavaScript origins**: leave empty
- **Authorised redirect URIs**: add exactly this one:

```
http://127.0.0.1:54321/auth/v1/callback
```

That is the Supabase local callback, not the app's own URL. It is the same for
every project during local development. (Production URIs will be added later
and are out of scope here.)

Create, then copy the **Client ID** and **Client secret** from the dialog. The
secret is shown once — capture it before closing.

### 5. Set the publishing status

Go to the **Audience** tab.

- For `sulibot-jobs-auth` (Plumb): **leave in Testing**, and add
  `sulibot@gmail.com` as a test user.
- For all six others: click **Publish app** and confirm.

Publishing is instant for these scopes. There is no review, no waiting, and no
privacy-policy requirement. If you are shown a verification submission form,
stop — that means a sensitive scope is configured and step 3 needs revisiting.

## What to return

Report back as a Markdown table, exactly this shape, with no other commentary:

| project_id | app_name | client_id | client_secret | status |
|---|---|---|---|---|
| sulibot-jobs-auth | Plumb | ...apps.googleusercontent.com | GOCSPX-... | testing |
| sulibot-tasks-auth | Tasks | ... | ... | published |

If any project fails, include it as a row with the error in place of the
client_id rather than omitting it.

## Rules

- Do not enable billing on any project. None of this requires it.
- Do not add scopes beyond the three listed.
- Do not create, delete or rename projects.
- Do not modify `sulibot-homelab-auth` or any project not in the table — some
  hold credentials already in use.
- If a project already has a consent screen or OAuth client configured, do not
  overwrite it. Report it as `already-configured` and move on.
