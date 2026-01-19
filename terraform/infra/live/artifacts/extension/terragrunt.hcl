# FRR Extension Build Stage
# Builds custom Talos extension for FRR (Free Range Routing) from source
#
# Purpose: Self-contained extension build for FRR routing daemon
# Output: ghcr.io/sulibot/frr-talos-extension:vX.X.X (with digest)
#
# Current Status: PLACEHOLDER - Extension currently built externally
# Source: https://github.com/sulibot/frr-talos-extension (assumed)
# Pre-built: ghcr.io/sulibot/frr-talos-extension:v1.0.33
#
# To enable local builds:
# 1. Clone FRR extension source to this repo or external location
# 2. Create/reference talos_extension module
# 3. Configure build process to produce extension image with pinned digest
# 4. Publish to ghcr.io/sulibot/frr-talos-extension:vX.X.X
# 5. Update common/install-schematic.hcl to reference local build output

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Disabled until FRR extension source is available in this repo
# terraform {
#   source = "../../../modules/talos_extension"
# }

locals {
  versions = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
}

# Placeholder inputs for future extension build
# inputs = {
#   extension_name    = "frr-talos-extension"
#   extension_version = "v1.0.19"  # Should come from versions.hcl
#
#   # Source repository for FRR extension code
#   source_repo = "https://github.com/sulibot/frr-talos-extension"
#   source_ref  = "v1.0.19"
#
#   # Output configuration
#   registry = "ghcr.io/sulibot"
#   image_name = "frr-talos-extension"
#
#   # FRR version and configuration
#   frr_version = "10.5.1"  # Should match FRR daemon version
# }

# Expected outputs (for consumption by images/ stage):
# - extension_image: Full image reference with digest
#   Example: ghcr.io/sulibot/frr-talos-extension:v1.0.33@sha256:abc123...
# - extension_version: Semantic version tag
#   Example: v1.0.19

# NOTE: Until this stage is implemented, clusters will continue using
# the pre-built extension specified in common/install-schematic.hcl:
#   ghcr.io/sulibot/frr-talos-extension:v1.0.33
