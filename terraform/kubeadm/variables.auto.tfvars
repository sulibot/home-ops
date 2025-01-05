# variables.auto.tfvars
euclid = {
  node_name = "euclid"
  endpoint  = "https://192.168.1.42:8006"
  insecure  = true
}

# variables.auto.tfvars
vm_dns = {
  domain  = "."
  servers = ["1.1.1.1", "8.8.8.8"]
}

vm_user      = "<USER>"
vm_password  = "<HASHED PASSWORD>"
host_pub-key = "<PUBLIC SSH KEY>"

k8s-version        = "1.29"
cilium-cli-version = "0.16.4"

