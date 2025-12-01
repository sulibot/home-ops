locals {
  # Compose lines for each section
  all_hosts = concat(
    [for i in range(var.control_plane.instance_count) :
      format("%s%s%03d ansible_host=%s::%d ansible_user=root",
        var.cluster_name,
        var.control_plane.role_id,
        var.control_plane.segment_start + i,
        "fd00:${var.cluster_id}",
        var.control_plane.segment_start + i
      )
    ],
    [for i in range(var.workers.instance_count) :
      format("%s%s%03d ansible_host=%s::%d ansible_user=root",
        var.cluster_name,
        var.workers.role_id,
        var.workers.segment_start + i,
        "fd00:${var.cluster_id}",
        var.workers.segment_start + i
      )
    ]
  )

  controlplane_hosts = [
    for i in range(var.control_plane.instance_count) :
      format("%s%s%03d ansible_host=%s::%d ansible_user=root",
        var.cluster_name,
        var.control_plane.role_id,
        var.control_plane.segment_start + i,
        "fd00:${var.cluster_id}",
        var.control_plane.segment_start + i
      )
  ]

  worker_hosts = [
    for i in range(var.workers.instance_count) :
      format("%s%s%03d ansible_host=%s::%d ansible_user=root",
        var.cluster_name,
        var.workers.role_id,
        var.workers.segment_start + i,
        "fd00:${var.cluster_id}",
        var.workers.segment_start + i
      )
  ]

  # etcd membership: always first 3 control plane nodes (classic k8s)
  etcd_hosts = [
    for i in range(var.control_plane.instance_count) :
      format("%s%s%03d ansible_host=%s::%d ansible_user=root",
        var.cluster_name,
        var.control_plane.role_id,
        var.control_plane.segment_start + i,
        "fd00:${var.cluster_id}",
        var.control_plane.segment_start + i
      )
  ]

  ansible_inventory_content = join("\n", concat(
    ["[all]"],
    local.all_hosts,
    ["", "[controlplane]"],
    local.controlplane_hosts,
    ["", "[worker]"],
    local.worker_hosts,
    ["", "[etcd]"],
    local.etcd_hosts,
    ["", "[cluster:children]", "worker", "controlplane"]
  ))
}

resource "local_file" "ansible_inventory_file" {
  filename = "${path.root}/../../../../../../../ansible/k8s/inventory/hosts.ini"
  #filename = "${var.git_repo_root}/ansible/k8s/inventory/hosts"
  content  = local.ansible_inventory_content
}

output "ansible_inventory" {
  value = local.ansible_inventory_content
}


#output "routeros_dns_ipv6" {
#  value = routeros_ip_dns_record.ipv6_records
#}

#output "routeros_dns_ipv4" {
#  value = routeros_dns_static.ipv4_records
#}