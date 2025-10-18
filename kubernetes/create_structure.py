#!/usr/bin/env python3

import os
import textwrap

# Define the directory structure starting from the current directory
structure = {
    'manifests': {
        'apps': {
            'kustomization.yaml': textwrap.dedent('''\
                resources:
                  - plex/
                  - prowlarr/
                  - sonarr/
                  - radarr/
                  - readarr/
                  - overseerr/
                  - lidarr/
                  - sabnzbd/
                # Add other apps here
            '''),
            # Define each app with its configurations
            'plex': {
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: plex
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Plex Helm chart values
                    claimToken: "YOUR_PLEX_CLAIM_TOKEN"
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                      data:
                        enabled: true
                        size: 100Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: plex
                      namespace: plex
                    spec:
                      releaseName: plex
                      chart:
                        spec:
                          chart: plex
                          version: 5.0.0
                          sourceRef:
                            kind: HelmRepository
                            name: plex-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: plex-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: plex-values
                        files:
                          - values.yaml
                '''),
            },
            'prowlarr': {
                # Similar structure for Prowlarr
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: prowlarr
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Prowlarr Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: prowlarr
                      namespace: prowlarr
                    spec:
                      releaseName: prowlarr
                      chart:
                        spec:
                          chart: prowlarr
                          version: 2.2.2
                          sourceRef:
                            kind: HelmRepository
                            name: prowlarr-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: prowlarr-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: prowlarr-values
                        files:
                          - values.yaml
                '''),
            },
            'sonarr': {
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: sonarr
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Sonarr Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: sonarr
                      namespace: sonarr
                    spec:
                      releaseName: sonarr
                      chart:
                        spec:
                          chart: sonarr
                          version: 15.2.0
                          sourceRef:
                            kind: HelmRepository
                            name: sonarr-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: sonarr-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: sonarr-values
                        files:
                          - values.yaml
                '''),
            },
            'radarr': {
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: radarr
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Radarr Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: radarr
                      namespace: radarr
                    spec:
                      releaseName: radarr
                      chart:
                        spec:
                          chart: radarr
                          version: 15.2.0
                          sourceRef:
                            kind: HelmRepository
                            name: radarr-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: radarr-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: radarr-values
                        files:
                          - values.yaml
                '''),
            },
            'readarr': {
                # Similar structure for Readarr
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: readarr
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Readarr Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: readarr
                      namespace: readarr
                    spec:
                      releaseName: readarr
                      chart:
                        spec:
                          chart: readarr
                          version: 1.0.0
                          sourceRef:
                            kind: HelmRepository
                            name: readarr-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: readarr-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: readarr-values
                        files:
                          - values.yaml
                '''),
            },
            'overseerr': {
                # Similar structure for Overseerr
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: overseerr
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Overseerr Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: overseerr
                      namespace: overseerr
                    spec:
                      releaseName: overseerr
                      chart:
                        spec:
                          chart: overseerr
                          version: 1.0.0
                          sourceRef:
                            kind: HelmRepository
                            name: overseerr-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: overseerr-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: overseerr-values
                        files:
                          - values.yaml
                '''),
            },
            'lidarr': {
                # Similar structure for Lidarr
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: lidarr
                '''),
                'values.yaml': textwrap.dedent('''\
                    # Lidarr Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: lidarr
                      namespace: lidarr
                    spec:
                      releaseName: lidarr
                      chart:
                        spec:
                          chart: lidarr
                          version: 1.0.0
                          sourceRef:
                            kind: HelmRepository
                            name: lidarr-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: lidarr-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: lidarr-values
                        files:
                          - values.yaml
                '''),
            },
            'sabnzbd': {
                # Similar structure for SABnzbd
                'namespace.yaml': textwrap.dedent('''\
                    apiVersion: v1
                    kind: Namespace
                    metadata:
                      name: sabnzbd
                '''),
                'values.yaml': textwrap.dedent('''\
                    # SABnzbd Helm chart values
                    persistence:
                      config:
                        enabled: true
                        size: 5Gi
                '''),
                'helmrelease.yaml': textwrap.dedent('''\
                    apiVersion: helm.toolkit.fluxcd.io/v2beta1
                    kind: HelmRelease
                    metadata:
                      name: sabnzbd
                      namespace: sabnzbd
                    spec:
                      releaseName: sabnzbd
                      chart:
                        spec:
                          chart: sabnzbd
                          version: 1.0.0
                          sourceRef:
                            kind: HelmRepository
                            name: sabnzbd-helmrepository
                            namespace: flux-system
                      interval: 5m
                      valuesFrom:
                        - kind: ConfigMap
                          name: sabnzbd-values
                          valuesKey: values.yaml
                '''),
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - namespace.yaml
                      - helmrelease.yaml
                    configMapGenerator:
                      - name: sabnzbd-values
                        files:
                          - values.yaml
                '''),
            },
        },
        'core': {
            'kustomization.yaml': textwrap.dedent('''\
                resources:
                  - network/
                  - security/
            '''),
            'network': {
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - cilium/
                      - nginx/
                      - cert-manager/
                      - cloudflared/
                      - external-dns/
                '''),
                'cilium': {
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: cilium
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # Cilium Helm chart values
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: cilium
                          namespace: cilium
                        spec:
                          releaseName: cilium
                          chart:
                            spec:
                              chart: cilium
                              version: 1.13.4
                              sourceRef:
                                kind: HelmRepository
                                name: cilium-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: ConfigMap
                              name: cilium-values
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                        configMapGenerator:
                          - name: cilium-values
                            files:
                              - values.yaml
                    '''),
                },
                'nginx': {
                    # Configuration for NGINX Ingress Controller
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: ingress-nginx
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # NGINX Ingress Controller Helm chart values
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: ingress-nginx
                          namespace: ingress-nginx
                        spec:
                          releaseName: ingress-nginx
                          chart:
                            spec:
                              chart: ingress-nginx
                              version: 4.0.13
                              sourceRef:
                                kind: HelmRepository
                                name: ingress-nginx-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: ConfigMap
                              name: ingress-nginx-values
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                        configMapGenerator:
                          - name: ingress-nginx-values
                            files:
                              - values.yaml
                    '''),
                },
                'cert-manager': {
                    # Configuration for cert-manager
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: cert-manager
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # cert-manager Helm chart values
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: cert-manager
                          namespace: cert-manager
                        spec:
                          releaseName: cert-manager
                          chart:
                            spec:
                              chart: cert-manager
                              version: v1.11.0
                              sourceRef:
                                kind: HelmRepository
                                name: cert-manager-helmrepository
                                namespace: flux-system
                          interval: 5m
                          values:
                            installCRDs: true
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                    '''),
                },
                'external-dns': {
                    # Configuration for ExternalDNS
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: external-dns
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # ExternalDNS Helm chart values
                        provider: cloudflare
                        cloudflare:
                          apiToken: "YOUR_CLOUDFLARE_API_TOKEN"
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: external-dns
                          namespace: external-dns
                        spec:
                          releaseName: external-dns
                          chart:
                            spec:
                              chart: external-dns
                              version: 1.12.2
                              sourceRef:
                                kind: HelmRepository
                                name: external-dns-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: ConfigMap
                              name: external-dns-values
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                        configMapGenerator:
                          - name: external-dns-values
                            files:
                              - values.yaml
                    '''),
                },
                'cloudflared': {
                    # Configuration for cloudflared
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: cloudflared
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # cloudflared Helm chart values
                        tunnelToken: "YOUR_CLOUDFLARE_TUNNEL_TOKEN"
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: cloudflared
                          namespace: cloudflared
                        spec:
                          releaseName: cloudflared
                          chart:
                            spec:
                              chart: cloudflared
                              version: 0.6.0
                              sourceRef:
                                kind: HelmRepository
                                name: cloudflared-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: ConfigMap
                              name: cloudflared-values
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                        configMapGenerator:
                          - name: cloudflared-values
                            files:
                              - values.yaml
                    '''),
                },
            },
            'security': {
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - authelia/
                      - authentik/
                      - external-secrets/
                      - 1password/
                '''),
                'authelia': {
                    # Configuration for Authelia
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: authelia
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # Authelia Helm chart values
                        secret:
                          jwtSecret: "YOUR_JWT_SECRET"
                          sessionSecret: "YOUR_SESSION_SECRET"
                          storageEncryptionKey: "YOUR_STORAGE_ENCRYPTION_KEY"
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: authelia
                          namespace: authelia
                        spec:
                          releaseName: authelia
                          chart:
                            spec:
                              chart: authelia
                              version: 1.0.0
                              sourceRef:
                                kind: HelmRepository
                                name: authelia-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: ConfigMap
                              name: authelia-values
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                        configMapGenerator:
                          - name: authelia-values
                            files:
                              - values.yaml
                    '''),
                },
                'authentik': {
                    # Configuration for Authentik
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: authentik
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # Authentik Helm chart values
                        postgresql:
                          auth:
                            password: "YOUR_POSTGRES_PASSWORD"
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: authentik
                          namespace: authentik
                        spec:
                          releaseName: authentik
                          chart:
                            spec:
                              chart: authentik
                              version: 4.0.0
                              sourceRef:
                                kind: HelmRepository
                                name: authentik-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: ConfigMap
                              name: authentik-values
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                        configMapGenerator:
                          - name: authentik-values
                            files:
                              - values.yaml
                    '''),
                },
                'external-secrets': {
                    # Configuration for External Secrets Operator
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: external-secrets
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # External Secrets Helm chart values
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: external-secrets
                          namespace: external-secrets
                        spec:
                          releaseName: external-secrets
                          chart:
                            spec:
                              chart: external-secrets
                              version: 0.5.1
                              sourceRef:
                                kind: HelmRepository
                                name: external-secrets-helmrepository
                                namespace: flux-system
                          interval: 5m
                          values:
                            installCRDs: true
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - helmrelease.yaml
                    '''),
                },
                '1password': {
                    # Configuration for 1Password Connect
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: onepassword
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # 1Password Helm chart values
                        connect:
                          token: "YOUR_OP_CONNECT_TOKEN"
                    '''),
                    'secret.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Secret
                        metadata:
                          name: onepassword-connect-token
                          namespace: onepassword
                        type: Opaque
                        stringData:
                          values.yaml: |
                            connect:
                              token: "YOUR_OP_CONNECT_TOKEN"
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        apiVersion: helm.toolkit.fluxcd.io/v2beta1
                        kind: HelmRelease
                        metadata:
                          name: onepassword-connect
                          namespace: onepassword
                        spec:
                          releaseName: onepassword-connect
                          chart:
                            spec:
                              chart: onepassword-connect
                              version: 1.6.0
                              sourceRef:
                                kind: HelmRepository
                                name: onepassword-helmrepository
                                namespace: flux-system
                          interval: 5m
                          valuesFrom:
                            - kind: Secret
                              name: onepassword-connect-token
                              valuesKey: values.yaml
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        resources:
                          - namespace.yaml
                          - secret.yaml
                          - helmrelease.yaml
                    '''),
                },
            },
        },
        'platform': {
            'kustomization.yaml': textwrap.dedent('''\
                resources:
                  - network/
                  - storage/
            '''),
            'network': {
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - cilium/
                '''),
                'cilium': {
                    # Configuration for Cilium (as previously provided)
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: cilium
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # Cilium Helm chart values
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        # (As previously provided)
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        # (As previously provided)
                    '''),
                },
            },
            'storage': {
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - ceph-csi-cephfs/
                '''),
                'ceph-csi-cephfs': {
                    # Configuration for Ceph CSI (as previously provided)
                    'namespace.yaml': textwrap.dedent('''\
                        apiVersion: v1
                        kind: Namespace
                        metadata:
                          name: ceph-csi-cephfs
                    '''),
                    'values.yaml': textwrap.dedent('''\
                        # Ceph CSI Helm chart values
                    '''),
                    'helmrelease.yaml': textwrap.dedent('''\
                        # (As previously provided)
                    '''),
                    'kustomization.yaml': textwrap.dedent('''\
                        # (As previously provided)
                    '''),
                },
            },
        },
    },
    'clusters': {
        'staging': {
            'kustomization.yaml': textwrap.dedent('''\
                resources:
                  - repos.yaml
                  - secrets.yaml
                  - git.yaml
                  - apps.yaml
                  - core.yaml
                  - platform.yaml
            '''),
            'apps.yaml': textwrap.dedent('''\
                apiVersion: kustomize.toolkit.fluxcd.io/v1
                kind: Kustomization
                metadata:
                  name: apps
                  namespace: flux-system
                spec:
                  interval: 10m
                  sourceRef:
                    kind: GitRepository
                    name: flux-system
                  path: ./../../manifests/apps
                  prune: true
                  wait: true
                  decryption:
                    provider: sops
                    secretRef:
                      name: sops-age
            '''),
            'core.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'platform.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'repos.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'secrets.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'git.yaml': textwrap.dedent('''\
                apiVersion: kustomize.toolkit.fluxcd.io/v1
                kind: Kustomization
                metadata:
                  name: git
                  namespace: flux-system
                spec:
                  interval: 10m
                  sourceRef:
                    kind: GitRepository
                    name: flux-system
                  path: ./../../shared/repo/git
                  prune: true
                  wait: true
            '''),
        },
        'production': {
            'kustomization.yaml': textwrap.dedent('''\
                resources:
                  - repos.yaml
                  - secrets.yaml
                  - git.yaml
                  - apps.yaml
                  - core.yaml
                  - platform.yaml
            '''),
            'apps.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'core.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'platform.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'repos.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'secrets.yaml': textwrap.dedent('''\
                # (As previously provided)
            '''),
            'git.yaml': textwrap.dedent('''\
                apiVersion: kustomize.toolkit.fluxcd.io/v1
                kind: Kustomization
                metadata:
                  name: git
                  namespace: flux-system
                spec:
                  interval: 10m
                  sourceRef:
                    kind: GitRepository
                    name: flux-system
                  path: ./../../shared/repo/git
                  prune: true
                  wait: true
            '''),
        },
    },
    'shared': {
        'repo': {
            'helm': {
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - plex-helmrepository.yaml
                      - prowlarr-helmrepository.yaml
                      - sonarr-helmrepository.yaml
                      - radarr-helmrepository.yaml
                      - readarr-helmrepository.yaml
                      - overseerr-helmrepository.yaml
                      - lidarr-helmrepository.yaml
                      - sabnzbd-helmrepository.yaml
                      # Add other Helm repositories here
                '''),
                'plex-helmrepository.yaml': textwrap.dedent('''\
                    apiVersion: source.toolkit.fluxcd.io/v1beta2
                    kind: HelmRepository
                    metadata:
                      name: plex-helmrepository
                      namespace: flux-system
                    spec:
                      url: https://charts.plex.tv
                      interval: 1h
                '''),
                'prowlarr-helmrepository.yaml': textwrap.dedent('''\
                    # (As previously provided)
                '''),
                'sonarr-helmrepository.yaml': textwrap.dedent('''\
                    apiVersion: source.toolkit.fluxcd.io/v1beta2
                    kind: HelmRepository
                    metadata:
                      name: sonarr-helmrepository
                      namespace: flux-system
                    spec:
                      url: https://charts.k8s-at-home.com/charts/
                      interval: 1h
                '''),
                'radarr-helmrepository.yaml': textwrap.dedent('''\
                    apiVersion: source.toolkit.fluxcd.io/v1beta2
                    kind: HelmRepository
                    metadata:
                      name: radarr-helmrepository
                      namespace: flux-system
                    spec:
                      url: https://charts.k8s-at-home.com/charts/
                      interval: 1h
                '''),
                # Other HelmRepository definitions (readarr, overseerr, etc.)
                # (As previously provided)
            },
            'git': {
                'kustomization.yaml': textwrap.dedent('''\
                    resources:
                      - flux-system-gitrepository.yaml
                      - my-secrets-gitrepository.yaml
                      # Add other Git repositories here
                '''),
                'flux-system-gitrepository.yaml': textwrap.dedent('''\
                    apiVersion: source.toolkit.fluxcd.io/v1beta2
                    kind: GitRepository
                    metadata:
                      name: flux-system
                      namespace: flux-system
                    spec:
                      interval: 1m0s
                      url: https://github.com/your-org/your-repo.git
                      branch: main
                      secretRef:
                        name: flux-system-git-auth
                '''),
                'my-secrets-gitrepository.yaml': textwrap.dedent('''\
                    apiVersion: source.toolkit.fluxcd.io/v1beta2
                    kind: GitRepository
                    metadata:
                      name: my-secrets
                      namespace: flux-system
                    spec:
                      interval: 1m0s
                      url: https://github.com/your-org/my-secrets.git
                      branch: main
                      secretRef:
                        name: my-secrets-git-auth
                '''),
                # Add other GitRepository definitions if needed
            },
            'kustomization.yaml': textwrap.dedent('''\
                resources:
                  - helm/
                  - git/
            '''),
        },
        'kustomization.yaml': textwrap.dedent('''\
            resources:
              - repo/
        '''),
    },
}

def create_structure(base_path, structure):
    for name, content in structure.items():
        path = os.path.join(base_path, name)
        if isinstance(content, dict):
            # It's a directory
            os.makedirs(path, exist_ok=True)
            create_structure(path, content)
        else:
            # It's a file
            with open(path, 'w') as f:
                f.write(content)

if __name__ == '__main__':
    create_structure('.', structure)
    print('Directory structure and files have been created successfully.')
