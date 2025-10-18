Flux

SOPS & Bootstrap
``````

cat ~/.config/sops/age/age.agekey |
kubectl create secret generic sops-age \
--namespace=flux-system \
--from-file=age.agekey=/dev/stdin



flux bootstrap github \
--branch=main \
--personal \
--private \
--token-auth \
--owner=sulibot \
--repository=sulibot-homeops \
--path=kubernetes/clusters/production \
--interval=10m \
--timeout=5m
``````



MetallB
``````
https://artifacthub.io/packages/helm/metallb/metallb
https://metallb.universe.tf/

mkdir -p clusters/charts
mkdir -p clusters/apps/networking/metallb/
flux create source helm metallb --url https://metallb.github.io/metallb --export > clusters/charts/metallb-charts.yaml


flux create helmrelease metallb --chart metallb \
  --namespace=metallb-system \
  --create-target-namespace=true \
  --source HelmRepository/metallb.flux-system  \
  --chart-version 0.13.10 \
  --export > clusters/apps/networking/metallb/helm-release.yaml
``````


Ingress-Nginx
``````
https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx
https://kubernetes.github.io/ingress-nginx/deploy/

mkdir -p clusters/apps/networking/ingress-nginx/
flux create source helm ingress-nginx --url  https://kubernetes.github.io/ingress-nginx --export > clusters/charts/ingress-nginx-charts.yaml

flux create helmrelease ingress-nginx --chart ingress-nginx \
  --source HelmRepository/ingress-nginx.flux-system  \
  --namespace=ingress-nginx \
  --create-target-namespace=true \
  --chart-version 4.7.1 \
  --export  >  clusters/apps/network/ingress-nginx/helm-release.yaml
``````



Traefik
``````
mkdir -p clusters/core/network/traefik/
mkdir -p helm_files/traefik/

helm repo add traefik https://traefik.github.io/charts
flux create source helm traefik --url https://traefik.github.io/charts --export > clusters/charts/traefik-charts.yaml

helm show values traefik/traefik >  helm_files/traefik/values.yaml

helm install -f myvalues.yaml traefik traefik/traefik

helm install traefik traefik/traefik

flux create helmrelease traefik --chart traefik \
  --source HelmRepository/traefik.flux-system  \
  --namespace=network \
  --chart-version 24.0.0 \
  --values=helm_files/traefik/values.yaml \
  --export  >  clusters/core/network/traefik/helm-release.yaml

  --depends-on cert-manager \

restrict ny IP range

https://github.com/traefik/traefik/issues/7896
* https://www.aviator.co/blog/dependencies-for-helm-releases-in-fluxcd/
https://community.traefik.io/t/traefik-default-cert-on-domain-that-have-lets-encrypt-cert-manager-certificate-issued/14742
``````
ceph-csi-cephfs
``````
flux create source helm ceph-csi \
  --url=https://ceph.github.io/csi-charts \
  --export > ceph-csi-cephfs.yaml

flux create helmrelease ceph-csi --chart ceph-csi/ceph-csi-cephfs \
  --namespace=ceph-csi-cephfs \
  --create-target-namespace=true \
  --source=HelmRepository/ceph-csi.flux-system \
  --chart-version=3.12.3 --export



flux create source helm jetstack \
  --url=https://charts.jetstack.io \
  --export > jetstack-charts.yaml



mkdir -p clusters/apps/networking/cert-manager/
flux create source helm jetstack --url  https://charts.jetstack.io --export > clusters/charts/jetstack-charts.yaml

flux create helmrelease cert-manager --chart cert-manager \
  --namespace=cert-manager \
  --create-target-namespace=true \
  --source HelmRepository/jetstack.flux-system  \
  --chart-version v1.16.2 --export 
  
  \
  --values=helm_files/cert-manager/values.yaml \
  --export  >  clusters/core/network/cert-manager/helm-release.yaml

sops --decrypt cloudflare_token.sops.yaml | kubectl apply -f -

rotate flux SOPS key:

kubectl delete -n flux-system secrets sops-age

cat age.agekey |
kubectl create secret generic sops-age \
--namespace=flux-system \
--from-file=age.agekey=/dev/stdin


add in gotk-sync.yaml
...
  sourceRef:
    kind: GitRepository
    name: flux-system
  validation: client
  # Enable decryption
  decryption:
    # Use the sops provider
    provider: sops
    secretRef:
      # Reference the new 'sops-gpg' secret
      name: sops-age


cat /Users/suahmad/.config/sops/age/age.agekey |
kubectl create secret generic sops-age \
--namespace=flux-system \
--from-file=age.agekey=/dev/stdin 


