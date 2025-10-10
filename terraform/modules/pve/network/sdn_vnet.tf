# Creates/ensures VNets + IPv4/IPv6 subnets via pvesh on the primary SSH host.
# - Idempotent: checks for existing subnets by JSON `cidr` (uses jq if present, grep fallback).
# - Safe commit: handles PVE versions that expose create OR set for /cluster/sdn/commit.
# - Requires zones to exist; we depend_on the zone resources to enforce order.

resource "null_resource" "vnet_and_subnets" {
  for_each = var.configure_vnets ? var.sdn_clusters : {}

  triggers = {
    cluster_id = each.key
    zone_id    = "fab${each.key}"
    vnet_id    = "fab${each.key}"
    tag        = tostring(each.value.vnet_tag)

    v4_cidr = each.value.v4_cidr
    v4_gw   = cidrhost(each.value.v4_cidr, 1)

    v6_cidr = each.value.v6_cidr
    v6_gw   = cidrhost(each.value.v6_cidr, 1)

    # bump to force re-run if logic changes
    cmdhash = sha1("v4:${each.value.v4_cidr}:${cidrhost(each.value.v4_cidr,1)}|v6:${each.value.v6_cidr}:${cidrhost(each.value.v6_cidr,1)}|tag:${tostring(each.value.vnet_tag)}|ipv6-type=subnet")
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${local._primary_ssh} '
        set -e

        # Helper: does VNet <vnet> already have a subnet with cidr <cidr>?
        has_subnet() {
          local vnet="$1" cidr="$2"
          local out
          out="$(pvesh get /cluster/sdn/vnets/$${vnet}/subnets --output-format json || echo "[]")"
          if command -v jq >/dev/null 2>&1; then
            echo "$out" | jq -e --arg c "$cidr" '"'"'map(select(.cidr == $c)) | length > 0'"'"' >/dev/null
          else
            echo "$out" | grep -F -q "\"cidr\":\"$cidr\""
          fi
        }

        VNET="${self.triggers.vnet_id}"
        ZONE="${self.triggers.zone_id}"
        TAG="${self.triggers.tag}"

        V4="${self.triggers.v4_cidr}"
        V4GW="${self.triggers.v4_gw}"
        V6="${self.triggers.v6_cidr}"
        V6GW="${self.triggers.v6_gw}"

        # Ensure VNet exists or is updated
        if pvesh get /cluster/sdn/vnets/"$VNET" >/dev/null 2>&1; then
          pvesh set /cluster/sdn/vnets/"$VNET" -zone "$ZONE" -tag "$TAG"
        else
          pvesh create /cluster/sdn/vnets -vnet "$VNET" -zone "$ZONE" -tag "$TAG"
        fi

        # IPv4 subnet (type is "subnet")
        if ! has_subnet "$VNET" "$V4"; then
          pvesh create /cluster/sdn/vnets/"$VNET"/subnets \
            -type subnet \
            -subnet "$V4" \
            -gateway "$V4GW"
        fi

        # IPv6 subnet (also -type subnet)
        if ! has_subnet "$VNET" "$V6"; then
          pvesh create /cluster/sdn/vnets/"$VNET"/subnets \
            -type subnet \
            -subnet "$V6" \
            -gateway "$V6GW" || true
        fi

        # Commit SDN changes (API differs by PVE version)
        pvesh create /cluster/sdn/commit >/dev/null 2>&1 || \
        pvesh set /cluster/sdn/commit    >/dev/null 2>&1 || true
      '
    EOT
  }

  depends_on = [
    null_resource.evpn_controller,                  # controller ready
    proxmox_virtual_environment_sdn_zone_evpn.zone, # zones exist
  ]
}
