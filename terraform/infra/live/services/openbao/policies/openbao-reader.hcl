# Human read-only access is intentionally operational, not a blanket secret
# reader role.
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/health" {
  capabilities = ["read"]
}

path "sys/leader" {
  capabilities = ["read"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}

path "sys/storage/raft/configuration" {
  capabilities = ["read"]
}
