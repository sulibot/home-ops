locals {
  # ── Cluster contract (required by clusters/_shared/units templates) ────────
  enabled             = true
  cluster_name        = "cluster-104"
  cluster_id          = 104 # Canonical cluster identity: state paths, output dirs, naming
  tenant_id           = 104 # Network tenancy: 10.<tenant>.x.x / fd00:<tenant>:: (equals cluster_id unless segments ever diverge)
  bootstrap_node_ipv4 = "10.104.0.4" # Single control-plane node; used by kubeconfig/talosconfig refresh hooks
  kubernetes_api_host = "10.104.0.4" # API endpoint host controllers pin to (no VIP on this single-node metal cluster)
  talos_apply_mode    = "auto"

  # ── Metal-platform node inventory (consumed by the config-metal unit) ──────
  # Map keyed by node name so additional bare-metal nodes are one entry each.
  nodes = {
    talos01 = {
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
            { vlanId = 30, mtu = 1500 },
            { vlanId = 31, mtu = 1500 },
          ]
        },
        {
          interface = "enp1s0.31"
          dhcp      = false
          mtu       = 1500
          addresses = [
            "fd00:31::6/64",
            "10.31.0.6/24",
          ]
          routes = [
            {
              network = "fd00:31::/64"
              gateway = "fd00:31::fffe"
              metric  = 512
            },
            {
              network = "10.31.0.0/24"
              gateway = "10.31.0.254"
              metric  = 512
            },
          ]
        },
      ]
      }
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
