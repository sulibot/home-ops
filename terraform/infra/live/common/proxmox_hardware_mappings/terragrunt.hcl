locals {
  # ---------------------------------------------------------------------------
  # PCI Mappings for Intel iGPU SR-IOV
  # ---------------------------------------------------------------------------
  # To find the device ID, run: lspci -nn | grep VGA
  # Example output: "00:02.1 VGA compatible controller [0300]: Intel Corporation AlderLake-S GT1 [8086:4680]"
  # The ID is the vendor:product pair in brackets, e.g., "8086:4680"
  # Note: pve03 (Comet Lake UHD 630) does not support SR-IOV
  pci_mappings = [
    {
      name    = "intel-igpu-vf1"
      comment = "Intel iGPU SR-IOV VF 1 (Alder Lake, 00:02.1)"
      maps = [
        { id = "8086:4680", node = "pve01", path = "0000:00:02.1" },
        { id = "8086:4680", node = "pve02", path = "0000:00:02.1" },
      ]
    },
    {
      name    = "intel-igpu-vf2"
      comment = "Intel iGPU SR-IOV VF 2 (Alder Lake, 00:02.2)"
      maps = [
        { id = "8086:4680", node = "pve01", path = "0000:00:02.2" },
        { id = "8086:4680", node = "pve02", path = "0000:00:02.2" },
      ]
    }
    # Add more VFs as needed (vf3, vf4, etc.)
    # pve01/pve02 support up to 7 VFs each (00:02.1 through 00:02.7)
  ]

  pci_mapping_paths = {
    for mapping in local.pci_mappings :
    mapping.name => {
      for entry in mapping.maps :
      entry.node => entry.path
    }
  }

  # ---------------------------------------------------------------------------
  # USB Mappings for Home Assistant Zigbee/Thread Radio
  # ---------------------------------------------------------------------------
  usb_mappings = [
    {
      name    = "sonoff-zigbee"
      comment = "Sonoff ZBDongle-E Thread/Matter Radio (1a86:55d4)"
      maps = [
        # Map by Vendor:Product ID. This allows Proxmox to find the device
        # regardless of which USB port it's plugged into on the specified node.
        # Check `lsusb` on your PVE hosts to confirm the ID.
        { node = "pve01", id = "1a86:55d4" },
        { node = "pve02", id = "1a86:55d4" },
        { node = "pve03", id = "1a86:55d4" },
      ]
    }
  ]

  usb_mapping_ids = {
    for mapping in local.usb_mappings :
    mapping.name => {
      for entry in mapping.maps :
      entry.node => entry.id
    }
  }

  # Provider credentials
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
}

terraform {
  source = "../../../modules/proxmox_hardware_mappings"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "versions" {
  path = find_in_parent_folders("common/versions.hcl")
}

include "credentials" {
  path = find_in_parent_folders("common/credentials.hcl")
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF
}

inputs = {
  pci_mappings = local.pci_mappings
  usb_mappings = local.usb_mappings
}
