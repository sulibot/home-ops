terraform {
  required_version = ">= 1.10.0"

  backend "local" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.40.0, < 8.0.0"
    }
  }
}

locals {
  project_id           = "sulibot-openbao-kms"
  bucket_name          = "sulibot-terraform-state"
  location             = "US-CENTRAL1"
  service_account_id   = "terraform-state"
  github_repository    = "sulibot/home-ops"
  github_repository_id = "912241670"
  github_actor_id      = "6082800"
  operator_iam_member  = "user:sulibot@gmail.com"
  backup_reader_member = "serviceAccount:content-archive-writer@sulibot-personal-archive.iam.gserviceaccount.com"
  version_history_days = 90
  soft_delete_seconds  = 1209600
}

provider "google" {
  project = local.project_id
}

resource "google_project_service" "required" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ])

  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "terraform_state" {
  project      = local.project_id
  account_id   = local.service_account_id
  display_name = "Terraform state backend"
  description  = "Keyless, least-privilege identity for the dedicated Terraform GCS backend"

  deletion_policy = "PREVENT"

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_project_iam_custom_role" "terraform_state_backend" {
  project     = local.project_id
  role_id     = "terraformStateBackend"
  title       = "Terraform state backend"
  description = "Minimum GCS bucket and object permissions required by Terragrunt and the GCS backend"
  stage       = "GA"
  permissions = [
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
  ]

  deletion_policy = "PREVENT"

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_storage_bucket" "terraform_state" {
  project                     = local.project_id
  name                        = local.bucket_name
  location                    = local.location
  storage_class               = "STANDARD"
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  deletion_policy = "PREVENT"

  versioning {
    enabled = true
  }

  soft_delete_policy {
    retention_duration_seconds = local.soft_delete_seconds
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      days_since_noncurrent_time = local.version_history_days
      with_state                 = "ARCHIVED"
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required["storage.googleapis.com"]]
}

resource "google_storage_bucket_iam_member" "terraform_state_backend" {
  bucket = google_storage_bucket.terraform_state.name
  role   = google_project_iam_custom_role.terraform_state_backend.name
  member = google_service_account.terraform_state.member
}

resource "google_storage_bucket_iam_member" "backup_reader" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectViewer"
  member = local.backup_reader_member
}

resource "google_service_account_iam_member" "operator_impersonation" {
  service_account_id = google_service_account.terraform_state.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.operator_iam_member
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = local.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "Keyless GitHub Actions authentication for ${local.github_repository}"
  deletion_policy           = "PREVENT"

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "home-ops"
  display_name                       = "home-ops GitHub Actions"
  description                        = "Restricted to the home-ops repository and the repository owner"
  deletion_policy                    = "PREVENT"

  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.actor_id"      = "assertion.actor_id"
  }

  attribute_condition = "assertion.repository_id == '${local.github_repository_id}' && assertion.actor_id == '${local.github_actor_id}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.terraform_state.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${local.github_repository_id}"
}

output "backend" {
  value = {
    bucket                     = google_storage_bucket.terraform_state.name
    location                   = google_storage_bucket.terraform_state.location
    service_account_email      = google_service_account.terraform_state.email
    workload_identity_provider = google_iam_workload_identity_pool_provider.github.name
  }
}
