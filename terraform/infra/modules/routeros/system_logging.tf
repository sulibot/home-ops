resource "routeros_system_logging" "rules" {
  for_each = { for l in var.system_logging_rules : join(",", l.topics) => l }

  topics = each.value.topics
  action = each.value.action
}
