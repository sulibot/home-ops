locals {
  secrets_file = "${get_repo_root()}/tf/infra/live/common/secrets.sops.yaml"
}

inputs = {
  secrets_file = local.secrets_file
}
