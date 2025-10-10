# live/clusters/cluster_defaults.hcl
locals {
  inputs = {
    template_vmid           = 9000
    datastore_id            = "local-zfs"
    snippet_datastore_id    = "resources"
    cloudinit_template_file = "${get_repo_root()}/terraform/modules/clusters/cluster/instance_group/templates/cloudinit.yaml.tmpl"
    frr_template_file       = "${get_repo_root()}/terraform/modules/clusters/cluster/instance_group/templates/frr-vm.conf.tmpl"
  }
}
