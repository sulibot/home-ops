# Flux Instance Module - REORGANIZED
# Phase 1: Preinstall critical apps BEFORE Flux starts
# Phase 2: Deploy Flux (it will adopt the preinstalled apps via SSA Replace)
# Phase 3: Post-bootstrap verification and cleanup

########## PHASE 1: PRE-FLUX SETUP ##########

# Create SOPS AGE secret for decrypting secrets
resource "kubernetes_secret_v1" "sops_age" {
  count = var.sops_age_key != "" ? 1 : 0

  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }

  data = {
    "age.agekey" = var.sops_age_key
  }

  type = "Opaque"
}

# Patch kubernetes.default service to dual-stack for IPv4 fallback
# This fixes Cilium IPv6 ClusterIP routing issues that cause timeouts
# Must be applied BEFORE any apps try to reach the API server
resource "null_resource" "patch_kubernetes_service" {
  depends_on = [kubernetes_secret_v1.sops_age]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Patching kubernetes.default service to dual-stack..."

      kubectl --kubeconfig="$KUBECONFIG" patch service kubernetes -n default \
        --type=merge \
        -p '{"spec":{"ipFamilyPolicy":"PreferDualStack","ipFamilies":["IPv6","IPv4"]}}'

      echo "✓ kubernetes.default service configured as dual-stack"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Pre-pull critical container images to all nodes
# This dramatically speeds up initial pod startup (60s → 1s for large images)
# Images are extracted from Flux HelmRelease/OCIRepository configs via helm template
resource "null_resource" "prepull_images" {
  depends_on = [null_resource.patch_kubernetes_service]

  triggers = {
    # Re-run if script changes
    script_hash = filesha256("${path.module}/scripts/prepull-images.sh")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/prepull-images.sh \"$KUBECONFIG\""

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

########## PHASE 1: PREINSTALL CRDs ##########
# Install CRDs first so ServiceMonitor/PodMonitor/etc are available for all apps

# Preinstall Gateway API CRDs (required by cert-manager and Cilium Gateway)
resource "null_resource" "preinstall_gateway_api_crds" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.patch_kubernetes_service]

  triggers = {
    patch_id = null_resource.patch_kubernetes_service.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing Gateway API CRDs..."

      # Apply Gateway API CRDs from Git repo (server-side required for v1.4.0 experimental)
      kubectl --kubeconfig="$KUBECONFIG" apply --server-side -f \
        ${var.repo_root}/kubernetes/apps/crds/gateway-api-crds/gateway-api-crds-v1.4.0-experimental.yaml

      echo "✓ Gateway API CRDs installed"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall kube-prometheus-stack CRDs (ServiceMonitor, PodMonitor, PrometheusRule, etc.)
resource "null_resource" "preinstall_prometheus_crds" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_gateway_api_crds]

  triggers = {
    gateway_api_id = null_resource.preinstall_gateway_api_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing kube-prometheus-stack CRDs..."

      # Extract chart version and URL
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/observability-stack/kube-prometheus-stack/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/observability-stack/kube-prometheus-stack/app/ocirepository.yaml)

      # Extract and apply only CRDs from the chart (filter out non-CRD resources)
      helm template kube-prometheus-stack-crds \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace observability \
        --include-crds \
        | yq eval 'select(.kind == "CustomResourceDefinition")' - \
        | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side

      echo "✓ kube-prometheus-stack CRDs installed (ServiceMonitor, PodMonitor, etc.)"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall KEDA CRDs (ScaledObject, ScaledJob, TriggerAuthentication, etc.)
resource "null_resource" "preinstall_keda_crds" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_prometheus_crds]

  triggers = {
    prometheus_crds_id = null_resource.preinstall_prometheus_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing KEDA CRDs..."

      # Extract chart version and URL
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/observability-stack/keda/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/observability-stack/keda/app/ocirepository.yaml)

      # Extract and apply only CRDs from the chart (filter out non-CRD resources)
      helm template keda-crds \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace keda \
        --include-crds \
        | yq eval 'select(.kind == "CustomResourceDefinition")' - \
        | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side

      echo "✓ KEDA CRDs installed"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall Grafana Operator CRDs (GrafanaDashboard, GrafanaDataSource, GrafanaFolder, etc.)
resource "null_resource" "preinstall_grafana_crds" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_keda_crds]

  triggers = {
    keda_crds_id = null_resource.preinstall_keda_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing Grafana Operator CRDs..."

      # Extract chart version and URL
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/observability-stack/grafana/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/observability-stack/grafana/app/ocirepository.yaml)

      # Extract and apply only CRDs from the chart (filter out non-CRD resources)
      helm template grafana-operator-crds \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace grafana \
        --include-crds \
        | yq eval 'select(.kind == "CustomResourceDefinition")' - \
        | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side

      echo "✓ Grafana Operator CRDs installed"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall Snapshot Controller CRDs (VolumeSnapshot, VolumeSnapshotClass, VolumeSnapshotContent)
