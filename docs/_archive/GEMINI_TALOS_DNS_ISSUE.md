# Gemini Prompt: Talos Kubernetes DNS Resolution Issue

## CRITICAL: What NOT to Do

**❌ DO NOT attempt to modify the kubelet `resolvConf` field in Talos configuration**

Talos Linux **explicitly prevents** overriding the `kubelet.resolvConf` field. Any attempt to set this field will result in:
```
rpc error: code = InvalidArgument desc = configuration validation failed:
    * kubelet configuration field "resolvConf" can't be overridden
```

This is a **protected/managed field** in Talos - the kubelet DNS configuration is handled internally and cannot be user-modified.

## Problem Statement

I have a Talos Linux v1.11.5 Kubernetes cluster with Cilium v1.18.4 CNI where **DNS resolution from pods fails**. The root cause is a routing issue with link-local addresses.

## Current Setup

**Talos Configuration:**
- Version: v1.11.5
- Nodes: 3 controlplane + 3 workers
- Network: EVPN/VXLAN overlay (vnet101)
- Feature enabled: `forwardKubeDNSToHost: true` (creates 169.254.116.108 DNS endpoint)

**Cilium Configuration:**
- Version: v1.18.4
- Feature enabled: `hostLegacyRouting: true` (allows routing to link-local addresses)
- Issue: Uses BPF host routing which bypasses netfilter

**CoreDNS Configuration:**
- Version: v1.12.4
- Default config: `forward . /etc/resolv.conf`
- Problem: `/etc/resolv.conf` points to `127.0.0.53` (systemd-resolved) which is unreachable from pods

## Root Cause

1. **Talos creates** DNS forwarder at `169.254.116.108` via `forwardKubeDNSToHost: true`
2. **Cilium enables** link-local routing via `hostLegacyRouting: true`
3. **CoreDNS forwards** to `/etc/resolv.conf` (127.0.0.53) instead of `169.254.116.108`
4. **Pods cannot reach** 127.0.0.53 because it's a host-only loopback address
5. **Result**: DNS timeouts (`connection timed out; no servers could be reached`)

## Previously Attempted (Failed) Solutions

### ❌ Attempt 1: Modify kubelet extraArgs
```hcl
kubelet = {
  extraArgs = {
    "resolv-conf" = "/etc/resolv.conf.kubelet"
  }
}
```
**Result**: Broke kubelet startup, etcd never initialized, bootstrap failed

### ❌ Attempt 2: Nest under extraConfig
```hcl
kubelet = {
  extraConfig = {
    resolvConf = "/etc/resolv.conf.kubelet"
  }
}
```
**Result**: Terraform provider validation error (field not recognized)

### ❌ Attempt 3: Direct resolvConf field
```hcl
kubelet = {
  resolvConf = "/etc/resolv.conf.kubelet"
}
```
**Result**: Talos API rejection - "kubelet configuration field 'resolvConf' can't be overridden"

### ❌ Attempt 4: CoreDNS ConfigMap inline manifest
```hcl
cluster = {
  inlineManifests = [
    {
      name = "coredns-forward-to-host-dns"
      contents = <<-EOT
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: coredns
          namespace: kube-system
        data:
          Corefile: |
            forward . 169.254.116.108
      EOT
    }
  ]
}
```
**Result**: Inline manifest deploys alongside default CoreDNS ConfigMap but doesn't override it

## Current Working Solution (Manual)

**After cluster bootstrap, manually patch CoreDNS:**
```bash
kubectl patch configmap coredns -n kube-system --type merge -p '{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health {\n        lameduck 5s\n    }\n    ready\n    log . {\n        class error\n    }\n    prometheus :9153\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    forward . 169.254.116.108 {\n       max_concurrent 1000\n    }\n    cache 30 {\n        denial 9984 30\n    }\n    loop\n    reload\n    loadbalance\n}\n"
  }
}'

kubectl delete pods -n kube-system -l k8s-app=kube-dns
```

**This works** but requires manual intervention after every cluster rebuild.

## Questions for Gemini

### 1. Automated CoreDNS ConfigMap Override

How can I **automatically** configure CoreDNS to forward to `169.254.116.108` during cluster bootstrap?

**Requirements:**
- Must work on fresh cluster deployment (no manual steps)
- Must override the default CoreDNS ConfigMap deployed by Talos
- Must be compatible with Flux GitOps (no out-of-band modifications)

**Options to explore:**
- **Option A**: Flux HelmRelease/Kustomization to patch CoreDNS ConfigMap
- **Option B**: Talos machine config that overwrites CoreDNS deployment
- **Option C**: Custom bootstrap script in Terraform that patches ConfigMap before Flux
- **Option D**: Alternative DNS configuration approach

