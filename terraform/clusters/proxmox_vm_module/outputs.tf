locals {
  ansible_inventory_content = join("\n", concat(
    ["[all]"],
    [for i in range(var.cp_quantity) : 
      format("${var.cluster_name}cp%02d            ansible_host=%s%d     ansible_user=root", i + 1, var.cluster.ipv6_egress_prefix, i + var.cp_octet_start)
    ],
    [for i in range(var.wkr_quantity) : 
      format("${var.cluster_name}wk%02d            ansible_host=%s%d    ansible_user=root", i + 1, var.cluster.ipv6_egress_prefix, i + var.wkr_octet_start)
    ],
    ["\n[controlplane]"],
    [for i in range(var.cp_quantity) : 
      format("${var.cluster_name}cp%02d            ansible_host=%s%d     ansible_user=root", i + 1, var.cluster.ipv6_egress_prefix, i + var.cp_octet_start)
    ],
    ["\n[worker]"],
    [for i in range(var.wkr_quantity) : 
      format("${var.cluster_name}wk%02d            ansible_host=%s%d    ansible_user=root", i + 1, var.cluster.ipv6_egress_prefix, i + var.wkr_octet_start)
    ],
    ["\n[etcd]"],
    [for i in range(
      var.cp_quantity == 1 ? 1 : var.cp_quantity == 2 ? 1 : 3
    ) : 
      format("${var.cluster_name}cp%02d            ansible_host=%s%d     ansible_user=root", i + 1, var.cluster.ipv6_egress_prefix, i + var.cp_octet_start)
    ],
    ["\n[cluster:children]"],
    ["worker"],
    ["controlplane"]
  ))
}

resource "local_file" "ansible_inventory_file" {
  filename = "../../../ansible/proxmox/${var.cluster_name}_cluster_inventory.ini"
  content  = local.ansible_inventory_content
}

output "ansible_inventory" {
  value = local.ansible_inventory_content
}
