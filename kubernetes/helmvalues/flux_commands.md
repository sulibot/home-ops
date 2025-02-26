helm repo add cnpg https://cloudnative-pg.github.io/charts
helm show values cnpg/cloudnative-pg > values.yaml

flux create source helm cnpg \
  --url=https://cloudnative-pg.github.io/charts \
  --interval=1h \
  --export > cnpg-helmrepository.yaml


helm upgrade --install cnpg \
  --namespace cnpg-system \
  --create-namespace \
  cnpg/cloudnative-pg

flux create helmrelease cloudnative-pg \
  --source=HelmRepository/cnpg.flux-system \
  --namespace=flux-system \
  --create-target-namespace=true \
  --target-namespace cnpg-system \
  --chart=cloudnative-pg \
  --chart-version=0.23.0 \
  --interval=1h \
  --values=values.yaml \
  --export > helmrelease.yaml

flux create helmrelease cnpg-cluster \
  --source=HelmRepository/cnpg.flux-system \
  --namespace=flux-system \
  --create-target-namespace=true \
  --target-namespace cnpg-system \
  --chart=cluster \
  --chart-version=0.2.1 \
  --interval=1h \
  --values=values.yaml \
  --export > helmrelease.yaml

#############################################

flux create source helm ndf \
  --url=https://kubernetes-sigs.github.io/node-feature-discovery/charts \
  --interval=1h \
  --export > ndf-helmrepository.yaml

flux create helmrelease node-feature-discovery \
  --source=HelmRepository/ndf.flux-system \
  --chart=node-feature-discovery \
  --chart-version=0.17.1 \
  --namespace=flux-system \
  --namespace=gpu-resources \
  --create-target-namespace=true \
  --interval=1h \
  --export > helmrelease.yaml

  --values=values.yaml \

flux create helmrelease device-plugin-operator \
  --source=HelmRepository/intel.flux-system \
  --chart=intel-device-plugins-operator \
  --chart-version=0.32.0 \
  --namespace=gpu-resources \
  --create-target-namespace=true \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml




helm repo add backube https://backube.github.io/helm-charts/
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
backube/snapscheduler   3.4.0           3.4.0           An operator to take scheduled snapshots of Kube...
backube/volsync         0.11.0          0.11.0          Asynchronous data replication for Kubernetes

```
flux create source helm backube \
  --url=https://backube.github.io/helm-charts \
  --interval=1h \
  --export > backube-helmrepository.yaml
    
```
flux create helmrelease snapscheduler \
  --source=HelmRepository/backube.flux-system \
  --chart=snapscheduler \
  --chart-version=3.4.0 \
  --namespace=flux-system \
  --target-namespace=volsync-system \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml

  flux create helmrelease volsync \
  --source=HelmRepository/backube.flux-system \
  --chart=volsync \
  --chart-version=0.11.0 \
  --namespace=flux-system \
  --target-namespace=volsync-system \
  --create-target-namespace=true \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml




helm repo add 1password https://1password.github.io/connect-helm-charts

```
flux create source helm 1password \
  --url=https://1password.github.io/connect-helm-charts \
  --interval=1h \
  --export > 1password-helmrepository.yaml
    
```
flux create helmrelease 1password-connect \
  --source=HelmRepository/1password.flux-system \
  --chart=connect \
  --chart-version=1.16.6 \
  --namespace=external-secrets \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml


flux create helmrelease 1password-connect \
  --source=HelmRepository/1password.flux-system \
  --chart=connect \
  --chart-version=1.16.6 \
  --namespace=flux-system \
  --target-namespace=external-secrets \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml


kubectl create secret generic op-credentials \
  -n external-secrets \
  --from-literal=1password-credentials.json="$(cat /Users/sulibot/1password-credentials.json | base64)" \
  --dry-run=client \
  -o yaml > op-credentials-secret.yaml







```
flux create source helm akeyless \
  --url=https://akeylesslabs.github.io/helm-charts \
  --interval=1h \
  --export > akeyless-helmrepository.yaml
    
```
flux create helmrelease akeyless \
  --source=HelmRepository/akeyless.flux-system \
  --chart=akeyless-secrets-injection \
  --chart-version=1.12.1 \
  --namespace=external-secrets \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml


```


```
flux create source helm cnpg \
  --url=https://cloudnative-pg.github.io/charts \
  --interval=1h \
  --export > cnpg-helmrepository.yaml
    
```
flux create helmrelease cnpg \
  --source=HelmRepository/cnpg.flux-system \
  --chart=cloudnative-pg \
  --chart-version=0.23.0 \
  --namespace=datastore \
  --values=values-0.23.0.yaml \
  --interval=1h \
  --export > helmrelease.yaml


```
flux create source helm bitnami \
    --url https://charts.bitnami.com/bitnami \
    --interval 1h \
    --namespace flux-system \

flux create source helm bitnami-charts \
  --url=https://charts.bitnami.com/bitnami \
  --namespace=flux-system \
  --interval=1h \
  --export > bitnami-source.yaml


```
flux create helmrelease redis \
  --source=HelmRepository/bitnami-charts.flux-system \
  --namespace=flux-system \
  --create-target-namespace=true \
  --target-namespace redis \
  --chart=redis \
  --chart-version=20.9.0 \
  --values=values.yaml \
  --interval=1h \
  --export > helmrelease.yaml






```
flux create source helm external-secrets \
  --url=https://charts.external-secrets.io \
  --interval=1h \
  --export > external-secrets-source.yaml
