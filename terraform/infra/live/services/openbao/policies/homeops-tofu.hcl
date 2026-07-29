path "kv/data/automation/tofu/*" {
  capabilities = ["read"]
}

path "kv/metadata/automation/tofu" {
  capabilities = ["list"]
}

path "kv/metadata/automation/tofu/*" {
  capabilities = ["read", "list"]
}
