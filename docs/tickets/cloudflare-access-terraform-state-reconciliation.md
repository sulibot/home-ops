# Cloudflare Access Terraform State Reconciliation

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

- [ ] Migrate or pin this stack to durable Terraform state.
- [ ] Import existing `cloudflare_dns_record` resources.
- [ ] Import existing `cloudflare_zero_trust_access_application` resources.
- [ ] Import existing `cloudflare_zero_trust_gateway_policy` resources.
- [ ] Import existing `cloudflare_zero_trust_tunnel_cloudflared_route`
      resources.
- [ ] Run `terragrunt plan` and confirm no unexpected creates/replaces remain.