### 2. Talos Machine Config Limitations

Based on Talos v1.11.5 API:

**What fields CAN be configured in `machine.kubelet`?**
- I know `resolvConf` cannot be overridden
- Can I configure `clusterDNS` servers?
- Are there other DNS-related fields available?

**What is the correct way to inject custom manifests that override Talos defaults?**
- `cluster.inlineManifests` doesn't seem to override existing resources
- Is there a precedence/order mechanism?

### 3. Production Architecture Validation

**Current configuration files:**

1. **Talos Config Generation**: `/Users/sulibot/repos/github/home-ops/terraform/infra/modules/talos_config/main.tf`
   - Lines 100-137: Inline manifest for CoreDNS (currently not working)
   - Line 192: Controlplane kubelet config (currently empty: `kubelet = {}`)
   - Lines 260-265: Worker kubelet config with custom clusterDNS IPs

2. **Cilium Values**: `/Users/sulibot/repos/github/home-ops/kubernetes/apps/networking/cilium/app/values.yaml`
   - Line 60: `hostLegacyRouting: true` (required for link-local routing)

3. **Bootstrap Module**: `/Users/sulibot/repos/github/home-ops/terraform/infra/modules/talos_bootstrap/main.tf`
   - Lines 113-118: SOPS secret creation (working correctly)
   - Flux bootstrap execution (currently times out due to DNS)

**Questions:**
- Is there a better approach than manual CoreDNS patching?
- Should I use Flux to manage CoreDNS instead of Talos inline manifests?
- Is `hostLegacyRouting: true` the correct Cilium setting for this use case?

### 4. Alternative DNS Architectures

**Should I consider:**

1. **External DNS resolver** (bypassing forwardKubeDNSToHost entirely)?
2. **Custom CoreDNS deployment** via Flux that completely replaces Talos-managed CoreDNS?
3. **NodeLocal DNSCache** to provide per-node DNS caching?
4. **Direct pod access** to host DNS via different Cilium routing mode?

### 5. EVPN/VXLAN Interaction

**My network architecture:**
- VMs run on Proxmox with EVPN/VXLAN overlay
- Each VM gets IP from `10.0.101.0/24` subnet
- Talos nodes use FRR BGP to advertise pod/service CIDRs
- Gateway is at `10.0.101.1` (Proxmox host)

**Questions:**
- Does the EVPN/VXLAN layer affect link-local address routing?
- Should DNS resolution happen via EVPN-routed addresses instead?
- Is there a conflict between Cilium's BPF routing and EVPN forwarding?

## Expected Outcome

I need a solution that:
1. ✅ Automatically configures CoreDNS to use `169.254.116.108` on cluster bootstrap
2. ✅ Works with Flux GitOps (all config in Git)
3. ✅ Requires **no manual intervention** on fresh cluster rebuild
4. ✅ Compatible with Talos v1.11.5 API restrictions
5. ✅ Production-ready and maintainable

## Repository Context

You have access to my full repository. Key files:
- `terraform/infra/modules/talos_config/` - Talos machine config generation
- `terraform/infra/modules/talos_bootstrap/` - Cluster bootstrap with Flux
- `kubernetes/apps/networking/cilium/` - Cilium CNI configuration
- `kubernetes/flux/` - Flux GitOps configuration

## Current Status

- Cluster bootstraps successfully
- All nodes become Ready
- Cilium pods are running (some restarting due to PodCIDR assignment delays)
- CoreDNS pods are running but using default config (forward to /etc/resolv.conf)
- DNS resolution from pods **fails** until manual ConfigMap patch applied

## Request

Please provide:
1. **Recommended solution** for automating CoreDNS configuration
2. **Specific implementation** (Flux manifests, Terraform config, etc.)
3. **Explanation** of why this approach overcomes the inline manifest limitation
4. **Validation** that it works with my EVPN/VXLAN/BGP architecture
5. **Any gotchas** or edge cases to watch for

---

## References

- [Talos v1.11.5 Machine Configuration Reference](https://www.talos.dev/v1.11/reference/configuration/)
- [Cilium hostLegacyRouting Documentation](https://docs.cilium.io/en/stable/operations/performance/tuning/#legacy-host-routing)
- [Talos forwardKubeDNSToHost Feature](https://www.talos.dev/v1.11/kubernetes-guides/network/forward-dns-to-host/)
- [CoreDNS Corefile Configuration](https://coredns.io/manual/toc/#configuration)
- [Flux Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)
