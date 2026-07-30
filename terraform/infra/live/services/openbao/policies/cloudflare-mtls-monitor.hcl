# Scheduled expiry monitoring needs certificate metadata but never the
# Cloudflare API token and cannot mutate identity material.
path "kv/data/automation/cloudflare-mtls/inventory/*" {
  capabilities = ["read"]
}

path "kv/metadata/automation/cloudflare-mtls/inventory" {
  capabilities = ["list"]
}

path "kv/metadata/automation/cloudflare-mtls/inventory/*" {
  capabilities = ["read", "list"]
}
