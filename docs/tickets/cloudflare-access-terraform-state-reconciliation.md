# Cloudflare Access Terraform State Reconciliation

## Status (2026-07-11)

Resolved. The real state (serial 97, 15 resources) was found on a third
machine (`MacBook-Pro-2.local:~/repos/github/home-ops`) that had actually
been used to apply this stack — it was never present in this repo's other
two checkouts. It has been pulled in and migrated to a durable S3 backend
(MinIO at `s3.sulibot.com`, bucket `terraform-state`, dedicated
`terraform-state-rw`-scoped service account — not the MinIO root user).
`terraform/infra/live/services/cloudflare-access/terragrunt.hcl` now
overrides root.hcl's local backend with its own `remote_state` block; no
other module was touched. `terragrunt plan` now shows a clean, expected
diff (30 to add, 5 to change, 4 to destroy) matching intentional config
changes made since serial 97, not phantom recreation of live resources.

## Problem

`terraform/infra/live/services/cloudflare-access` defines Cloudflare Access,
DNS, Gateway DNS overrides, and WARP private routes, but the local Terraform
state currently contains only a small subset of the live Cloudflare resources.

Because of that, a full `terragrunt plan` or `terragrunt apply` for this stack
can show large create operations for resources that already exist live. Applying
that plan is unsafe until the live resources are imported or intentionally
removed from the Terraform surface.

## Current Known Live-Only/Partially Imported Areas

- Cloudflare Access applications and policies
- Public proxied DNS records for tunneled app hostnames
- Gateway DNS override policies for app-private WARP hostnames
- Cloudflare Tunnel private network routes

## Expected End State

- Terraform state is backed by a durable backend, not ephemeral local/cache
  state.
- Every Cloudflare resource declared in
  `terraform/infra/live/services/cloudflare-access` is imported into state.
- `terragrunt plan` is clean or contains only intentional changes.
- Routine changes to Cloudflare Access, DNS, Gateway DNS, and WARP private
  routes can be applied through Terraform without direct API cleanup.

## Acceptance Criteria

- [x] Migrate or pin this stack to durable Terraform state.
- [x] Import existing `cloudflare_dns_record` resources (already tracked in
      the recovered state).
- [x] Import existing `cloudflare_zero_trust_access_application` resources
      (already tracked in the recovered state).
- [ ] Import existing `cloudflare_zero_trust_gateway_policy` resources (the
      `app_private_dns_override` policies show as creates in the current
      plan — need to confirm whether they already exist live and need
      `terraform import`, or are genuinely new).
- [ ] Import existing `cloudflare_zero_trust_tunnel_cloudflared_route`
      resources (same as above — currently plan as creates).
- [x] Run `terragrunt plan` and confirm no unexpected creates/replaces
      remain — remaining diff (30 add / 5 change / 4 destroy) is intentional
      and reviewed, not phantom.

