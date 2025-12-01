# -----------------------------
# Locals (normalize inputs)
# -----------------------------
locals {
  acme_directory_url = lower(var.acme_directory) == "production" ? "https://acme-v02.api.letsencrypt.org/directory" : (lower(var.acme_directory) == "staging" ? "https://acme-staging-v02.api.letsencrypt.org/directory" : var.acme_directory)

  # Build per-node command strings (single line; evaluated remotely)
  node_commands = {
    for n in var.nodes :
    n.ssh_host => join(" && ", concat(
      ["pvenode config set --acme account=${var.acme_account_name}"],
      [for idx, d in n.domains : "pvenode config set --acmedomain${idx} domain=${d},plugin=${var.dns_plugin.id}"],
      var.order_on_apply ? ["pvenode acme cert order --force 1", "systemctl restart pveproxy"] : []
    ))
  }
}

# 1) ACME account (must be root@pam; auto-accept ToS)
resource "proxmox_virtual_environment_acme_account" "this" {
  provider  = proxmox.rootpam
  name      = var.acme_account_name
  contact   = var.acme_contact_email
  directory = local.acme_directory_url
  tos       = true
}

# 2) DNS plugin
resource "proxmox_virtual_environment_acme_dns_plugin" "dns" {
  provider         = proxmox.rootpam
  plugin           = var.dns_plugin.id
  api              = var.dns_plugin.api
  data             = var.dns_plugin.data
  validation_delay = try(var.dns_plugin.validation_delay, 30)
}

# 3) Apply node config + optionally order the cert(s) via CLI
resource "null_resource" "order" {
  for_each = local.node_commands

  triggers = {
    account = proxmox_virtual_environment_acme_account.this.name
    plugin  = proxmox_virtual_environment_acme_dns_plugin.dns.plugin
    cmdhash = sha1(each.value)
  }

  provisioner "local-exec" {
    # Single quotes so && is processed by the remote shell, not JSON-escaped locally
    command = "ssh -o StrictHostKeyChecking=no ${each.key} '${each.value}'"
  }

  depends_on = [
    proxmox_virtual_environment_acme_account.this,
    proxmox_virtual_environment_acme_dns_plugin.dns
  ]
}