```
flux create helmrelease external-secrets \
  --source HelmRepository/external-secrets.flux-system \
  --chart external-secrets \
  --namespace=external-secrets \
  --values=values.yaml \
  --chart-version 0.12.1 \
  --interval 1h \
  --export > helmrelease.yaml








```
flux create source helm immich \
  --url=https://immich-app.github.io/immich-charts \
  --interval=1h \
  --export > immich-source.yaml
```
flux create helmrelease immich \
  --source HelmRepository/immich.flux-system \
  --chart immich \
  --namespace=media \
  --values=values.yaml \
  --chart-version 0.8.5 \
  --interval 1h \
  --export > helmrelease.yaml


  --values=<(sops -d values.yaml) \
sops -e -i helmrelease.yaml

```
flux create source helm external-dns \
  --url=https://kubernetes-sigs.github.io/external-dns/ \
  --interval=1h \
  --export > external-dns-source.yaml
```
flux create helmrelease external-dns \
  --source HelmRepository/external-dns.flux-system \
  --chart external-dns \
  --namespace=external-dns \
  --values=values.yaml \
  --chart-version 1.15.0 \
  --interval 1h \
  --export > helmrelease.yaml

```
flux create source helm cloudflare \
  --url=https://cloudflare.github.io/helm-charts \
  --interval=1h \
  --export > cloudflare-source.yaml
```
flux create helmrelease cloudflare \
  --source HelmRepository/cloudflare.flux-system \
  --chart cloudflare-tunnel \
  --values=<(sops -d values.yaml) \
  --chart-version 0.3.2 \
  --interval 1h \
  --export > helmrelease.yaml

sops -e -i helmrelease.yaml

```
flux create source helm chart-template \
  --url=https://sulibot.github.io/chart-template/ \
  --interval=1h \
  --export > sulibot-chart-template.yaml
```

flux create helmrelease prowlarr \
  --source HelmRepository/chart-template \
  --chart chart-template \
  --values values-prowlarr.yaml \
  --chart-version 0.1.0 \
  --interval 1h \
  --export > ../manifests/apps/media/prowlarr/helmrelease.yaml
```
$ helm repo add cilium https://helm.cilium.io/
helm repo update
helm search repo cilium
```


```
flux create source helm cilium \
--interval=24h \
--url=https://helm.cilium.io \
--export > ../shared/repo/helm/cilium-source.yaml
```

```
****** 
flux create helmrelease cilium \
  --source=HelmRepository/cilium.flux-system \
  --chart=cilium \
  --chart-version=1.16.6 \
  --namespace=kube-system \
  --target-namespace kube-system \
  --values=./values.yaml \
  --export > helmrelease.yaml 

kubectl logs -n flux-system -l app=helm-controller
```
------


```
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update
helm search repo ceph-csi
```

```
flux create source helm ceph-csi \
  --interval=24h \
  --url=https://ceph.github.io/csi-charts \
  --export > ../shared/repo/helm/ceph-csi-cephfs.yaml

```

```
flux create helmrelease ceph-csi \
  --chart=ceph-csi-cephfs \
  --chart-version=3.13.0 \
  --namespace=ceph-csi-cephfs \
  --source=HelmRepository/ceph-csi.flux-system \
  --values=<(sops -d values.yaml) \
  --export > helmrelease.yaml
  
sops -e -i helmrelease.yaml


kubectl logs -n flux-system -l app=helm-controller
```


------

```
https://cert-manager.io/docs/installation/continuous-deployment-and-gitops/#create-a-helmrelease-resource

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm search repo jetstack


kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml


```
flux create source helm cert-manager \
  --interval=24h \
  --url https://charts.jetstack.io \
  --export > ../shared/repo/helm/jetstack-source.yaml
```
***

```
flux create helmrelease cert-manager \
  --chart cert-manager \
  --source HelmRepository/cert-manager.flux-system \
  --release-name cert-manager \
  --target-namespace cert-manager \
  --create-target-namespace=true \
  --values values-cert-manager.yaml \
  --chart-version v1.16.2 \
  --export > ../manifests/core/network/cert-manager/helmrelease.yaml
```


***

helm repo add portefaix-hub https://charts.portefaix.xyz/
helm repo update
helm search repo portefaix-hub/gateway-api-crds --versions


kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml


```
flux create source helm gateway-api-crds \
  --url=https://charts.portefaix.xyz \
  --interval=24h \
  --export > ../shared/repo/helm/gateway-api-crds-source.yaml
```
***

```
flux create helmrelease gateway-api-crds \
  --chart gateway-api-crds \
  --source HelmRepository/gateway-api-crds.flux-system \
  --release-name cert-manager \
  --target-namespace kube-system \
  --chart-version 1.2.0 \
  --export > ../manifests/platform/misc/gateway-api-crds/helmrelease.yaml
```



flux create helmrelease sabnzbd \
  --source HelmRepository/chart-template.flux-system \
  --chart chart-template \
  --values=values.yaml \
  --chart-version 0.1.0 \
  --interval 1h \
  --export > helmrelease.yaml


  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch