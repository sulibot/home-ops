include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  project_id = get_env("OPENBAO_GCP_KMS_PROJECT_ID", "sulibot-openbao-kms")
  location   = get_env("OPENBAO_GCP_KMS_LOCATION", "global")
  key_ring   = get_env("OPENBAO_GCP_KMS_KEY_RING", "openbao")
  crypto_key = get_env("OPENBAO_GCP_KMS_CRYPTO_KEY", "auto-unseal")
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
terraform {
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.40.0, < 8.0.0"
    }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

provider "google" {
  project = "${local.project_id}"
}

locals {
  project_id = "${local.project_id}"
  location   = "${local.location}"
  key_ring   = "${local.key_ring}"
  crypto_key = "${local.crypto_key}"
}

resource "google_project_service" "cloudkms" {
  project            = local.project_id
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = local.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_kms_key_ring" "openbao" {
  name       = local.key_ring
  location   = local.location
  depends_on = [google_project_service.cloudkms]
}

resource "google_kms_crypto_key" "openbao_auto_unseal" {
  name                       = local.crypto_key
  key_ring                   = google_kms_key_ring.openbao.id
  purpose                    = "ENCRYPT_DECRYPT"
  destroy_scheduled_duration = "2592000s"
  deletion_policy            = "PREVENT"

  # Do not set rotation_period for this homelab seal. GCP bills every active
  # key version, old OpenBao seal ciphertext may still require an older
  # version, and rotating the KMS key does not revoke a leaked service-account
  # credential. Rotate the restricted service-account credential instead.
  labels = {
    application = "openbao"
    purpose     = "auto-unseal"
    managed_by  = "opentofu"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "openbao_auto_unseal" {
  project      = local.project_id
  account_id   = "openbao-auto-unseal"
  display_name = "OpenBao auto-unseal"
  description  = "Non-human principal used only to wrap and unwrap the OpenBao barrier key"
  depends_on   = [google_project_service.iam]
}

resource "google_project_iam_custom_role" "openbao_kms_seal" {
  project     = local.project_id
  role_id     = "openbaoKmsSeal"
  title       = "OpenBao KMS seal"
  description = "Minimum GCP KMS permissions required by the OpenBao gcpckms seal"
  stage       = "GA"
  permissions = [
    "cloudkms.cryptoKeyVersions.useToEncrypt",
    "cloudkms.cryptoKeyVersions.useToDecrypt",
    "cloudkms.cryptoKeys.get",
  ]
  depends_on = [google_project_service.iam]
}

resource "google_kms_crypto_key_iam_member" "openbao_auto_unseal" {
  crypto_key_id = google_kms_crypto_key.openbao_auto_unseal.id
  role          = google_project_iam_custom_role.openbao_kms_seal.name
  member        = "serviceAccount:$${google_service_account.openbao_auto_unseal.email}"
}

output "openbao_kms" {
  value = {
    project_id            = local.project_id
    location              = google_kms_key_ring.openbao.location
    key_ring              = google_kms_key_ring.openbao.name
    crypto_key            = google_kms_crypto_key.openbao_auto_unseal.name
    service_account_email = google_service_account.openbao_auto_unseal.email
  }
}
EOF2
}
