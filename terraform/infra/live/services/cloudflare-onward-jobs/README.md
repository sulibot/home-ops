# onward.jobs DNS delegation

This Terragrunt unit creates the `onward.jobs` zone in Cloudflare and sets the
domain's authoritative nameservers at Porkbun to Cloudflare's assigned pair.

Porkbun credentials remain in the 1Password `Kubernetes` vault, item `Login`.
The `.env.op` file contains only 1Password secret references. Always run this
unit through the wrapper so the provider receives short-lived environment
variables without writing credentials to disk or Terraform state:

```sh
./run.sh init
./run.sh plan
./run.sh apply
```

Porkbun must have **API Access** enabled for `onward.jobs` before planning or
applying the `porkbun_nameservers` resource. After delegation, Cloudflare may
remain `pending` briefly while the registry publishes the new nameservers.
