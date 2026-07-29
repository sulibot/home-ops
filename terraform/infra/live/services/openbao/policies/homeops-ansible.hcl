path "kv/data/automation/ansible/*" {
  capabilities = ["read"]
}

path "kv/metadata/automation/ansible" {
  capabilities = ["list"]
}

path "kv/metadata/automation/ansible/*" {
  capabilities = ["read", "list"]
}
