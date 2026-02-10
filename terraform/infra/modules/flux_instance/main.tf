# Flux Instance Module
# Creates FluxInstance CR after flux-operator is ready
# This is Phase 2 of the two-phase Flux deployment

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

# Create FluxInstance to configure what Flux syncs
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
        patches = var.sops_age_key != "" ? [
          {
            target = {
              kind = "Kustomization"
              name = "flux-system"
            }
            patch = yamlencode([
              {
                op    = "add"
                path  = "/spec/decryption"
                value = {
                  provider = "sops"
                  secretRef = {
                    name = "sops-age"
                  }
                }
              }
            ])
          }
        ] : []
      }
    }
  }

  depends_on = [kubernetes_secret_v1.sops_age]
}

# Wait for Flux controllers to be ready
# Uses kubectl wait for simplicity and reliability
resource "null_resource" "wait_flux_controllers" {
  depends_on = [kubernetes_manifest.flux_instance]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for flux-operator to create Flux controllers..."

      # First, wait for flux-operator to create the deployments (up to 2 minutes)
      TIMEOUT=120
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
          --timeout=300s
      done

      echo "✓ All Flux controllers are ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Step 1: Suspend flux-system to prevent apps from deploying before helm cache is ready
resource "null_resource" "suspend_flux_system" {
  depends_on = [null_resource.wait_flux_controllers]

  # Trigger recreation when FluxInstance changes
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
# Using kubectl apply instead of kubernetes_manifest to avoid CRD validation issues during plan
resource "null_resource" "deploy_canary" {
  depends_on = [null_resource.suspend_flux_system]

  # Trigger recreation when suspend_flux_system changes
  triggers = {
    suspend_id = null_resource.suspend_flux_system.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Deploying canary HelmRepository and HelmRelease..."

      # Create HelmRepository
      cat <<EOF | kubectl --kubeconfig="$KUBECONFIG" apply -f -
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
      cat <<EOF | kubectl --kubeconfig="$KUBECONFIG" apply -f -
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
# Falls back to time-based wait if canary fails
resource "null_resource" "wait_helm_cache_ready" {
  depends_on = [null_resource.deploy_canary]

  # Trigger recreation when deploy_canary changes
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

  # Trigger recreation when wait_helm_cache_ready changes
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
          # This tells Helm: "these resources are yours to manage now"
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

# Step 6: Resume flux-system and clean up canary (atomic operation)
resource "null_resource" "resume_and_cleanup" {
  depends_on = [null_resource.adopt_cilium]

  # Trigger recreation when adopt_cilium changes
  triggers = {
    adopt_id = null_resource.adopt_cilium.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Resume flux-system first (most critical operation)
      echo "Resuming flux-system (helm cache is ready)..."
      kubectl --kubeconfig="$KUBECONFIG" patch kustomization flux-system -n flux-system \
        --type=merge -p '{"spec":{"suspend":false}}'
      echo "✓ flux-system resumed - apps will now deploy"

      # Clean up canary (best effort - don't fail if this errors)
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
