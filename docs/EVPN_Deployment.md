Deployment Document: Proxmox SDN with FRR EVPN
1. Introduction
This document outlines the deployment process for establishing a Software-Defined Network (SDN) environment within a Proxmox VE cluster, leveraging Free Range Routing (FRR) for EVPN (Ethernet VPN)functionality. The solution integrates Terraform/Terragrunt for Proxmox SDN configuration and Ansible for FRR configuration on Proxmox hosts. This setup enables advanced networking features such as VXLAN-backed VNets, VRF (Virtual Routing and Forwarding) segmentation, and efficient routing of tenant workloads (e.g.,Kubernetes/Talos clusters) with IPv4 and IPv6 support, including Global Unicast Addresses (GUA) from delegated prefixes.

2. Architecture Overview
The architecture consists of the following key components:

Proxmox VE Cluster: The hypervisor platform hosting virtual machines (VMs) and providing the underlying network infrastructure.
FRR (Free Range Routing): Running on each Proxmox VE host, FRR acts as the routing control plane. It uses IS-IS for underlay reachability within the Proxmox cluster and BGP (Border Gateway Protocol) for both iBGP peering between PVE hosts (for EVPN) and eBGP peering with an external RouterOS edge router.
Proxmox SDN:The built-in Proxmox SDN features are utilized for L2/VXLAN/VRF device plumbing. This includes the creation of EVPN zones, virtual networks (VNets), and associated IPv4 and IPv6 subnets (ULA and GUA).
RouterOS Edge Router: An external router responsible for providing external network connectivity,including BGP peering for route exchange with the Proxmox cluster. It imports and exports tenant routes to/from the Proxmox environment.
Terraform/Terragrunt: Used for declarative management of the Proxmox SDN configuration. Terragrunt orchestrates the application of a Terraform module that defines the EVPN zones, VNets, and subnets within Proxmox.
Ansible: Used for imperative configuration management of the FRR daemon on each Proxmox VE host. It ensures consistent deployment of FRR's BGP and IS-IS configurations, including EVPN address families and VRF routing policies.
Key Design Principles:

Separation of Concerns: Proxmox SDN handles L2/VXLAN/VRF device plumbing. FRR handles all routing and control-plane logic (IS-IS, BGP, EVPN, VRFs, policy).
Tenant Isolation: Tenant workloads are isolated using VRFs and VNets.
Scalable BGP Peering: Tenant workloads (e.g., Talos nodes) peer dynamically with FRR within the VRF using bgp listen range.
IPv4 and IPv6 Dual-Stack: Full support for both IPv4 and IPv6 addressing for tenants, including ULA (stable internal IPv6) and GUA (internet-routable IPv6) prefixes.
Configuration Integrity: Ansible includes checks to prevent external modifications to the FRR configuration.
3. Deployment Steps
The deployment process is sequential and involves two primary phases:

3.1. Prerequisites
Before proceeding, ensure the following are in place:

Proxmox VE Cluster: A functional Proxmox VE cluster with appropriate networking configured for inter-node communication.
Ansible Control Host: A machine with Ansible installed, configured for SSH access to all Proxmox VE nodes (target group pve in Ansible inventory).
Terraform & Terragrunt: Terraform and Terragrunt installed on the machine from which the deployment will be executed.
SOPS: sops (Secrets Operations) installed for decrypting secrets, particularly Proxmox API credentials.
RouterOS Configuration: The external RouterOS device should be pre-configured to participate in BGP peering with the Proxmox cluster, expecting specific Autonomous System Numbers (ASNs) and IP addresses.
Network Planning: Defined IPv4 and IPv6 subnet allocations for infrastructure (underlay, loopbacks) and tenant VNets (ULA, GUA, IPv4).
3.2. Phase 1: Configure FRR on Proxmox Hosts (Ansible)
This phase configures the FRR routing daemon on each Proxmox VE host. This is a critical prerequisite for the Proxmox SDN EVPN functionality.

Actions Performed by Ansible (ansible/lae.proxmox/roles/frr):

Ownership Policy Enforcement:
Verifies and enforces that the Proxmox SDN's frr@sdn.service is masked and not running. If detected, it stops and masks the service, ensuring FRR is managed exclusively by Ansible.
Configuration Integrity Check:
Calculates a SHA256 hash of /etc/frr/frr.conf and compares it against a previously stored hash. If there's a mismatch, it indicates an external modification, but the playbook proceeds to re-deploy the Ansible-managed configuration.
System Configuration:
Enables net.ipv4.tcp_l3mdev_accept=1 for VRF TCP acceptance, crucial for BGP peering in VRFs.
Disables ICMP redirects (net.ipv4.conf.*.accept_redirects=0, net.ipv4.conf.*.send_redirects=0, net.ipv6.conf.*.accept_redirects=0) to prevent routing cache pollution.
FRR Daemon Configuration:
Deploys the /etc/frr/daemons file (from ansible/lae.proxmox/roles/frr/templates/daemons-pve.j2), enabling bgpd, isisd, and bfdd.
Main FRR Configuration:
Deploys the /etc/frr/frr.conf file (from ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2), which includes:
IS-IS Underlay: Configures IS-IS for the PVE infrastructure network to establish reachability between PVE loopbacks.
Global BGP:
Establishes iBGP peering between PVE hosts using IPv6 loopbacks (acting as EVPN control plane).
Establishes eBGP peering with the external RouterOS device (IPv4 and IPv6).
Applies route-maps to filter routes advertised to RouterOS, ensuring only tenant routes are exported.
Enables l2vpn evpn address family for iBGP neighbors and advertises all VNIs.
VRF BGP (vrf_evpnz1):
Configures a dedicated BGP instance within the vrf_evpnz1 VRF for tenant workloads.
Uses bgp listen range for IPv4 and IPv6 tenant subnets (ULA, GUA), allowing dynamic peering with VMs/Talos nodes.
Applies route-maps to import/export specific tenant routes (e.g., Talos Pod CIDRs) within the VRF.
VRF Static Routes: Configures static routes within the vrf_evpnz1 VRF to leak default routes or management network routes to the global routing table via nexthop-vrf default.
Service Management:
Restarts and enables the frr systemd service.
Execution Command:

