resource "null_resource" "write_token_to_sops" {
  count = var.write_token_to_sops ? 1 : 0

  triggers = {
    sops_file_path = var.sops_file_path
    token_id_hash  = sha1(local._tok_id)
    token_sec_hash = sha1(local._tok_secret)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-euo", "pipefail", "-c"]
    command = <<-EOT
      if ! command -v sops >/dev/null 2>&1; then
        echo "ERROR: sops not found in PATH" >&2
        exit 1
      fi
      if [ ! -f "${var.sops_file_path}" ]; then
        echo "ERROR: SOPS file not found: ${var.sops_file_path}" >&2
        exit 1
      fi

      # In-place set both keys in one run (SOPS v3.7+)
      sops -i \
        --set '["pve_api_token_id"] "${local._tok_id}"' \
        --set '["pve_api_token_secret"] "${local._tok_secret}"' \
        "${var.sops_file_path}"
    EOT
  }

  depends_on = [proxmox_virtual_environment_user_token.terraform_token]
}