resource "null_resource" "preinstall_snapshot_crds" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_grafana_crds]

  triggers = {
    grafana_crds_id = null_resource.preinstall_grafana_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing Snapshot Controller CRDs..."

      # Extract chart version and URL
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/kube-system/snapshot-controller/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/kube-system/snapshot-controller/app/ocirepository.yaml)

      # Extract and apply only CRDs from the chart (filter out non-CRD resources)
      helm template snapshot-controller-crds \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace kube-system \
        --include-crds \
        | yq eval 'select(.kind == "CustomResourceDefinition")' - \
        | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side

      echo "✓ Snapshot Controller CRDs installed (VolumeSnapshot, VolumeSnapshotClass, etc.)"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

########## PHASE 2: PREINSTALL APPS ##########

# Preinstall spegel (P2P container image distribution) - DISABLED
# Spegel is incompatible with Cilium BPF + IPv6 ULA networking (libp2p TLS handshake timeouts)
# Removed to unblock Terraform bootstrap - can investigate alternatives later
# resource "null_resource" "preinstall_spegel" {
#   depends_on = [null_resource.preinstall_snapshot_crds]
#
#   triggers = {
#     snapshot_crds_id = null_resource.preinstall_snapshot_crds.id
#   }
#
#   provisioner "local-exec" {
#     command = <<-EOT
#       set -e
#       echo "Installing spegel..."
#
#       # Extract chart version and URL from Git repo
#       CHART_VERSION=$(yq eval '.spec.ref.tag' \
#         ${var.repo_root}/kubernetes/apps/core/spegel/app/ocirepository.yaml)
#       CHART_URL=$(yq eval '.spec.url' \
#         ${var.repo_root}/kubernetes/apps/core/spegel/app/ocirepository.yaml)
#
#       # Extract values from HelmRelease (Prometheus CRDs already installed)
#       yq eval '.spec.values' \
#         ${var.repo_root}/kubernetes/apps/core/spegel/app/helmrelease.yaml \
#         > /tmp/spegel-values.yaml
#
#       # Template and apply chart (no Helm release - Flux will adopt via SSA Replace)
#       helm template spegel \
#         $CHART_URL \
#         --version $CHART_VERSION \
#         --namespace kube-system \
#         --values /tmp/spegel-values.yaml \
#         | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts
#
#       # Wait for spegel DaemonSet to be ready (longer timeout for P2P initialization)
#       kubectl --kubeconfig="$KUBECONFIG" wait --for=condition=Ready pod \
#         -l app.kubernetes.io/name=spegel \
#         -n kube-system \
#         --timeout=600s
#
#       rm -f /tmp/spegel-values.yaml
#       echo "✓ spegel installed and ready"
#     EOT
#
#     environment = {
#       KUBECONFIG = var.kubeconfig_path
#     }
#   }
# }

# Preinstall external-secrets operator (required for 1Password and other secret management)
resource "null_resource" "preinstall_external_secrets" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_snapshot_crds]

  triggers = {
    snapshot_crds_id = null_resource.preinstall_snapshot_crds.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing external-secrets operator..."

      # Create namespace
      kubectl --kubeconfig="$KUBECONFIG" create namespace external-secrets \
        --dry-run=client -o yaml | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts

      # Extract chart version and URL from Git repo (zero drift!)
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/foundation/external-secrets/external-secrets/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/foundation/external-secrets/external-secrets/app/ocirepository.yaml)

      # Extract values from HelmRelease
      yq eval '.spec.values' \
        ${var.repo_root}/kubernetes/apps/foundation/external-secrets/external-secrets/app/helmrelease.yaml \
        > /tmp/external-secrets-values.yaml

      # Install as a proper Helm release so Flux can adopt with fast upgrade.
      # Critically, this ensures Helm owns all service port fields from the start,
      # preventing SSA field ownership conflicts on the webhook service (port 443).
      helm upgrade --install external-secrets \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace external-secrets \
        --values /tmp/external-secrets-values.yaml \
        --kubeconfig="$KUBECONFIG" \
        --wait \
        --timeout 10m

      rm -f /tmp/external-secrets-values.yaml
      echo "✓ external-secrets installed and ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall 1Password Connect (secrets backend for external-secrets)