From the project root directory, execute:

cd $(git rev-parse --show-toplevel)/ansible/lae.proxmox && \
ansible-playbook -i inventory/hosts.ini playbooks/stage2-configure-frr.yml
3.3. Phase 2: Configure Proxmox SDN (Terraform/Terragrunt)
This phase applies the SDN configuration within Proxmox, leveraging the FRR setup from Phase 1.

Actions Performed by Terraform/Terragrunt (terraform/infra/live/common/0-sdn-setup):

Reads Centralized Configuration:
Utilizes terragrunt.hcl to import various shared configurations (e.g., proxmox-infrastructure.hcl, network-infrastructure.hcl, sdn-vnets.hcl, ipv6-prefixes.hcl, credentials.hcl).
Generates Providers:
Dynamically creates a providers.tf file to configure the sops and proxmox Terraform providers. Proxmox credentials are securely retrieved from a sops encrypted file.
Configures Proxmox SDN Module:
Uses the proxmox_sdn Terraform module (terraform/infra/modules/proxmox_sdn) to define:
EVPN Zone: Creates the EVPN zone, specifying FRR as the controller, vrf_vxlan ID, MTU, Proxmox nodes, exit nodes, and the rt_import value for RouterOS route leaking.
VNets: Creates virtual networks (VNets) based on defined VNET_IDS.
Subnets: Creates associated IPv4, ULA IPv6, and GUA IPv6 subnets for each VNet.
Applies Configuration:
The proxmox_virtual_environment_sdn_applier resource triggers the application of the defined SDN configuration within the Proxmox environment.
Post-Deployment Reminder:
A null_resource in the Terraform module provides a console output message after successful SDN configuration, reminding the operator to ensure FRR configuration (Phase 1) is current and active, which is crucial for the SDN to function correctly. This is an explicit signal for the ordering of operations.
Execution Command:

From the terraform/infra/live/common/0-sdn-setup directory, execute:

terragrunt apply
4. Key Configuration Files
terraform/infra/live/common/0-sdn-setup/terragrunt.hcl: The entry point for Terragrunt, defining module source and inputs for Proxmox SDN.
terraform/infra/modules/proxmox_sdn/main.tf: The core Terraform module defining Proxmox EVPN zone, VNets, and subnets.
ansible/lae.proxmox/playbooks/stage2-configure-frr.yml: The Ansible playbook initiating FRR configuration on PVE hosts.
ansible/lae.proxmox/roles/frr/tasks/main.yaml: The Ansible tasks for the FRR role, including pre-flight checks, system tuning, and template deployment.
ansible/lae.proxmox/roles/frr/templates/daemons-pve.j2: Jinja2 template for /etc/frr/daemons, enabling bgpd, isisd, bfdd.
ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2: Jinja2 template for /etc/frr/frr.conf, containing detailed IS-IS, BGP (iBGP, eBGP, EVPN), VRF, and route-map configurations.
5. Troubleshooting / Important Notes
Execution Order is Crucial: Always execute the Ansible FRR configuration (Phase 1) before applying the Proxmox SDN configuration with Terragrunt (Phase 2). FRR must be properly configured and running for Proxmox SDN EVPN to function.
frr@sdn.service Masking: The Ansible playbook rigorously ensures that the Proxmox SDN's own FRR service (frr@sdn.service) is masked. This is paramount to prevent conflicts and ensure that Ansible maintains exclusive control over FRR configuration.
FRR Configuration Integrity: If you encounter issues where FRR is not behaving as expected, check the Ansible logs for warnings about external modifications to /etc/frr/frr.conf. Re-running the Ansible playbook should restore the desired state.
BGP Peering with RouterOS: Verify BGP sessions between FRR on PVE nodes and the RouterOS edge are established and exchanging routes correctly. Use vtysh on PVE hosts to check BGP neighbor status.
VRF Configuration: Ensure tenant VMs are correctly attached to the SDN VNets and that their routing within the vrf_evpnz1 VRF is functioning.
IPv6 Delegated Prefixes: The system relies on dynamically assigned IPv6 GUA prefixes. Verify that the ipv6-prefixes.hcl Terragrunt include correctly provides these to the Proxmox SDN module.
This deployment document provides a comprehensive overview of the components, steps, and critical considerations for setting up the Proxmox SDN with FRR EVPN.I have created the deployment document. Let me know if you need any further modifications or have more questions.