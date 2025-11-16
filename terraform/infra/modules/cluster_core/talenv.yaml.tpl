# Talos Environment Configuration for ${cluster_name}
# Generated from Terraform infrastructure configuration

clusterName: "${cluster_name}"
endpoint: "${endpoint}"

# Kubernetes Network CIDRs
pods_ipv4: "${pods_ipv4}"
pods_ipv6: "${pods_ipv6}"
services_ipv4: "${services_ipv4}"
services_ipv6: "${services_ipv6}"
loadbalancers_ipv4: "${loadbalancers_ipv4}"
loadbalancers_ipv6: "${loadbalancers_ipv6}"

# Cluster Nodes
nodes:
%{~ for node in nodes }
  - hostname: ${node.hostname}
    ipAddress: ${node.ipAddress}
    controlPlane: ${node.controlPlane}
    installDisk: ${node.installDisk}

%{~ endfor ~}
