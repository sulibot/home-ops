module "control_planes" {
  source = "./instance_group"

  # Group / topology
  group                    = var.control_plane
  cluster_id               = var.cluster_id
  cluster_name             = var.cluster_name

  # Proxmox / cloud-init artifacts
  datastore_id             = var.datastore_id
  snippet_datastore_id     = var.snippet_datastore_id
  template_vmid            = var.template_vmid
  cloudinit_template_file  = var.cloudinit_template_file
  frr_template_file        = var.frr_template_file

  # RouterOS (for DNS records)
  routeros_hosturl         = var.routeros_hosturl
  routeros_username        = var.routeros_username
  routeros_password        = var.routeros_password

  # Stack flags (control-plane)
  enable_ipv4              = try(var.control_plane.enable_ipv4, true)
  enable_ipv6              = try(var.control_plane.enable_ipv6, true)
}

module "workers" {
  source = "./instance_group"

  # Group / topology
  group                    = var.workers
  cluster_id               = var.cluster_id
  cluster_name             = var.cluster_name

  # Proxmox / cloud-init artifacts
  datastore_id             = var.datastore_id
  snippet_datastore_id     = var.snippet_datastore_id
  template_vmid            = var.template_vmid
  cloudinit_template_file  = var.cloudinit_template_file
  frr_template_file        = var.frr_template_file

  # RouterOS (for DNS records)
  routeros_hosturl         = var.routeros_hosturl
  routeros_username        = var.routeros_username
  routeros_password        = var.routeros_password

  # Stack flags (workers) — NOTE: pull from var.workers, not control_plane
  enable_ipv4              = try(var.workers.enable_ipv4, true)
  enable_ipv6              = try(var.workers.enable_ipv6, true)
}

output "control_planes" {
  value = module.control_planes
}

output "workers" {
  value = module.workers
}
