terraform {
  backend "local" {}

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Exposes BGP/SDN/RouterOS values that already live as Terraform locals in
# network-infrastructure.hcl to Ansible, as a plain checked-in JSON file -
# no wrapper script, no provisioner. ansible/pve/inventory/group_vars/all.yml
# reads this directly via a `lookup('file', ...) | from_json` and re-exposes
# it as `network_facts`.
#
# This exists because the FRR power-event incident
# (docs/tickets/pve-frr-power-event-20260712.md) was caused in part by these
# same values being hand-typed independently in ansible group_vars and
# drifting from what's declared here.
resource "local_file" "ansible_network_facts" {
  filename        = "${var.repo_root}/ansible/network-facts.json"
  file_permission = "0644"
  content = jsonencode({
    bgp_asn_base   = var.bgp_asn_base
    bgp_remote_asn = var.bgp_remote_asn
    sdn_mtu        = var.sdn_mtu
    sdn_vrf_vxlan  = var.sdn_vrf_vxlan
    sdn_zone_id    = var.sdn_zone_id
    routeros       = var.routeros
  })
}
