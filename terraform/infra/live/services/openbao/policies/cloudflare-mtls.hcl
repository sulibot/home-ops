# Cloudflare API credentials used only by the scoped issuance workflow.
path "kv/data/automation/cloudflare-mtls/config" {
  capabilities = ["read"]
}

# Per-device private identities and installation profiles. The workflow may
# create a new version, update the current pointer, and read before rotation or
# revocation. It cannot delete secret history.
path "kv/data/automation/cloudflare-mtls/identities/*" {
  capabilities = ["create", "read", "update"]
}

path "kv/metadata/automation/cloudflare-mtls/identities" {
  capabilities = ["list"]
}

path "kv/metadata/automation/cloudflare-mtls/identities/*" {
  capabilities = ["read", "list"]
}

# Sanitized inventory records contain lifecycle metadata only. They are written
# alongside the secret identity so monitoring never needs private-key access.
path "kv/data/automation/cloudflare-mtls/inventory/*" {
  capabilities = ["create", "read", "update"]
}

path "kv/metadata/automation/cloudflare-mtls/inventory" {
  capabilities = ["list"]
}

path "kv/metadata/automation/cloudflare-mtls/inventory/*" {
  capabilities = ["read", "list"]
}
