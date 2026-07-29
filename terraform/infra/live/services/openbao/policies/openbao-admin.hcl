# Human administrators authenticate through Kanidm OIDC. Root remains a
# break-glass credential only. Explicit deny rules keep destructive recovery
# operations out of normal browser sessions.
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}

path "sys/raw" {
  capabilities = ["deny"]
}

path "sys/raw/*" {
  capabilities = ["deny"]
}

path "sys/rekey/*" {
  capabilities = ["deny"]
}

path "sys/generate-root/*" {
  capabilities = ["deny"]
}

path "sys/seal" {
  capabilities = ["deny"]
}

path "sys/audit" {
  capabilities = ["deny"]
}

path "sys/audit/*" {
  capabilities = ["deny"]
}
