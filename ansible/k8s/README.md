# sol-k8s IPv6-only Kubernetes Cluster Bootstrap

## Prerequisites

- Ansible and the `task` runner installed on your control machine
- Your Age key configured for SOPS encryption (see `.sops.yaml`)

## Workflow to Create a New Cluster

1. **Render cluster configuration**  
   Generate per-cluster variables from the template:
   ```bash
   task render
   # -> rendered/<cluster_name>-group_vars.yaml
   ```

2. **Generate join credentials**  
   Create and encrypt the kubeadm bootstrap token and CA hash:
   ```bash
   ansible-playbook -i inventory/hosts.ini playbooks/generate-join-creds.yaml
   # -> secrets/sensitive.enc.yaml
   ```

3. **Bootstrap all hosts**  
   Prepare each node with kernel tweaks and install required tooling:
   ```bash
   task bootstrap
   ```

4. **Initialize first control plane**  
   Run kubeadm and deploy kube-vip:
   ```bash
   task init
   # or explicitly:
   ansible-playbook -i inventory/hosts.ini playbooks/init-controlplane.yaml
   ```

5. **Join remaining nodes**  
   Add control plane replicas and worker nodes:
   ```bash
   task join
   # or explicitly:
   ansible-playbook -i inventory/hosts.ini playbooks/join-nodes.yaml
   ```

6. **Install Cilium CNI**  
   Deploy IPv6-only Cilium via Helm:
   ```bash
   task cilium
   ```

7. **Validate cluster**  
   Run network and service checks:
   ```bash
   task validate
   ```

8. **Bootstrap Flux GitOps**  
   Install Flux and link to your Git repository:
   ```bash
   task flux
   ```

---
Happy clustering! 🎉
