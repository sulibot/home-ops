locals {
  ansible_inventory_content = join("\n", concat(
    ["[all]"],
    [for i in range(var.cp_quantity) : 
      format("${var.name_prefix}-controlplane-%d      ansible_host=%s%d    ansible_user=root", i + 1, var.ipv6_address_prefix, i + var.cp_octet_start)
    ],
    [for i in range(var.wkr_quantity) : 
      format("${var.name_prefix}-worker-%d            ansible_host=%s%d    ansible_user=root", i + 1, var.ipv6_address_prefix, i + var.wkr_octet_start)
    ],
    ["\n[kube_control_plane]"],
    [for i in range(var.cp_quantity) : 
      format("${var.name_prefix}-controlplane-%d      ansible_host=%s%d    ansible_user=root", i + 1, var.ipv6_address_prefix, i + var.cp_octet_start)
    ],
    ["\n[kube_worker]"],
    [for i in range(var.wkr_quantity) : 
      format("${var.name_prefix}-worker-%d            ansible_host=%s%d    ansible_user=root", i + 1, var.ipv6_address_prefix, i + var.wkr_octet_start)
    ],
    ["\n[etcd]"],
    [for i in range(
      var.cp_quantity == 1 ? 1 : var.cp_quantity == 2 ? 1 : 3
    ) : 
      format("${var.name_prefix}-controlplane-%d      ansible_host=%s%d    ansible_user=root", i + 1, var.ipv6_address_prefix, i + var.cp_octet_start)
    ],
    ["\n[k8s_cluster:children]"],
    ["kube_worker"],
    ["kube_control_plane"]
  ))
}

resource "local_file" "ansible_inventory_file" {
  filename = "../../../ansible/proxmox/${var.name_prefix}_cluster_inventory.ini"
  content  = local.ansible_inventory_content
}

output "ansible_inventory" {
  value = local.ansible_inventory_content
}
