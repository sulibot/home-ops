locals {
  region        = "home-lab"
  talos_version = "v1.8.2"
}

remote_state {
  backend = "local"
  config = {
    path = "terragrunt-cache/${path_relative_to_include()}/terraform.tfstate"
  }
}

terraform {
  extra_arguments "region_var" {
    commands  = get_terraform_commands_that_need_vars()
    arguments = ["-var", "region=${local.region}"]
  }
}

inputs = {
  talos_version = local.talos_version
}
