# Flux Instance Module
# Phase 1: Pre-flux setup
# Phase 2: Deploy Flux instance
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

# Wait for Flux operator CRD + namespace to exist before applying FluxInstance.
resource "null_resource" "wait_fluxinstance_crd" {
  depends_on = [null_resource.patch_kubernetes_service]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      echo "Waiting for flux-system namespace..."
      timeout 300 bash -c '
        until kubectl --kubeconfig="$KUBECONFIG" get namespace flux-system >/dev/null 2>&1; do
          sleep 2
        done
      '
      echo "Waiting for FluxInstance CRD..."
      kubectl --kubeconfig="$KUBECONFIG" wait --for=condition=Established \
        crd/fluxinstances.fluxcd.controlplane.io --timeout=300s
      echo "✓ Flux namespace and CRD are ready"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

########## PHASE 2: DEPLOY FLUX ##########

locals {
  flux_instance_manifest = {
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
          var.kubernetes_api_host != "" ? [
            {
              target = {
                kind          = "Deployment"
                labelSelector = "app.kubernetes.io/part-of=flux"
              }
              patch = yamlencode([
                {
                  op   = "add"
                  path = "/spec/template/spec/containers/0/env/-"
                  value = {
                    name  = "KUBERNETES_SERVICE_HOST"
                    value = var.kubernetes_api_host
                  }
                },
                {
                  op   = "add"
                  path = "/spec/template/spec/containers/0/env/-"
                  value = {
                    name  = "KUBERNETES_SERVICE_PORT"
                    value = "6443"
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
}

# Create FluxInstance to configure what Flux syncs.
# Use kubectl apply to avoid plan-time CRD validation races when operator CRDs
# are still registering in a fresh cluster.
resource "null_resource" "flux_instance" {
  triggers = {
    manifest_sha = sha256(yamlencode(local.flux_instance_manifest))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      cat <<'EOF' | kubectl --kubeconfig="$KUBECONFIG" apply -f - --server-side --force-conflicts
${yamlencode(local.flux_instance_manifest)}
EOF
      echo "✓ FluxInstance applied"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }

  # ZOT registry mirror handles image caching — no pre-pull step needed
  depends_on = [null_resource.wait_fluxinstance_crd]
}

# Patch Flux controllers for bootstrap API reachability in dual-stack environments
resource "null_resource" "patch_flux_controllers_api" {
  count      = var.kubernetes_api_host != "" ? 1 : 0
  depends_on = [null_resource.flux_instance]

  triggers = {
    kubernetes_api_host = var.kubernetes_api_host
    flux_instance_id    = null_resource.flux_instance.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CONTROLLERS="source-controller kustomize-controller helm-controller notification-controller image-reflector-controller image-automation-controller"

      echo "Patching Flux controllers for API reachability via ${var.kubernetes_api_host}:6443..."

      # Wait up to 7 minutes for controllers to be created
      TIMEOUT=420
      ELAPSED=0
      while [ $ELAPSED -lt $TIMEOUT ]; do
        if kubectl --kubeconfig="$KUBECONFIG" get deployment helm-controller -n flux-system >/dev/null 2>&1; then
          break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
      done

      for controller in $CONTROLLERS; do
        if kubectl --kubeconfig="$KUBECONFIG" get deployment "$controller" -n flux-system >/dev/null 2>&1; then
          kubectl --kubeconfig="$KUBECONFIG" -n flux-system patch deployment "$controller" \
            --type=merge \
            -p '{"spec":{"template":{"spec":{"hostNetwork":false,"dnsPolicy":"ClusterFirst"}}}}'
          kubectl --kubeconfig="$KUBECONFIG" -n flux-system set env deployment/"$controller" \
            KUBERNETES_SERVICE_HOST='${var.kubernetes_api_host}' \
            KUBERNETES_SERVICE_PORT='6443' >/dev/null
        fi
      done

      echo "✓ Flux controller network patch applied"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Wait for Flux controllers to be ready
resource "null_resource" "wait_flux_controllers" {
  depends_on = [null_resource.flux_instance, null_resource.patch_flux_controllers_api]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for flux-operator to create Flux controllers..."

      # Wait for flux-operator to create the deployments (up to 2 minutes)
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
      FAILED=0
      for controller in helm-controller source-controller kustomize-controller notification-controller; do
        echo "  Waiting for $controller..."
        if ! kubectl --kubeconfig="$KUBECONFIG" wait deployment $controller \
          -n flux-system \
          --for=condition=Available \
          --timeout=120s; then
          echo "  ⚠ $controller did not become Available within timeout"
          FAILED=1
        fi
      done

      if [ "$FAILED" -eq 0 ]; then
        echo "✓ All Flux controllers are ready"
      else
        echo "⚠ Continuing despite Flux controller readiness timeout(s)"
      fi
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
    flux_instance_id = null_resource.flux_instance.id
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
