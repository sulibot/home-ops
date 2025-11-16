variable "pve_endpoint" {
  description = "The endpoint for the Proxmox Virtual Environment API (e.g., https://pve01.sulibot.com:8006/api2/json)"
  type        = string
}

variable "pve_api_token_id" {
  description = "The API token ID for the Proxmox Virtual Environment"
  type        = string
}

variable "pve_api_token_secret" {
  description = "The API token secret for the Proxmox Virtual Environment"
  type        = string
}

variable "pve_username" {
  description = "The username for the Proxmox Virtual Environment API"
  type        = string
}

variable "pve_password" {
  description = "The password for the Proxmox Virtual Environment API"
  type        = string
  sensitive   = true
}

variable "template_image_id" {
  type        = string
  description = "ID of the uploaded base image to attach to the template VM disk"
}

variable "vm_host" {
  type        = string
  description = "The host for the VM"
  default     = "node"
}

variable "latest_debian_12_bookworm_qcow2_img_url" {
  type        = string
  description = "The URL for the latest Debian 12 Bookworm qcow2 image"
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}

variable "release_20240725_ubuntu_24_noble_lxc_img_url" {
  type        = string
  description = "The URL for the Ubuntu 24.04 LXC image"
  default     = "https://mirrors.servercentral.com/ubuntu-cloud-images/releases/24.04/release-20240725/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz"
}

variable "release_20240725_ubuntu_24_noble_lxc_img_checksum" {
  type        = string
  description = "The checksum for the Ubuntu 24.04 LXC image"
  default     = "d767d38cb25b2c25d84edc31a80dd1c29a8c922b74188b0e14768b2b2fb6df8e"
}

variable "vm_password" {
  description = "The password to be used for cloud-init users."
  type        = string
  sensitive   = true
}

# ---------------------------
# Provider SSH variables
# ---------------------------

variable "pve_ssh_user" {
  description = "SSH username for uploading snippets to the node"
  type        = string
  default     = "root"
}

variable "pve_ssh_agent" {
  description = "Use ssh-agent for SSH auth"
  type        = bool
  default     = true
}

variable "pve_ssh_private_key" {
  description = "Private key contents for SSH auth (set null to use ssh-agent)"
  type        = string
  default     = null
  sensitive   = true
}

variable "pve_ssh_host" {
  description = "SSH host for Proxmox node connections"
  type        = string
  default     = "pve01.sulibot.com"
}

# variables.tf

variable "node_name" {
  description = "The Proxmox node name where the Cloud-Init snippet should be uploaded."
  type        = string
}

