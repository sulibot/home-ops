resource "proxmox_virtual_environment_hosts" "hosts_config" {
  for_each = toset(["pve01", "pve02", "pve03"])

  node_name = each.value

  entry {
    address   = "127.0.0.1"
    hostnames = ["localhost.localdomain", "localhost"]
  }

  entry {
    address   = "::1"
    hostnames = ["ip6-localhost", "ip6-loopback"]
  }

  entry {
    address   = "fe00::0"
    hostnames = ["ip6-localnet"]
  }

  entry {
    address   = "ff00::0"
    hostnames = ["ip6-mcastprefix"]
  }

  entry {
    address   = "ff02::1"
    hostnames = ["ip6-allnodes"]
  }

  entry {
    address   = "ff02::2"
    hostnames = ["ip6-allrouters"]
  }

  entry {
    address   = "ff02::3"
    hostnames = ["ip6-allhosts"]
  }

  entry {
    address   = "fd00:255::1"
    hostnames = ["pve01.sulibot.com", "pve01"]
  }

  entry {
    address   = "fd00:255::2"
    hostnames = ["pve02.sulibot.com", "pve02"]
  }

  entry {
    address   = "fd00:255::3"
    hostnames = ["pve03.sulibot.com", "pve03"]
  }

  entry {
    address   = "fd00:255::4"
    hostnames = ["pve04.sulibot.com", "pve04"]
  }

}
