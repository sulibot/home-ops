locals {
  # Shared defaults for LXC-based service stacks.
  lxc_defaults = {
    provider_version = "~> 0.98.0"
    template_file_id = "resources:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    vm_datastore     = "rbd-vm"
  }

  # Service class catalog. Keep networking and sizing in one place so new
  # stacks (zot, jool, pki, etc.) can follow the same tenant pattern.
  services = {
    kanidm = {
      role      = "kanidm"
      tenant_id = 100
      network = {
        bridge       = "vnet100"
        vlan_id      = null
        ipv4_gateway = "10.100.0.254"
        ipv6_gateway = "fd00:100::fffe"
      }
      storage = {
        vm_datastore = "rbd-vm"
      }
      sizing = {
        cpu_cores = 2
        memory_mb = 2048
        swap_mb   = 512
        disk_gb   = 16
      }
    }

    minio = {
      role      = "minio"
      tenant_id = 200
      network = {
        bridge       = "vmbr0"
        vlan_id      = 200
        ipv4_gateway = "10.200.0.254"
        ipv6_gateway = "fd00:200::fffe"
      }
      storage = {
        vm_datastore = "rbd-vm"
      }
      sizing = {
        cpu_cores = 2
        memory_mb = 2048
        swap_mb   = 512
        disk_gb   = 16
      }
      node_name = "pve02"
      vm_id     = 200052
      hostname  = "minio01"
      ipv4      = "10.200.0.52/24"
      ipv6      = "fd00:200::52/64"
    }

    zot = {
      role      = "zot"
      tenant_id = 200
      network = {
        bridge       = "vmbr0"
        vlan_id      = 200
        ipv4_gateway = "10.200.0.254"
        ipv6_gateway = "fd00:200::fffe"
      }
      storage = {
        vm_datastore = "rbd-vm"
      }
      sizing = {
        cpu_cores = 2
        memory_mb = 2048
        swap_mb   = 512
        disk_gb   = 20
      }
      node_name = "pve02"
      vm_id     = 200051
      hostname  = "zot01"
      ipv4      = "10.200.0.51/24"
      ipv6      = "fd00:200::51/64"
    }

    otbr = {
      role      = "otbr"
      tenant_id = 31
      network = {
        bridge       = "vmbr0"
        vlan_id      = 31
        ipv4_gateway = "10.31.0.254"
        ipv6_gateway = "fd00:31::fffe"
      }
      storage = {
        vm_datastore = "rbd-vm"
      }
      sizing = {
        cpu_cores = 2
        memory_mb = 2048
        swap_mb   = 512
        disk_gb   = 16
      }
      node_name = "pve01"
      vm_id     = 30253
      hostname  = "otbr01"
      ipv4      = "10.31.0.253/24"
      ipv6      = "fd00:31::253/64"
    }

    pki = {
      role      = "pki"
      tenant_id = 100
      network = {
        bridge       = "vnet100"
        vlan_id      = null
        ipv4_gateway = "10.100.0.254"
        ipv6_gateway = "fd00:100::fffe"
      }
      storage = {
        vm_datastore = "rbd-vm"
      }
      sizing = {
        cpu_cores = 2
        memory_mb = 2048
        swap_mb   = 512
        disk_gb   = 16
      }
      node_name = "pve01"
      vm_id     = 100064
      hostname  = "pki01"
      ipv4      = "10.100.0.64/24"
      ipv6      = "fd00:100::64/64"
    }
  }
}
