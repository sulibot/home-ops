# sdn_controller.tf
# Ensure EVPN controller exists (create/update via pvesh), then commit.

locals {
  _ctrl_id     = var.sdn_controller.id
  _asn         = var.sdn_controller.asn

  # Optional fabric input (set default to an empty string if null)
  _fabric_in   = try(var.sdn_controller.fabric, "")

  # Only trim if _fabric_in is not empty
  _fabric      = local._fabric_in != "" ? trimspace(local._fabric_in) : ""

  # Peers model (your current mode)
  _peers_list  = [for p in try(var.sdn_controller.peers, []) : trimspace(p) if trimspace(p) != ""]
  _has_peers   = length(local._peers_list) > 0
  _has_fabric  = length(local._fabric) > 0

  # Choose exactly one CLI arg: -peers ip1,ip2 OR -fabric <name>; else nothing
  _mode_arg    = local._has_peers ? "-peers ${join(",", local._peers_list)}" : (local._has_fabric ? "-fabric ${local._fabric}" : "")

  # Single owner of _primary_ssh (referenced by other files too)
  _primary_ssh = var.primary_ssh_host != "" ? var.primary_ssh_host : var.nodes[0].ssh_host
}

resource "null_resource" "evpn_controller" {
  triggers = {
    id      = local._ctrl_id
    asn     = tostring(local._asn)
    mode    = local._mode_arg
    cmdhash = sha1("controller:${local._ctrl_id}:${local._asn}:${local._mode_arg}")
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${local._primary_ssh} '
        set -e
        if pvesh get /cluster/sdn/controllers/${local._ctrl_id} >/dev/null 2>&1; then
          pvesh set /cluster/sdn/controllers/${local._ctrl_id} -asn ${local._asn} ${local._mode_arg}
        else
          pvesh create /cluster/sdn/controllers -type evpn -controller ${local._ctrl_id} -asn ${local._asn} ${local._mode_arg}
        fi
        # commit (API differs by PVE version)
        pvesh create /cluster/sdn/commit >/dev/null 2>&1 || pvesh set /cluster/sdn/commit >/dev/null 2>&1 || true
      '
    EOT
  }
}
