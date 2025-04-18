data "external" "password_hash" {
  program = [
    "sh", "-c", 
    "echo '{\"password\": \"'$(openssl passwd -6 \"${local.vm_password}\")'\"}'"
  ]
}
