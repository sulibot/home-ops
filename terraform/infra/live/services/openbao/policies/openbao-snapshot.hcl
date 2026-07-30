# Scheduled backup nodes may identify the active Raft member and read an
# application-consistent snapshot. They cannot restore, seal, rekey, or read
# logical secrets.
path "sys/leader" {
  capabilities = ["read"]
}

path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