flux bootstrap github \
--branch=main \
--personal \
--private \
--token-auth \
--owner=sulibot \
--repository=sulibot-homeops \
--path=/kubernetes/clusters/production




``````




ESO 

``````
mkdir -p clusters/core/security/external-secrets/
mkdir -p helm_files/external-secrets/

helm repo add external-secrets https://charts.external-secrets.io
flux create source helm external-secrets --url https://charts.external-secrets.io --export > clusters/charts/external-secrets-charts.yaml

helm show values external-secrets/external-secrets >  helm_files/external-secrets/values.yaml

flux create helmrelease external-secrets --chart external-secrets \
  --source HelmRepository/external-secrets.flux-system  \
  --namespace=security \
  --chart-version 0.9.4 \
  --values=helm_files/external-secrets/values.yaml \
  --export  >  clusters/core/security/external-secrets/helm-release.yaml

``````


1Password
``````
mkdir -p clusters/core/security/1password/
mkdir -p helm_files/1password/

helm repo add 1password https://1password.github.io/connect-helm-charts
flux create source helm 1password --url https://1password.github.io/connect-helm-charts --export > clusters/charts/1password-charts.yaml

helm show values 1password/connect >  helm_files/1password/values.yaml

cd ~/.op/
flux create helmrelease connect --chart 1password/connect \
  --source HelmRepository/1password.flux-system  \
  --namespace=security \
  --chart-version 1.14.0 \
  --values=/Users/suahmad/repo/github/cluster-sulibot/helm_files/1password/values.yaml \
  --export  >  /Users/suahmad/repo/github/cluster-sulibot/clusters/core/security/1password/helm-release.yaml

cd /Users/suahmad/repo/github/cluster-sulibot

https://external-secrets.io/v0.7.0/provider/1password-automation/

``````


GPU
``````
rm -r clusters/core/plugins/intel/
mkdir -p clusters/core/plugins/intel-device-plugins-operator/
mkdir -p clusters/core/plugins/intel-device-plugins-gpu/
mkdir -p helm_files/intel-device-plugins-operator/
mkdir -p helm_files/intel-device-plugins-gpu/

helm show values intel/intel-device-plugins-operator >  helm_files/intel-device-plugins-operator/values.yaml
helm show values intel/intel-device-plugins-gpu >  helm_files/intel-device-plugins-gpu/values.yaml

helm repo add intel https://intel.github.io/helm-charts/
flux create source helm intel --url https://intel.github.io/helm-charts/ --export > clusters/charts/intel-charts.yaml

flux create helmrelease intel-device-plugins-operator --chart intel-device-plugins-operator \
  --source HelmRepository/intel.flux-system  \
  --namespace=flux-system \
  --values=helm_files/intel-device-plugins-operator/values.yaml \
  --export  >  clusters/core/plugins/intel-device-plugins-operator/helm-release.yaml

  flux create helmrelease intel-device-plugins-gpu --chart intel-device-plugins-gpu \
  --source HelmRepository/intel.flux-system  \
  --namespace=flux-system \
  --values=helm_files/intel-device-plugins-gpu/values.yaml \
  --export  >  clusters/core/plugins/intel-device-plugins-gpu/helm-release.yaml


helm install device-plugin-operator intel/intel-device-plugins-operator
helm install gpu-device-plugin intel/intel-device-plugins-gpu 


https://www.derekseaman.com/2023/04/proxmox-plex-lxc-with-alder-lake-transcoding.html


ssh root@10.1.1.252 -L 8888:localhost:32400

stop container first
pct set 300 -mp0 /tank/media/library,mp=/library


https://www.reddit.com/r/selfhosted/comments/121vb07/plex_on_kubernetes_with_intel_igpu_passthrough/
https://3os.org/infrastructure/proxmox/gpu-passthrough/igpu-split-passthrough/#proxmox-configuration-for-gvt-g-split-passthrough
https://www.geekbitzone.com/posts/2022/proxmox/plex-lxc/install-plex-in-proxmox-lxc/



https://www.plex.tv/claim

``````

nfs-subdir-external-provisioner
``````
https://artifacthub.io/packages/helm/nfs-subdir-external-provisioner/nfs-subdir-external-provisioner
https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner

mkdir -p clusters/apps/storage/nfs-subdir-external-provisioner/



flux create source helm nfs-subdir-external-provisioner \
    --url=https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
    --interval=1h \
    --export > clusters/charts/nfs-subdir-external-provisioner.yaml

