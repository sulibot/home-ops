locals {
  region = "home-lab"
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
