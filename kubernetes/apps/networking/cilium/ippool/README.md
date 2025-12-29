# LoadBalancer IP Pools for BGP Advertisement

This directory defines IP pools that Cilium can assign to LoadBalancer services. These IPs are automatically advertised via BGP to the upstream router.

## IP Pool Configuration

**Cluster-101 IP Pools:**
- **IPv4:** `10.101.27.0/24` (10.101.27.0 - 10.101.27.255)
- **IPv6:** `fd00:101:1b::/112` (fd00:101:1b::0 - fd00:101:1b::ffff)

**Important:** These ranges must:
1. NOT overlap with node IPs (10.101.0.0-63, fd00:101::10-23)
2. NOT overlap with pod CIDRs (10.101.244.0/22, fd00:101:244::/60)
3. Be routable by your network infrastructure

## How It Works

1. **Create a LoadBalancer service** with label `bgp-advertise: "true"`
2. **Cilium assigns an IP** from the pool
3. **BGP advertises the IP** to the router
4. **Router routes traffic** to the cluster
5. **Cilium load-balances** to backend pods

## Example: Expose a Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    bgp-advertise: "true"  # Required for BGP advertisement
spec:
  type: LoadBalancer
  # Optional: request specific IP from pool
  # loadBalancerIP: 10.101.27.120
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app: my-app
```

## Example: Ingress Controller

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    bgp-advertise: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.101.27.80  # Reserve IP for ingress
  ports:
    - name: http
      port: 80
    - name: https
      port: 443
  selector:
    app.kubernetes.io/name: ingress-nginx
```

## Verifying BGP Advertisement

Check if IP is being advertised:

```bash
# From cluster
kubectl exec -n kube-system ds/cilium -- cilium bgp routes advertised ipv4 unicast

# From router (Mikrotik)
/routing/route/print where bgp-as-path~"65101"
```

## IP Pool Management

To check available IPs:

```bash
kubectl get ciliumloadbalancerippool -A
```

To check IP assignments:

```bash
kubectl get svc -A -o wide | grep LoadBalancer
```

## Troubleshooting

**Service gets no IP:**
- Check if IP pools are created: `kubectl get ciliumloadbalancerippool -A`
- Verify pool has available IPs
- Check Cilium operator logs: `kubectl logs -n kube-system -l name=cilium-operator`

**IP not advertised via BGP:**
- Verify `bgp-advertise: "true"` label is on the service
- Check BGP session is established: `kubectl exec -n kube-system ds/cilium -- cilium bgp peers`
- Check advertisement config: `kubectl get ciliumbgpadvertisement -A`

**Traffic not reaching service:**
- Verify router has learned the route
- Check Cilium service status: `kubectl exec -n kube-system ds/cilium -- cilium service list`
- Verify firewall rules allow traffic