flux create helmrelease nfs-subdir-external-provisioner \
  --namespace=storage \
  --create-target-namespace=true \
  --source=HelmRepository/nfs-subdir-external-provisioner.flux-system \
  --interval=60m \
  --chart=nfs-subdir-external-provisioner \
  --chart-version="4.0.18" \
  --values=clusters/apps/storage/nfs-subdir-external-provisioner/values.yaml \
  --export > clusters/apps/storage/nfs-subdir-external-provisioner/helm-release.yaml

https://docs.aws.amazon.com/efs/latest/ug/mounting-fs-mount-cmd-general.html
https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/issues/134

sudo zfs set sharenfs="rw=*,sync,all_squash,anonuid=65534,anongid=65534,no_subtree_check,insecure" tank/media

echo "nfs:
  server: fs1.ent.top
  path: /sea1
  mountOptions:
    - vers=
    - nolock
    - noacl
    - proto=tcp
    - rsize=1048576
    - wsize=1048576
    - hard
    - timeo=15
    - retrans=2
    - noresvport
    - _netdev
storageClass:
  defaultClass: true" > ~/nfs.yaml

mountOptions:
  - vers=3
  - nolock
  - noacl
  - proto=tcp
  - rsize=1048576
  - wsize=1048576
  - hard
  - timeo=600
  - retrans=2
  - noresvport
  - _netdev


``````



Cilium
``````
https://blog.devgenius.io/cilium-installation-tips-17a870fdc4f2

helm template \
    cilium \
    cilium/cilium \
    --version 1.14.1 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set=kubeProxyReplacement=strict \
    --set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set=cgroup.autoMount.enabled=false \
    --set=cgroup.hostRoot=/sys/fs/cgroup \
    --set=k8sServiceHost=localhost \
    --set=k8sServicePort=7445 \
    --set tunnel=disabled \
    --set bpf.masquerade=true \
    --set endpointRoutes.enabled=true \
    --set autoDirectNodeRoutes=true \
    --set localRedirectPolicy=true \
    --set operator.rollOutPods=true \
    --set rollOutCiliumPods=true \
    --set ipv4NativeRoutingCIDR="10.244.0.0/16" \
    --set hubble.relay.enabled=true \
    --set enable-bgp-control-plane=true \
    --set hubble.ui.enabled=true  > cilium.yaml


    routing-mode: native
``````



``````

helm repo add bjw-s https://bjw-s.github.io/helm-charts
flux create source helm bjw-s --url https://bjw-s.github.io/helm-charts --export > clusters/charts/bjw-s-charts.yaml

helm repo add 1password https://1password.github.io/connect-helm-charts
flux create source helm 1password --url https://1password.github.io/connect-helm-charts --export > clusters/charts/connect-charts.yaml




```

Create Talos cluster config:
```markdown
talosctl gen config --output-dir ./configure \
    rhea https://rhea.sulibot.com:6443 \
    --config-patch '[{"op": "add", "path": "/cluster/proxy", "value": {"disabled": true}}, {"op":"add", "path": "/cluster/network/cni", "value": {"name": "custom", "urls": ["https://raw.githubusercontent.com/sulibot/home/main/cilium.yaml"]}}]'
```

Terraform wipe k8s cluster
```console
 terraform apply -replace=proxmox_vm_qemu.talos-k8s-cluster
```

Generate config base on talconfig.yaml
```console
talhelper gensecret --patch-configfile > talenv.sops.yaml
sops -e -i talenv.sops.yaml
talhelper genconfig
```

Bootstrap Talos nodes:
```markdown
export CONTROL_PLANE_IP=192.168.10.21
export WOk3sR_IP=192.168.10.24

#Controllers:
talosctl apply-config --insecure --nodes 192.168.10.21 --file ./clusterconfig/rhea-master-1.yaml
talosctl apply-config --insecure --nodes 192.168.10.22 --file ./clusterconfig/rhea-master-2.yaml
talosctl apply-config --insecure --nodes 192.168.10.23 --file ./clusterconfig/rhea-master-3.yaml

#Workers
talosctl apply-config --insecure --nodes 192.168.10.24 --file ./clusterconfig/rhea-wok3sr-1.yaml
talosctl apply-config --insecure --nodes 192.168.10.25 --file ./clusterconfig/rhea-wok3sr-2.yaml
talosctl apply-config --insecure --nodes 192.168.10.26 --file ./clusterconfig/rhea-wok3sr-3.yaml
```

Temporary talosctl config
```markdown
export CONTROL_PLANE_IP=192.168.10.21
export TALOSCONFIG="./clusterconfig/talosconfig"
talosctl config endpoint $CONTROL_PLANE_IP
talosctl config node $CONTROL_PLANE_IP

