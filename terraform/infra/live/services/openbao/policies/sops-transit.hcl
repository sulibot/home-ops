path "transit/encrypt/sops" {
  capabilities = ["update"]
}

path "transit/decrypt/sops" {
  capabilities = ["update"]
}

path "transit/keys/sops" {
  capabilities = ["read"]
}
