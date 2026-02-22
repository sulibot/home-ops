# Static DNS records — infra-managed only.
#
# IMPORTANT: Records with ttl=0s owned by Kubernetes external-dns MUST NOT be
# added here. external-dns and Terraform will fight for ownership and external-dns
# will lose (or records will flip-flop). Only add records that are permanently
# static (pve hostnames, infrastructure services, etc.) with ttl > 0.

resource "routeros_ip_dns_record" "records" {
  for_each = { for r in var.dns_records : "${r.type}-${r.name}" => r }

  name     = each.value.name
  type     = each.value.type
  address  = each.value.address
  text     = each.value.text
  disabled = each.value.disabled
  ttl      = each.value.ttl
  comment  = each.value.comment != "" ? each.value.comment : null
}
