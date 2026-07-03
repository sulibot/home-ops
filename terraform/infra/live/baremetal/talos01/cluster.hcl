locals {
  enabled          = true
  cluster_name     = "luna"
  cluster_id       = 10
  talos_apply_mode = "auto"

  node = {
    name         = "luna01"
    hostname     = "luna01"
    machine_type = "controlplane"
    ip_suffix    = 4
    public_ipv4  = "10.10.0.4"
    public_ipv6  = "fd00:10::4"
  }

  network = {
    use_vip          = false
    cluster_endpoint = "https://10.10.0.4:6443"
  }
}
