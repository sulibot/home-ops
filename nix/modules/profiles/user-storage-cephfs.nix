# Native CephFS client used by trusted VMs. The path-scoped CephX keyring is
# installed out-of-band at /etc/ceph/ceph.client.sulibot-cloud.keyring.
# noauto + automount keeps boot healthy before the keyring is enrolled.
{ ... }:
{
  imports = [ ./user-storage-common.nix ];

  environment.etc."ceph/ceph.conf".text = ''
    [global]
    fsid = 407036f5-1f73-44ff-ba81-1f219b7a8a64
    mon_host = fc00:20::1 fc00:20::2 fc00:20::3
    ms_bind_ipv4 = false
    ms_bind_ipv6 = true
  '';

  fileSystems."/home/sulibot/Cloud" = {
    device = "sulibot-cloud@.content=/users/sulibot/Cloud";
    fsType = "ceph";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "_netdev"
    ];
  };

  # Organization-owned data is served through the HA NFS gateway so the VM
  # receives only the user's POSIX group entitlement, not another CephX key.
  fileSystems."/srv/common" = {
    device = "10.200.0.209:/common";
    fsType = "nfs";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "_netdev"
      "vers=4.1"
      "proto=tcp"
      "hard"
    ];
  };
}