resource "null_resource" "preinstall_onepassword" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_external_secrets]

  triggers = {
    external_secrets_id = null_resource.preinstall_external_secrets.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing 1Password Connect..."

      # Decrypt and apply the SOPS-encrypted credentials secret
      sops -d ${var.repo_root}/kubernetes/apps/foundation/external-secrets/onepassword/app/credentials.json-secret.sops.yaml | \
        kubectl --kubeconfig="$KUBECONFIG" apply -f -

      # Extract chart version and URL from Git repo
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/foundation/external-secrets/onepassword/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/foundation/external-secrets/onepassword/app/ocirepository.yaml)

      # Extract values from HelmRelease
      yq eval '.spec.values' \
        ${var.repo_root}/kubernetes/apps/foundation/external-secrets/onepassword/app/helmrelease.yaml \
        > /tmp/onepassword-values.yaml

      # Install as a proper Helm release so Flux can adopt with fast upgrade.
      helm upgrade --install onepassword \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace external-secrets \
        --values /tmp/onepassword-values.yaml \
        --kubeconfig="$KUBECONFIG" \
        --wait \
        --timeout 10m

      rm -f /tmp/onepassword-values.yaml
      echo "✓ 1Password Connect installed and ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall cert-manager (certificate management for ingress/webhooks)
resource "null_resource" "preinstall_cert_manager" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_onepassword]

  triggers = {
    onepassword_id = null_resource.preinstall_onepassword.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing cert-manager..."

      # Create namespace
      kubectl --kubeconfig="$KUBECONFIG" create namespace cert-manager \
        --dry-run=client -o yaml | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts

      # Extract chart version from HelmRelease
      CHART_VERSION=$(yq eval '.spec.chart.spec.version' \
        ${var.repo_root}/kubernetes/apps/core/cert-manager/app/helmrelease.yaml)

      # Extract repo URL from HelmRepository
      REPO_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/core/cert-manager/helm-repo/helmrepository.yaml)

      # Extract values from HelmRelease
      yq eval '.spec.values' \
        ${var.repo_root}/kubernetes/apps/core/cert-manager/app/helmrelease.yaml \
        > /tmp/cert-manager-values.yaml

      # Add Helm repository
      helm repo add cert-manager-temp $REPO_URL
      helm repo update cert-manager-temp

      # Install cert-manager as a proper Helm release so Flux can adopt it with
      # a fast helm upgrade instead of a slow helm install from scratch.
      # CRDs are auto-installed from the chart's crds/ directory.
      helm upgrade --install cert-manager \
        cert-manager-temp/cert-manager \
        --version $CHART_VERSION \
        --namespace cert-manager \
        --values /tmp/cert-manager-values.yaml \
        --kubeconfig="$KUBECONFIG" \
        --wait \
        --timeout 10m

      # Clean up
      helm repo remove cert-manager-temp || true
      rm -f /tmp/cert-manager-values.yaml
      echo "✓ cert-manager installed and ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall snapshot-controller (CSI volume snapshots)
resource "null_resource" "preinstall_snapshot_controller" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_cert_manager]

  triggers = {
    cert_manager_id = null_resource.preinstall_cert_manager.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing snapshot-controller..."

      # Extract chart version and URL from Git repo
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/kube-system/snapshot-controller/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/kube-system/snapshot-controller/app/ocirepository.yaml)

      # Extract values from HelmRelease (Prometheus CRDs already installed)
      yq eval '.spec.values' \
        ${var.repo_root}/kubernetes/apps/kube-system/snapshot-controller/app/helmrelease.yaml \
        > /tmp/snapshot-controller-values.yaml

      # Install as a proper Helm release so Flux can adopt with fast upgrade.
      helm upgrade --install snapshot-controller \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace kube-system \
        --values /tmp/snapshot-controller-values.yaml \
        --kubeconfig="$KUBECONFIG" \
        --wait \
        --timeout 10m

      rm -f /tmp/snapshot-controller-values.yaml
      echo "✓ snapshot-controller installed and ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Preinstall volsync (volume backup/restore for persistent storage)
