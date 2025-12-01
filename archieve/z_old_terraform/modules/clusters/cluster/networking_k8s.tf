locals {
  # ===================================================================
  # Kubernetes Network CIDRs
  # ===================================================================
  # This map defines the IP ranges for Pods, Services, and LoadBalancers
  # for each Kubernetes cluster, supporting dual-stack operations.
  # ===================================================================
  k8s_cidrs = {
    "101" = {
      pods_ipv4          = "10.101.0.0/16"
      pods_ipv6          = "fd00:101:1::/60"
      services_ipv4      = "10.101.96.0/20"
      services_ipv6      = "fd00:101:96::/108"
      loadbalancers_ipv4 = "10.101.27.0/24"
      loadbalancers_ipv6 = "fd00:101:1b::/120"
    },
    "102" = {
      pods_ipv4          = "10.102.0.0/16"
      pods_ipv6          = "fd00:102:1::/60"
      services_ipv4      = "10.102.96.0/20"
      services_ipv6      = "fd00:102:96::/108"
      loadbalancers_ipv4 = "10.102.27.0/24"
      loadbalancers_ipv6 = "fd00:102:1b::/120"
    },
    "103" = {
      pods_ipv4          = "10.103.0.0/16"
      pods_ipv6          = "fd00:103:1::/60"
      services_ipv4      = "10.103.96.0/20"
      services_ipv6      = "fd00:103:96::/108"
      loadbalancers_ipv4 = "10.103.27.0/24"
      loadbalancers_ipv6 = "fd00:103:1b::/120"
    }
  }

  # --- Current Cluster Network Config ---
  # Selects the appropriate network configuration based on the var.cluster_id
  # provided to the module. This makes the rest of the code cleaner.
  k8s_network_config = lookup(local.k8s_cidrs, tostring(var.cluster_id), {})

  # Individual CIDRs for the current cluster
  k8s_pod_cidrs          = [local.k8s_network_config.pods_ipv6, local.k8s_network_config.pods_ipv4]
  k8s_service_cidrs      = [local.k8s_network_config.services_ipv6, local.k8s_network_config.services_ipv4]
  k8s_loadbalancer_cidrs = [local.k8s_network_config.loadbalancers_ipv6, local.k8s_network_config.loadbalancers_ipv4]
}