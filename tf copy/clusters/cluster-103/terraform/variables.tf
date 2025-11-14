variable "pm_api_url"        { type = string, description = "Proxmox API URL (CHANGE_ME)" }
variable "pm_api_token"      { type = string, sensitive = true, description = "Proxmox API token (CHANGE_ME)" }
variable "pm_insecure"       { type = bool,   default = true }

variable "pm_datastore_id"   { type = string, description = "Where to upload image (e.g., local)" }
variable "pm_vm_datastore"   { type = string, description = "Datastore for VM disks (e.g., rdb-vm)" }
variable "pm_snippets_datastore" { type = string, description = "Datastore for snippets/cloud-init" }

variable "pm_node_primary"   { type = string, description = "Primary node for uploads (e.g., pve01)" }
variable "pm_nodes"          { type = list(string), description = "Round-robin nodes, e.g., ["pve01","pve02","pve03"]" }

variable "vm_bridge_public"  { type = string, description = "Bridge name for public network (e.g., vmbr0)" }
variable "vm_vlan_public"    { type = number, default = 0 }
variable "vm_bridge_mesh"    { type = string, description = "Bridge name for mesh network (e.g., vmbr101)" }
variable "vm_vlan_mesh"      { type = number, default = 101 }

variable "vm_cpu_cores"      { type = number, default = 4 }
variable "vm_memory_mb"      { type = number, default = 8192 }
variable "vm_disk_gb"        { type = number, default = 60 }