resource "null_resource" "preinstall_volsync" {
  count      = 0 # DISABLED for now
  depends_on = [null_resource.preinstall_snapshot_controller]

  triggers = {
    snapshot_controller_id = null_resource.preinstall_snapshot_controller.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Installing volsync..."

      # Create namespace
      kubectl --kubeconfig="$KUBECONFIG" create namespace volsync-system \
        --dry-run=client -o yaml | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts

      # Extract chart version and URL from Git repo
      CHART_VERSION=$(yq eval '.spec.ref.tag' \
        ${var.repo_root}/kubernetes/apps/data/volsync/app/ocirepository.yaml)
      CHART_URL=$(yq eval '.spec.url' \
        ${var.repo_root}/kubernetes/apps/data/volsync/app/ocirepository.yaml)

      # Extract values from HelmRelease
      yq eval '.spec.values' \
        ${var.repo_root}/kubernetes/apps/data/volsync/app/helmrelease.yaml \
        > /tmp/volsync-values.yaml

      # Install as a proper Helm release so Flux can adopt with fast upgrade.
      # helm handles CRDs natively - no need for the CRD-splitting workaround.
      helm upgrade --install volsync \
        $CHART_URL \
        --version $CHART_VERSION \
        --namespace volsync-system \
        --values /tmp/volsync-values.yaml \
        --kubeconfig="$KUBECONFIG" \
        --wait \
        --timeout 10m

      rm -f /tmp/volsync-values.yaml
      echo "✓ volsync installed and ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

########## PHASE 2: DEPLOY FLUX ##########

# Create FluxInstance to configure what Flux syncs
# Flux will adopt the preinstalled apps via SSA Replace annotation
resource "kubernetes_manifest" "flux_instance" {
  manifest = {
    apiVersion = "fluxcd.controlplane.io/v1"
    kind       = "FluxInstance"
    metadata = {
      name      = "flux"
      namespace = "flux-system"
    }
    spec = {
      distribution = {
        version  = var.flux_version
        registry = "ghcr.io/fluxcd"
      }
      components = [
        "source-controller",
        "kustomize-controller",
        "helm-controller",
        "notification-controller",
        "image-reflector-controller",
        "image-automation-controller"
      ]
      cluster = {
        type = "kubernetes"
      }
      sync = {
        kind = "GitRepository"
        url  = var.git_repository
        ref  = "refs/heads/${var.git_branch}"
        path = var.git_path
      }
      kustomize = {
        patches = concat(
          var.sops_age_key != "" ? [
            {
              target = {
                kind = "Kustomization"
                name = "flux-system"
              }
              patch = yamlencode([
                {
                  op   = "add"
                  path = "/spec/decryption"
                  value = {
                    provider = "sops"
                    secretRef = {
                      name = "sops-age"
                    }
                  }
                }
              ])
            }
          ] : [],
          [
            # Fix 1: Increase liveness probe delay to prevent restart loops
            {
              target = {
                kind          = "Deployment"
                labelSelector = "app.kubernetes.io/part-of=flux"
              }
              patch = yamlencode([
                {
                  op    = "add"
                  path  = "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds"
                  value = 60
                }
              ])
            },
            # Fix 2: Allow traffic to health/metrics ports (9090, 9440) in NetworkPolicy
            {
              target = {
                kind = "NetworkPolicy"
                name = "allow-scraping"
              }
              patch = yamlencode([
                {
                  op   = "add"
                  path = "/spec/ingress/0/ports/-"
                  value = {
                    port     = 9090
                    protocol = "TCP"
                  }
                },
                {
                  op   = "add"
                  path = "/spec/ingress/0/ports/-"
                  value = {
                    port     = 9440
                    protocol = "TCP"
                  }
                }
              ])
            }
          ]
        )
      }
    }
  }

  # Wait for image pre-pull to complete before deploying Flux
  # This ensures all critical images are cached, speeding up pod startup
  depends_on = [null_resource.prepull_images]
}

# Wait for Flux controllers to be ready
resource "null_resource" "wait_flux_controllers" {
  depends_on = [kubernetes_manifest.flux_instance]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for flux-operator to create Flux controllers..."

      # Wait for flux-operator to create the deployments (up to 7 minutes)
      TIMEOUT=420
      ELAPSED=0
      while [ $ELAPSED -lt $TIMEOUT ]; do
        if kubectl --kubeconfig="$KUBECONFIG" get deployment helm-controller -n flux-system >/dev/null 2>&1; then
          echo "  ✓ Flux controllers created by flux-operator"
          break
        fi
        echo "  ⏳ Waiting for flux-operator to create controllers... ($ELAPSED/$TIMEOUT seconds)"
        sleep 5
        ELAPSED=$((ELAPSED + 5))
      done

      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "  ⚠ Timeout waiting for flux-operator to create controllers"
        exit 1
      fi

      echo "Waiting for Flux controllers to be ready..."

      # Wait for all critical Flux deployments to be Available
      for controller in helm-controller source-controller kustomize-controller notification-controller; do
        echo "  Waiting for $controller..."
        kubectl --kubeconfig="$KUBECONFIG" wait deployment $controller \
          -n flux-system \
          --for=condition=Available \
          --timeout=420s
      done

      echo "✓ All Flux controllers are ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

########## PHASE 3: POST-BOOTSTRAP VERIFICATION AND CLEANUP ##########

# Step 1: Suspend flux-system to prevent apps from deploying before helm cache is ready
resource "null_resource" "suspend_flux_system" {
  depends_on = [null_resource.wait_flux_controllers]

  triggers = {
    flux_instance_id = kubernetes_manifest.flux_instance.object.metadata.uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Suspending flux-system to prevent premature app deployment..."

      # Wait for flux-system Kustomization to exist (created by FluxInstance)
      timeout 30 bash -c '
        until kubectl --kubeconfig="$KUBECONFIG" get kustomization flux-system -n flux-system >/dev/null 2>&1; do
          echo "  ⏳ Waiting for flux-system Kustomization to be created..."
          sleep 1
        done
      '

      # Suspend it immediately
      kubectl --kubeconfig="$KUBECONFIG" patch kustomization flux-system -n flux-system \
        --type=merge -p '{"spec":{"suspend":true}}'

      echo "✓ flux-system suspended - apps blocked from deploying"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Step 2 & 3: Deploy canary HelmRepository and HelmRelease for testing helm-controller cache
resource "null_resource" "deploy_canary" {
  depends_on = [null_resource.suspend_flux_system]

  triggers = {
    suspend_id = null_resource.suspend_flux_system.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Deploying canary HelmRepository and HelmRelease..."

      # Create HelmRepository
      cat <<EOF | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: podinfo
  namespace: flux-system
  labels:
    app.kubernetes.io/managed-by: terraform
    flux.home-ops.io/cache-test: "true"
spec:
  interval: 1h
  url: https://stefanprodan.github.io/podinfo
EOF

      # Wait a moment for source-controller to process the HelmRepository
      sleep 2

      # Create HelmRelease
      cat <<EOF | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flux-cache-canary
  namespace: flux-system
  labels:
    app.kubernetes.io/managed-by: terraform
    flux.home-ops.io/cache-test: "true"
spec:
  interval: 1h
  chart:
    spec:
      chart: podinfo
      version: 6.7.0
      sourceRef:
        kind: HelmRepository
        name: podinfo
        namespace: flux-system
  values:
    replicaCount: 0
    resources:
      requests:
        cpu: 1m
        memory: 1Mi
EOF

      echo "✓ Canary resources deployed"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Step 4: Wait for canary to prove helm-controller cache is ready
resource "null_resource" "wait_helm_cache_ready" {
  depends_on = [null_resource.deploy_canary]

  triggers = {
    canary_id = null_resource.deploy_canary.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Testing helm-controller cache with canary HelmRelease..."

      # Try to wait for canary to have observedGeneration != -1
      # This proves helm-controller cache is synced and processing resources
      if timeout 90 bash -c '
        until [ "$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease flux-cache-canary -n flux-system -o jsonpath='\''{.status.observedGeneration}'\'' 2>/dev/null)" != "-1" ] && \
              [ "$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease flux-cache-canary -n flux-system -o jsonpath='\''{.status.observedGeneration}'\'' 2>/dev/null)" != "" ]; do
          echo "  ⏳ Waiting for helm-controller cache..."
          sleep 2
        done
      '; then
        echo "✓ helm-controller cache is ready (canary observedGeneration != -1)"
      else
        echo "⚠️  Canary timeout - falling back to time-based wait (45s)"
        echo "    This ensures flux-system won't stay suspended indefinitely"
        sleep 45
        echo "✓ Fallback wait complete - proceeding"
      fi
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Step 5: Adopt Talos-installed Cilium into Helm management
resource "null_resource" "adopt_cilium" {
  depends_on = [null_resource.wait_helm_cache_ready]

  triggers = {
    wait_id = null_resource.wait_helm_cache_ready.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Checking if Cilium was installed by Talos inline manifests..."

      # Check if Cilium DaemonSet exists but has no Helm metadata
      if kubectl --kubeconfig="$KUBECONFIG" get daemonset cilium -n kube-system >/dev/null 2>&1; then
        # Check if it's already managed by Helm
        if ! kubectl --kubeconfig="$KUBECONFIG" get secret -n kube-system -l owner=helm,name=cilium >/dev/null 2>&1; then
          echo "  Found Talos-installed Cilium - adopting into Helm..."

          # Label critical Cilium resources so Helm can adopt them
          for resource in \
            "daemonset/cilium" \
            "daemonset/cilium-envoy" \
            "deployment/cilium-operator" \
            "serviceaccount/cilium" \
            "serviceaccount/cilium-operator" \
            "configmap/cilium-config" \
            "service/cilium-agent" \
            "service/cilium-envoy"; do
            kubectl --kubeconfig="$KUBECONFIG" label $resource -n kube-system \
              app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
          done

          echo "✓ Cilium resources labeled for Helm adoption"
          echo "  Flux HelmRelease will now manage Cilium lifecycle"
        else
          echo "✓ Cilium already managed by Helm - no adoption needed"
        fi
      else
        echo "  No existing Cilium installation found - Flux will install fresh"
      fi
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Step 6: Resume flux-system and clean up canary
resource "null_resource" "resume_and_cleanup" {
  depends_on = [null_resource.adopt_cilium]

  triggers = {
    adopt_id = null_resource.adopt_cilium.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Resume flux-system (Flux will now adopt the preinstalled apps)
      echo "Resuming flux-system (helm cache is ready, apps are preinstalled)..."
      kubectl --kubeconfig="$KUBECONFIG" patch kustomization flux-system -n flux-system \
        --type=merge -p '{"spec":{"suspend":false}}'
      echo "✓ flux-system resumed - Flux will adopt preinstalled apps via SSA Replace"

      # Force immediate reconciliation of pre-installed app kustomizations so Flux
      # adopts them now instead of waiting for the default poll interval (~5m).
      echo "Triggering immediate reconciliation of pre-installed apps..."
      FLUX_KUBECONFIG="$KUBECONFIG"
      for KS in external-secrets onepassword cert-manager snapshot-controller volsync; do
        echo "  Reconciling kustomization/$KS..."
        flux reconcile kustomization $KS -n flux-system \
          --kubeconfig="$FLUX_KUBECONFIG" \
          --with-source \
          --timeout=5m 2>/dev/null || \
        echo "  ⚠ Could not reconcile $KS (may not exist yet, Flux will pick it up on next poll)"
      done
      echo "✓ Pre-installed apps queued for immediate adoption"

      # Clean up canary (best effort)
      echo "Cleaning up cache test canary..."
      kubectl --kubeconfig="$KUBECONFIG" delete helmrelease flux-cache-canary -n flux-system --ignore-not-found=true || true
      kubectl --kubeconfig="$KUBECONFIG" delete helmrepository podinfo -n flux-system --ignore-not-found=true || true
      echo "✓ Canary cleanup complete"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Step 7: Run post-bootstrap operations after Flux is ready
resource "null_resource" "post_bootstrap" {
  count = var.repo_root != "" ? 1 : 0

  depends_on = [null_resource.resume_and_cleanup]

  provisioner "local-exec" {
    working_dir = var.repo_root
    command     = "./scripts/post-bootstrap.sh"

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}
