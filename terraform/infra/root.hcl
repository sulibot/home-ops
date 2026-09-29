locals {
  region = "home-lab"
}

remote_state {
  backend = "gcs"
  config = {
    bucket                      = "sulibot-terraform-state"
    prefix                      = path_relative_to_include()
    impersonate_service_account = "terraform-state@sulibot-openbao-kms.iam.gserviceaccount.com"

    # The bucket is managed by the isolated terraform/bootstrap/gcs-state
    # root. Terragrunt must never create or mutate it implicitly.
    project                = "sulibot-openbao-kms"
    location               = "us-central1"
    skip_bucket_creation   = true
    skip_bucket_versioning = true
  }
}

inputs = {
  # Use TF_VAR inputs rather than injected CLI flags: saved-plan apply must
  # receive only its plan filename, with variable values frozen in that plan.
  region = local.region
}
