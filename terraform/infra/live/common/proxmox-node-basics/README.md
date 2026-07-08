# Proxmox Node Basics

This stack manages only BPG-supported node API metadata.

It intentionally does not manage host-local configuration such as packages,
systemd services, SSH, sysctl, FRR, `/etc/network/interfaces`, Ceph OSDs, or
BlueStore DB/WAL placement. Those remain Ansible-owned.
