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

# Wait for helm-controller cache to be ready by checking actual HelmRelease processing
# Instead of blind 45s sleep, we query direct state: observedGeneration != -1
# This proves the controller cache is synced and processing resources
resource "null_resource" "wait_helm_cache_ready" {
  depends_on = [null_resource.wait_flux_controllers]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for helm-controller cache to be ready..."

      # Wait for ANY HelmRelease to move past observedGeneration: -1
      # Direct state query from Kubernetes API - not a timing assumption
      timeout 90 bash -c 'until [ "$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease -A -o jsonpath='\''{range .items[*]}{.status.observedGeneration}{"\n"}{end}'\'' 2>/dev/null | grep -v "^-1$" | grep -v "^$" | wc -l)" -gt "0" ]; do echo "  ⏳ Waiting for HelmReleases to be processed by helm-controller..."; sleep 2; done'

      echo "✓ helm-controller cache is ready (HelmRelease processed with observedGeneration != -1)"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Run post-bootstrap operations after Flux is ready
resource "null_resource" "post_bootstrap" {
  count = var.repo_root != "" ? 1 : 0

  depends_on = [null_resource.wait_helm_cache_ready]

  provisioner "local-exec" {
    working_dir = var.repo_root
    command     = "./scripts/post-bootstrap.sh"

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}
