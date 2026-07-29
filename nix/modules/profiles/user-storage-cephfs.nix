# Native CephFS client used by trusted VMs. The path-scoped CephX secret is
# installed out-of-band at /etc/ceph/ceph.client.sulibot-cloud.secret.
# noauto + automount keeps boot healthy before the secret is enrolled.
{ ... }:
{
  imports = [ ./user-storage-common.nix ];

  fileSystems."/home/sulibot/Cloud" = {
    device = "sulibot-cloud@.content=/users/sulibot/Cloud";
    fsType = "ceph";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "_netdev"
      "mon_addr=[fc00:20::1]:6789/[fc00:20::2]:6789/[fc00:20::3]:6789"
      "secretfile=/etc/ceph/ceph.client.sulibot-cloud.secret"
    ];
  };
}
