locals {
  secrets_file = "${get_repo_root()}/terraform/infra/live/common/secrets.sops.yaml"
}

inputs = {
  secrets_file = local.secrets_file
}