talosctl --talosconfig ./clusterconfig/talosconfig config endpoint $CONTROL_PLANE_IP
talosctl --talosconfig ./clusterconfig/talosconfig config node $CONTROL_PLANE_IP

#Bootstrap Ectd
talosctl --talosconfig ./clusterconfig/talosconfig bootstrap


#Generate kubeconfig
talosctl --talosconfig ./clusterconfig/talosconfig kubeconfig .

```

Update kubeconfig
```console
cp ~/.kube/config ~/.kube/config.bak
KUBECONFIG=~/.kube/config:`pwd`/kubeconfig kubectl config view --flatten > /tmp/config
cat  /tmp/config

mv /tmp/config ~/.kube/config 

```

kubectl delete -n flux-system secret flux-system




--reconcile               if true, the configured options are also reconciled if the repository already exists

```markdown
flux bootstrap github \
--branch=main \
--owner=${GITHUB_USER} \
  --repository=cluster-sulibot \
--path=clusters/jove \
--personal
--components-extra=image-reflector-controller,image-automation-controller \
--personal

 --private=true --export

cd clusters/rhea


mkdir -p infrastructure/metallb
mkdir -p infrastructure/kyverno  


flux create source helm k8s-at-home \
    --url=https://library-charts.k8s-at-home.com \
    --interval=60m \
    --export > cluster/charts/k8s-at-home.yaml

mkdir -p cluster/apps/media-servers/plex
# wget -O - https://raw.githubusercontent.com/k8s-at-home/charts/master/charts/stable/plex/values.yaml > cluster/apps/media-servers/plex/values.yaml  

flux create helmrelease plex \
  --namespace=media-servers \
  --create-target-namespace=true \
  --source=HelmRepository/k8s-at-home \
  --interval=60m \
  --chart=plex \
  --chart-version=">6.0.0" \
  --values=cluster/apps/media-servers/plex/values.yaml \
  --export > cluster/apps/media-servers/plex/helm-release.yaml



flux create helmrelease plex \
  --namespace=media-servers \
  --create-target-namespace=true \
  --source=HelmRepository/k8s-at-home \
  --interval=60m \
  --chart=plex \
  --chart-version=">6.0.0" \
  --values=cluster/apps/media-servers/plex/values.yaml \
  --export > cluster/apps/media-servers/plex/helm-release.yaml

### nfs-subdir-external-provisioner

---
nfs:
  path: /tank/pvcs
  server: nas01.sulibot.com
storageClass:
  defaultClass: false
  name: nfs-client


flux create source helm nfs-subdir-external-provisioner \
    --url https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
    --export | tee nfs-subdir-external-provisioner-charts.yaml


flux create helmrelease \
    chart-name \
    --source HelmRepository/repo-name-charts \
    --values values.yaml \
    --chart chart-name \
    --chart-version chart-version \
    --target-namespace namespace-name \
    --export \
    | tee helm-release.yaml





mkdir -p cluster/apps/storage/nfs-subdir-external-provisioner/
# wget -O - https://raw.githubusercontent.com/kubernetes-sigs/nfs-subdir-external-provisioner/master/charts/nfs-subdir-external-provisioner/values.yaml > cluster/apps/storage/nfs-subdir-external-provisioner/values.yaml 

flux create source helm nfs-subdir-external-provisioner \
    --url=https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
    --interval=1h \
    --export > cluster/charts/nfs-subdir-external-provisioner.yaml

flux create helmrelease nfs-subdir-external-provisioner \
  --namespace=storage \
  --create-target-namespace=true \
  --source=HelmRepository/nfs-subdir-external-provisioner \
  --interval=60m \
  --chart=nfs-subdir-external-provisioner \
  --chart-version="4.0.17" \
  --values=cluster/apps/storage/nfs-subdir-external-provisioner/values.yaml \
  --export > cluster/apps/storage/nfs-subdir-external-provisioner/helm-release-template.yaml

### 

flux create source helm nfs-subdir-external-provisioner \
    --url=https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
    --interval=1h \
    --export > cluster/charts/nfs-subdir-external-provisioner.yaml

flux create helmrelease nfs-subdir-external-provisioner \
  --namespace=storage \
  --create-target-namespace=true \
  --source=HelmRepository/nfs-subdir-external-provisioner \
  --interval=60m \
  --chart=nfs-subdir-external-provisioner \
  --chart-version=">4.0.0" \
  --values=cluster/apps/storage/nfs-subdir-external-provisioner/values.yaml \
  --export > cluster/apps/storage/nfs-subdir-external-provisioner/helm-release.yaml

---------------------


