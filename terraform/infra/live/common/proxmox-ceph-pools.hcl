locals {
  # Terraform owns only the Proxmox API-level Ceph pool declarations in this
  # catalog. Physical OSDs, disk partitions, DB/WAL, and CRUSH drive buckets
  # stay in Ansible.
  #
  # Keep managed=false until the existing live pool has been imported.
  ceph_pools = {
    "rbd-vm" = {
      managed           = true
      application       = "rbd"
      size              = 3
      min_size          = 2
      pg_num            = 128
      crush_rule        = "replicated_nvme"
      pg_autoscale_mode = "on"
      force_destroy     = false
      remove_ecprofile  = true
      remove_storages   = false
      owner             = "terraform"
      notes             = "Primary VM disk pool. Imported from existing live pool."
    }

    "rbd-backups" = {
      managed           = true
      application       = "rbd"
      size              = 3
      min_size          = 2
      pg_num            = 128
      crush_rule        = "replicated_hdd"
      pg_autoscale_mode = "on"
      force_destroy     = false
      remove_ecprofile  = true
      remove_storages   = false
      owner             = "terraform"
      notes             = "RBD backup pool. Imported from existing live pool."
    }

    "resources_data" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 256
      crush_rule        = "replicated_hdd"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS resources data pool; filesystem creation remains outside this module."
    }

    "resources_metadata" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 32
      crush_rule        = "replicated_rule"
      pg_autoscale_mode = "off"
      owner             = "terraform"
      notes             = "CephFS resources metadata pool; filesystem creation remains outside this module."
    }

    "content_default" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 32
      crush_rule        = "replicated_rule"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS content replicated data pool."
    }

    "content_meta" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 16
      crush_rule        = "replicated_nvme"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS content metadata pool."
    }

    "content_ec" = {
      managed           = false
      application       = "cephfs"
      erasure_coding    = "k=4,m=2,profile=ec_4_2_profile,device-class=hdd,failure-domain=drive"
      pg_num            = 256
      crush_rule        = "ec_4_2_host_then_drive"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "Existing EC content pool. Import and test provider readback before enabling management."
    }

    "config_data" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 16
      crush_rule        = "replicated_rule"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS config data pool."
    }

    "config_metadata" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 8
      crush_rule        = "replicated_rule"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS config metadata pool."
    }

    "backups_data" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 16
      crush_rule        = "replicated_rule"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS backups data pool."
    }

    "backups_metadata" = {
      managed           = false
      application       = "cephfs"
      size              = 3
      min_size          = 2
      pg_num            = 8
      crush_rule        = "replicated_rule"
      pg_autoscale_mode = "on"
      owner             = "terraform"
      notes             = "CephFS backups metadata pool."
    }
  }
}
