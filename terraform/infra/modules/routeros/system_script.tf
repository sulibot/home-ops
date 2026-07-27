resource "routeros_system_script" "scripts" {
  for_each = { for s in var.system_scripts : s.name => s }

  name                     = each.value.name
  policy                   = each.value.policy
  dont_require_permissions = each.value.dont_require_permissions
  source                   = each.value.source
}
