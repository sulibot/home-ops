locals {
  enabled          = true
  cluster_name     = "cluster-104"
  cluster_id       = 104
  talos_apply_mode = "auto"

  node = {
    name         = "talos01"
    hostname     = "talos01"
    machine_type = "controlplane"
    ip_suffix    = 4
    public_ipv4  = "10.104.0.4"
    public_ipv6  = "fd00:104::4"
    interface    = "enp1s0.104"
    extra_interfaces = [
      {
        interface = "enp1s0"
        dhcp      = false
        mtu       = 1500
        addresses = [
          "fd00:10::4/64",
          "10.10.0.4/24",
        ]
        vlans = [
          { vlanId = 104, mtu = 1500 },
        ]
      },
    ]
  }

  network = {
    use_vip          = false
    cluster_endpoint = "https://10.104.0.4:6443"
  }

  user_volumes = [
    {
      name                = "ha-data"
      disk_selector_match = "system_disk"
      min_size            = "80GiB"
      max_size            = "80GiB"
    }
  ]
}
