locals {
  # ===================================================================
  # Kubernetes Network CIDRs
  # ===================================================================
  # This map defines the IP ranges for Pods, Services, and LoadBalancers
  # for each Kubernetes cluster, supporting dual-stack operations.
  # ===================================================================
  k8s_cidrs = {
    "101" = {
      pods_ipv4          = "10.101.244.0/22"
      pods_ipv6          = "fd00:101:244::/60"
      services_ipv4      = "10.101.96.0/24"
      services_ipv6      = "fd00:101:96::/108"
      loadbalancers_ipv4 = "10.101.240.0/24"
      loadbalancers_ipv6 = "fd00:101:fffe::/112"
    },
    "102" = {
      pods_ipv4          = "10.102.244.0/22"
      pods_ipv6          = "fd00:102:244::/60"
      services_ipv4      = "10.102.96.0/24"
      services_ipv6      = "fd00:102:96::/108"
      loadbalancers_ipv4 = "10.102.240.0/24"
      loadbalancers_ipv6 = "fd00:102:fffe::/112"
    },
    "103" = {
      pods_ipv4          = "10.103.244.0/22"
      pods_ipv6          = "fd00:103:244::/60"
      services_ipv4      = "10.103.96.0/24"
      services_ipv6      = "fd00:103:96::/108"
      loadbalancers_ipv4 = "10.103.240.0/24"
      loadbalancers_ipv6 = "fd00:103:fffe::/112"
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