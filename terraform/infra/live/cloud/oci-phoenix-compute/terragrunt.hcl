# OCI Phoenix compute (ENG-452) -- custom Talos arm64 image import + the
# Ampere A1.Flex instance itself. Depends on ENG-451's networking (subnet +
# Reserved Public IP). Talos machine-config generation/apply/bootstrap is
# deliberately NOT done here: the security list only opens WireGuard/51820
# inbound, so the Talos API (50000) isn't reachable until ENG-453 stands up
# the tunnel. This unit stops at "instance is running, image is AVAILABLE."

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  versions     = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals

  account_prefix = "oci_sulaimanahmad"

  # versions.hcl pins amd64 (Proxmox metal nodes) -- deliberate arm64
  # deviation here, matching Ampere A1.Flex, the free-tier shape.
  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version
  talos_architecture = "arm64"

  image_dir = "${get_repo_root()}/talos/_out/oci-phoenix"
}

dependency "networking" {
  config_path = "${get_terragrunt_dir()}/../oci-phoenix"

  mock_outputs = {
    subnet_id             = "mock-subnet-id"
    reserved_public_ip    = "0.0.0.0"
    reserved_public_ip_id = "mock-public-ip-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
terraform {
  backend "gcs" {}
  required_providers {
    oci  = { source = "oracle/oci", version = ">= 6.0.0, < 7.0.0" }
    sops = { source = "carlpett/sops", version = "~> 1.4.0" }
    null = { source = "hashicorp/null", version = "~> 3.2.0" }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

# A1.Flex free-tier capacity is scarce and varies by AD; index picks which
# of the tenancy's 3 PHX ADs to launch into, so a capacity-exhausted AD can
# be retried against another without editing this file.
variable "ad_index" {
  type    = number
  default = 0
}

provider "sops" {}

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "oci" {
  tenancy_ocid = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  user_ocid    = data.sops_file.secrets.data["${local.account_prefix}_user_ocid"]
  fingerprint  = data.sops_file.secrets.data["${local.account_prefix}_fingerprint"]
  private_key  = data.sops_file.secrets.data["${local.account_prefix}_private_key"]
  region       = data.sops_file.secrets.data["${local.account_prefix}_region"]
}

locals {
  compartment_id = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  talos_version  = "${local.talos_version}"
  talos_arch     = "${local.talos_architecture}"
  image_dir      = "${local.image_dir}"
  bucket_name    = "oci-phoenix-talos-images"
  object_name    = "talos-$${local.talos_version}-$${local.talos_arch}.oci"

  # Object Storage namespace is a fixed, tenancy-wide constant (confirmed via
  # `oci os ns get`). Hardcoded rather than read via the
  # oci_objectstorage_namespace data source: feeding that computed value into
  # a required argument on oci_objectstorage_bucket trips a provider-level
  # "Missing required argument" plan error (oracle/oci v6.37.0).
  object_storage_namespace = "axx57zesnjxy"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

resource "oci_objectstorage_bucket" "talos_images" {
  compartment_id = local.compartment_id
  namespace      = local.object_storage_namespace
  name           = local.bucket_name
}

# Fetches a Talos Image Factory schematic, downloads oracle-arm64.qcow2 for
# the pinned Talos version, and packages it with OCI's required
# image_metadata.json into a .oci tar -- OCI's custom-image import format.
resource "null_resource" "build_talos_image" {
  triggers = {
    talos_version = local.talos_version
    talos_arch    = local.talos_arch
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      mkdir -p "${local.image_dir}"
      cd "${local.image_dir}"

      # Idempotent: if a previous run (or a manual pre-build) already
      # produced the archive, leave it untouched. Rebuilding it here would
      # change its mtime between plan and apply, which the oci provider
      # bakes into oci_objectstorage_object's "source" diff and trips a
      # "Provider produced inconsistent final plan" error.
      if [ -f "talos-${local.talos_version}-${local.talos_architecture}.oci" ]; then
        echo "talos-${local.talos_version}-${local.talos_architecture}.oci already built, skipping"
        exit 0
      fi

      SCHEMATIC_ID=$(curl -sf "https://factory.talos.dev/schematics" \
        -X POST -H "Content-Type: application/json" -d '{"customization":{}}' | jq -r '.id')
      echo "Factory schematic: $SCHEMATIC_ID"

      curl -sfL -o oracle-arm64.qcow2 \
        "https://factory.talos.dev/image/$SCHEMATIC_ID/${local.talos_version}/oracle-arm64.qcow2"

      TALOS_SEMVER="$(echo "${local.talos_version}" | sed 's/^v//')"

      cat > image_metadata.json <<JSON
      {
        "version": 2,
        "externalLaunchOptions": {
          "firmware": "UEFI_64",
          "networkType": "PARAVIRTUALIZED",
          "bootVolumeType": "PARAVIRTUALIZED",
          "remoteDataVolumeType": "PARAVIRTUALIZED",
          "localDataVolumeType": "PARAVIRTUALIZED",
          "launchOptionsSource": "PARAVIRTUALIZED",
          "pvAttachmentVersion": 2,
          "pvEncryptionInTransitEnabled": true,
          "consistentVolumeNamingEnabled": true
        },
        "imageCapabilityData": null,
        "imageCapsFormatVersion": null,
        "operatingSystem": "Talos",
        "operatingSystemVersion": "$TALOS_SEMVER",
        "additionalMetadata": {
          "shapeCompatibilities": [
            {
              "internalShapeName": "VM.Standard.A1.Flex",
              "ocpuConstraints": null,
              "memoryConstraints": null
            }
          ]
        }
      }
JSON

      tar zcf "$${local.object_name}" oracle-arm64.qcow2 image_metadata.json
      echo "Built ${local.image_dir}/$${local.object_name}"
    EOT
  }
}

resource "oci_objectstorage_object" "talos_image" {
  namespace = local.object_storage_namespace
  bucket    = oci_objectstorage_bucket.talos_images.name
  object    = local.object_name
  source    = "$${local.image_dir}/$${local.object_name}"

  depends_on = [null_resource.build_talos_image]
}

resource "oci_core_image" "talos" {
  compartment_id = local.compartment_id
  display_name   = "talos-$${local.talos_version}-$${local.talos_arch}"
  launch_mode    = "PARAVIRTUALIZED"

  image_source_details {
    source_type             = "objectStorageTuple"
    namespace_name           = local.object_storage_namespace
    bucket_name              = oci_objectstorage_bucket.talos_images.name
    object_name              = oci_objectstorage_object.talos_image.object
    operating_system         = "Talos"
    operating_system_version = local.talos_version
    source_image_type        = "QCOW2"
  }

  timeouts {
    create = "30m"
  }
}

resource "oci_core_instance" "talos_node" {
  compartment_id      = local.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index].name
  display_name        = "oci-phoenix-talos-01"
  shape                = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  source_details {
    source_type             = "image"
    source_id                = oci_core_image.talos.id
    boot_volume_size_in_gbs  = 50
  }

  create_vnic_details {
    subnet_id        = "${dependency.networking.outputs.subnet_id}"
    assign_public_ip = false
    assign_ipv6ip     = true
  }

  is_pv_encryption_in_transit_enabled = true

  # Talos has no cloud-init/metadata-service agent by default; nothing to
  # inject at launch. Machine config is applied later, over the WireGuard
  # tunnel (ENG-453), via talosctl against the Talos API directly.

  depends_on = [oci_core_image.talos]
}

data "oci_core_vnic_attachments" "talos_node" {
  compartment_id = local.compartment_id
  instance_id     = oci_core_instance.talos_node.id
}

data "oci_core_private_ips" "talos_node" {
  vnic_id = data.oci_core_vnic_attachments.talos_node.vnic_attachments[0].vnic_id
}

# The Reserved Public IP was created unattached in ENG-451's unit (its own
# Terraform state). Attaching it here -- rather than managing that same
# resource in two states -- via a direct API call once the instance's
# private IP OCID exists.
resource "null_resource" "attach_reserved_ip" {
  triggers = {
    instance_id = oci_core_instance.talos_node.id
    private_ip  = data.oci_core_private_ips.talos_node.private_ips[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      oci network public-ip update \
        --public-ip-id "${dependency.networking.outputs.reserved_public_ip_id}" \
        --private-ip-id "$${data.oci_core_private_ips.talos_node.private_ips[0].id}" \
        --force
    EOT
  }

  depends_on = [oci_core_instance.talos_node]
}

output "image_id" {
  value = oci_core_image.talos.id
}

output "instance_id" {
  value = oci_core_instance.talos_node.id
}

output "instance_private_ip" {
  value = data.oci_core_private_ips.talos_node.private_ips[0].ip_address
}

output "instance_public_ip" {
  value = "${dependency.networking.outputs.reserved_public_ip}"
}
EOF2
}
