locals {
  cluster_name      = "sol"
  cluster_id        = 101
  controlplanes     = 3
  workers           = 2
  proxmox_nodes     = ["pve01", "pve02", "pve03"]
  storage_default   = "rbd-vm"
  talos_version     = "v1.8.2"
  description       = "Primary production cluster"

  # Optional: Override specific nodes (by name)
  node_overrides    = {
    # Example:
    # "solcp011" = { cpu_cores = 8, memory_mb = 32768 }
    # "solwk021" = { cpu_cores = 2, memory_mb = 8192 }
  }
}
