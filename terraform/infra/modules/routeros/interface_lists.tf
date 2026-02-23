resource "routeros_interface_list" "lists" {
  for_each = toset(var.interface_lists)
  name     = each.key
}

resource "routeros_interface_list_member" "members" {
  for_each  = { for m in var.interface_list_members : "${m.list}-${m.interface}" => m }
  list      = each.value.list
  interface = each.value.interface
}