flux create helmrelease plex \
  --namespace=media-servers \
  --create-target-namespace=true \
  --source=HelmRepository/plex \
  --export



flux create kustomization plex \
    --source=kyverno \
    --path="./definitions/release" \
    --prune=true \
    --interval=10m \
    --export > apps/media-servers/plex/release-plex.yaml


flux create kustomization infrastructure \
    --source=plex \
    --path="./infrastructure" \
    --prune=true \
    --interval=10m \
    --export > infrastructure.yaml

flux create source git kyverno \
    --url=https://github.com/kyverno/kyverno \
    --tag-semver=">1.0.0" \
    --interval=10m \
    --export > infrastructure/kyverno/source.yaml

flux create kustomization kyverno \
    --source=kyverno \
    --path="./definitions/release" \
    --prune=true \
    --interval=10m \
    --export > infrastructure/kyverno/release.yaml

flux create kustomization apps \
    --depends-on=infrastructure \
    --source=flux-system \
    --path="./apps" \
    --prune=true \
    --interval=10m \
    --export > infrastructure/apps.yaml

mkdir -p apps/podinfo

flux  reconcile kustomization flux-system --with-source 
```
```markdown
ssh root@192.168.10.11 'sed -i s/#DNS=/DNS=192.168.10.1/ /etc/systemd/resolved.conf && reboot'
ssh root@192.168.10.12 'sed -i s/#DNS=/DNS=192.168.10.1/ /etc/systemd/resolved.conf && reboot'
ssh root@192.168.10.13 'sed -i s/#DNS=/DNS=192.168.10.1/ /etc/systemd/resolved.conf && reboot'
ssh root@192.168.10.14 'sed -i s/#DNS=/DNS=192.168.10.1/ /etc/systemd/resolved.conf && reboot'

ssh root@192.168.10.11 ' reboot'
ssh root@192.168.10.12 ' reboot'
ssh root@192.168.10.13 ' reboot'
ssh root@192.168.10.14 ' reboot'

task sops:encrypt -- tmpl/terraform/secret.sops.yaml
task sops:encrypt -- tmpl/cluster/cert-manager-secret.sops.yaml
task sops:encrypt -- tmpl/cluster/external-dns-secret.sops.yaml
task sops:encrypt -- tmpl/cluster/cluster-secrets.sops.yaml
task sops:encrypt -- tmpl/cluster/cloudflare-ddns-secret.sops.yaml
task sops:encrypt -- tmpl/cluster/flux-system/webhooks/github/secret.sops.yaml
task sops:encrypt -- cluster/apps/kube-system/kube-vip/rbac.yaml

task sops:decrypt -- tmpl/terraform/secret.sops.yaml
task sops:decrypt -- tmpl/cluster/cert-manager-secret.sops.yaml
task sops:decrypt -- tmpl/cluster/external-dns-secret.sops.yaml
task sops:decrypt -- tmpl/cluster/cluster-secrets.sops.yaml
task sops:decrypt -- tmpl/cluster/cloudflare-ddns-secret.sops.yaml
task sops:decrypt -- tmpl/cluster/flux-system/webhooks/github/secret.sops.yaml
task sops:decrypt -- cluster/apps/kube-system/kube-vip/rbac.yaml

zfs destroy  rpool/data/vm-1011-cloudinit
zfs destroy  rpool/data/vm-1012-cloudinit
zfs destroy  rpool/data/vm-1013-cloudinit
zfs destroy  rpool/data/vm-1014-cloudinit
```

    
```



https://medium.com/@LachlanEvenson/hands-on-with-kubernetes-pod-security-admission-b6cac495cd11


pveum user add root@pam!fire
pveum aclmod / -user root@pam!fire -role terraform-role
pveum user token add root@pam!fire terraform-token --privsep=0pveum role add terraform-role -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"


pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"


pveum user add root@pam
pveum aclmod / -user root@pam!fire -role terraform-role
pveum user token add root@pam!fire terraform-token --privsep=0


wget -nc -q --show-progress -O "/var/lib/vz/template/iso/archlinux-2024.01.01-x86_64.iso" "https://archlinux.uk.mirror.allworldit.com/archlinux/iso/2024.01.01/archlinux-x86_64.iso"


pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role terraform-role
pveum user token add terraform@pve terraform-token --privsep=0

┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ terraform@pve!terraform-token        │
├──────────────┼──────────────────────────────────────┤
│ info         │ {"privsep":"0"}                      │
├──────────────┼──────────────────────────────────────┤
│ value        │ b3d5cb0b-70ab-48c8-9b54-2b89dc89219f │
└──────────────┴──────────────────────────────────────┘ 
