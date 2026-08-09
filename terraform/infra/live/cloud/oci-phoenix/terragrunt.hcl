# OCI Phoenix networking (ENG-451) -- VCN, dual-stack subnet, IGW, security
# list, Reserved Public IP. First piece of the standalone Talos node for the
# kabinett orchestrator (ENG-452/453/454, project "OCI Phoenix Talos Node").
#
# Deliberately no NAT Gateway / private-subnet-only design here: the compute
# instance (ENG-452) needs its own public IP for the Reserved Public IP to
# attach to and for outbound HTTPS to Cloudflare/Supabase/Anthropic/
# OpenRouter. Inbound is what's locked down -- see the security list below.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  vcn_cidr        = "10.20.0.0/24"
  subnet_cidr     = "10.20.0.0/24"
  account_prefix  = "oci_sulaimanahmad" # matches the sops field prefix; second account (sulibot) gets its own unit later, not a variable here
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
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

provider "sops" {}

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "oci" {
  tenancy_ocid     = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  user_ocid        = data.sops_file.secrets.data["${local.account_prefix}_user_ocid"]
  fingerprint      = data.sops_file.secrets.data["${local.account_prefix}_fingerprint"]
  private_key      = data.sops_file.secrets.data["${local.account_prefix}_private_key"]
  region           = data.sops_file.secrets.data["${local.account_prefix}_region"]
}

resource "oci_core_vcn" "this" {
  compartment_id = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  cidr_blocks    = ["${local.vcn_cidr}"]
  display_name   = "oci-phoenix-talos"
  dns_label      = "ocitalos"
  is_ipv6enabled = true
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-phoenix-talos-igw"
  enabled        = true
}

resource "oci_core_default_route_table" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id  = oci_core_internet_gateway.this.id
  }

  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id  = oci_core_internet_gateway.this.id
  }
}

# Default-deny inbound. Talos API (50000) and Kubernetes API (6443) are never
# exposed here -- reached only via the WireGuard tunnel (ENG-453), which
# terminates on the instance itself, not through a security-list allow rule.
# No port 22 either; SSH (if ever needed) goes over the same tunnel.
resource "oci_core_security_list" "this" {
  compartment_id = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-phoenix-talos-default-deny-inbound"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol          = "all"
    stateless         = false
  }

  egress_security_rules {
    destination      = "::/0"
    destination_type = "CIDR_BLOCK"
    protocol          = "all"
    stateless         = false
  }

  # WireGuard UDP inbound -- the one deliberate hole, required for the
  # RouterOS peer's handshake to reach this node at all (ENG-453). All other
  # inbound stays denied by the security list's implicit default.
  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "17" # udp
    stateless   = false

    udp_options {
      min = 51820
      max = 51820
    }
  }
}

resource "oci_core_subnet" "this" {
  compartment_id             = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "${local.subnet_cidr}"
  ipv6cidr_block              = cidrsubnet(oci_core_vcn.this.ipv6cidr_blocks[0], 8, 0)
  display_name               = "oci-phoenix-talos-public"
  dns_label                  = "public"
  route_table_id              = oci_core_default_route_table.this.id
  security_list_ids           = [oci_core_security_list.this.id]
  prohibit_public_ip_on_vnic = false
}

# Unattached for now -- ENG-452 attaches this to the compute instance's VNIC
# private IP once it exists. RESERVED (not EPHEMERAL) specifically so it
# survives instance stop/recreate -- it's the fixed WireGuard endpoint
# RouterOS's dynamic-IP side connects to (ENG-453).
resource "oci_core_public_ip" "talos_node" {
  compartment_id = data.sops_file.secrets.data["${local.account_prefix}_tenancy_ocid"]
  display_name   = "oci-phoenix-talos-reserved-ip"
  lifetime       = "RESERVED"
}

output "vcn_id" {
  value = oci_core_vcn.this.id
}

output "subnet_id" {
  value = oci_core_subnet.this.id
}

output "vcn_ipv6_cidr" {
  value = oci_core_vcn.this.ipv6cidr_blocks
}

output "subnet_ipv6_cidr" {
  value = oci_core_subnet.this.ipv6cidr_block
}

output "reserved_public_ip" {
  value = oci_core_public_ip.talos_node.ip_address
}

output "reserved_public_ip_id" {
  value = oci_core_public_ip.talos_node.id
}
EOF2
}
