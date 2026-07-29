# Kubernetes applications receive only secrets under the Kubernetes subtree.
path "kv/data/kubernetes/*" {
  capabilities = ["read"]
}

path "kv/metadata/kubernetes" {
  capabilities = ["list"]
}

path "kv/metadata/kubernetes/*" {
  capabilities = ["read", "list"]
}
