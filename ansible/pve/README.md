# Proxmox + Ceph Cluster Automation

This Ansible project will stand up a 3-node Proxmox VE + Ceph cluster **from scratch**, with:

- **Corosync** cluster for Proxmox HA
- **Ceph** with your custom CRUSH map, MONs, MGRs, and OSDs
- **CephFS** (metadata + data pools) with MDS daemons
- **CSI-compatible** pools, filesystems, client user/key
- **Static subvolumes** for your Kubernetes PVs
- **Proxmox storage** entries (RBD & CephFS)
- **Ceph MGR modules** (Dashboard & Prometheus)
- **Basic Ceph tuning** (full/nearfull thresholds, OSD threads)

---

## 📁 Directory layout

\`\`\`
ansible/
├── ansible.cfg
├── inventory/
│   └── hosts.ini
├── group_vars/
│   └── pve.yml
├── host_vars/
│   ├── pve01.yml
│   ├── pve02.yml
│   └── pve03.yml
├── files/
│   └── crushmap.txt
├── templates/
│   ├── corosync.conf.j2
│   └── ceph.conf.j2
├── playbooks/
│   ├── site.yml
│   └── tasks/
│       └── main.yml
├── roles/
│   └── requirements.yml
├── collections/
│   └── requirements.yml
└── README.md
\`\`\`

---

## 🔧 Prerequisites

1. **Ansible 2.9+** with Python 3  
2. SSH access to \`root@pve0[1-3]\`  
3. Ansible Vault secret \`vault_proxmox_password\` for the Proxmox root password  
4. A local copy of your **CRUSH map** in \`files/crushmap.txt\`  
5. Environment variable \`CEPH_FSID\` set to your cluster FSID  

---

## 🚀 Deployment

```bash
cd ansible

# 1. Install roles & collections
ansible-galaxy install -r roles/requirements.yml -p roles
ansible-galaxy collection install -r collections/requirements.yml

# 2. Run the playbook
ansible-playbook playbooks/site.yml \
  -e vault_proxmox_password="<YOUR_PROXMOX_ROOT_PW>"
```
