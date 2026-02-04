# Install schematic for actual system
# Full configuration with all kernel args and extensions

locals {
  # Pull versions so we can tag extensions correctly
  # Explicit path so it works from .terragrunt-cache during run-all
  versions = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals

  # Kernel args for production system (metal platform)
  install_kernel_args = [
    "talos.platform=metal",  # Use metal platform for bare metal/VM installation
    "-init_on_alloc",        # Less security, faster performance
    "-init_on_free",         # Less security, faster performance
    "-selinux",              # Less security, faster performance
    "apparmor=0",            # Less security, faster performance
    "i915.disable_display=1",  # Disable display subsystem for compute-only (Plex transcoding)
    "i915.enable_guc=0",     # Disable GuC firmware loading (fixes VM boot hang)
    "i915.force_probe=4680", # Force enable Alder Lake iGPU support
    "init_on_alloc=0",       # Less security, faster performance
    "init_on_free=0",        # Less security, faster performance
    "intel_iommu=on",        # PCI Passthrough
    "iommu=pt",              # PCI Passthrough
    "mitigations=off",       # Less security, faster performance
    "module_blacklist=igc",  # Disable onboard NIC
    "security=none",         # Less security, faster performance
    "sysctl.kernel.kexec_load_disabled=1",  # Meteor Lake CPU & Intel iGPU
    "talos.auditd.disabled=1",  # Less security, faster performance
  ]

  # Install extensions for Talos v1.12.1
  # Official Siderolabs extensions with pinned digests
  # Extracted via: crane export ghcr.io/siderolabs/extensions:v1.12.1 - | tar x -O image-digests
  install_system_extensions = [
    "ghcr.io/siderolabs/i915:20251125-v1.12.1@sha256:fb89c85a04ecb85abaec9d400e03a1628bf68aef3580e98f340cbe8920a6e4ed",
    "ghcr.io/siderolabs/qemu-guest-agent:10.2.0@sha256:b2843f69e3cd31ba813c1164f290ebbfddd239d53b3a0eeb19eb2f91fec6fed7",
    "ghcr.io/siderolabs/crun:1.26@sha256:5910e8e068a557afd727344649e0e6738ba53267c4339213924d4349567fe8d4",
    "ghcr.io/siderolabs/ctr:v2.1.5@sha256:67337f841b2ad13fbf43990e735bc9e61deafb91ab5d4fde42392b49f58cbe00",
  ]

  # FRR extension - using your fork
  # Published from: /Users/sulibot/repos/github/frr-talos-extension
  # Available at: https://github.com/sulibot/frr-talos-extension/pkgs/container/frr-talos-extension
  # v1.7.20: Add next-hop-self on upstream peer - fixes IPv6 LB routes not reaching PVE. FRR was not auto-rewriting next-hop on eBGP when stored next-hop (from set ipv6 next-hop global) matched the peer address.
  # v1.7.19: Fix template override - docker-start tmpfs populate was overwriting ExtensionServiceConfig mount. Add override check after defaults copy. Replace next_hop_self/peer-address with explicit ip_next_hop/ipv6_next_hop gateway rewrite (FRR 10.x does not support peer-address).
  # v1.7.18: Fix next-hop peer-address for IPv6 route-maps - remove Jinja2 dashes that fought trim_blocks=True, causing 'set ipv6 next-hop peer-address!' concatenation
  # v1.7.17: INCOMPLETE - fixed endif dash but missed {%- else -%} stripping IPv6 branch newline
  # v1.7.16: INCOMPLETE - correct logic but Jinja2 whitespace created malformed config
  # v1.7.15: Fix RFC5549 next-hop rewriting - always use IPv6 next-hop commands for all BGP sessions. Fixes LoadBalancer route advertisement from Cilium to FRR to PVE.
  # v1.7.14: Merge duplicate router bgp sections - fixes bgp listen range being lost when Cilium and upstream use same ASN
  # v1.7.13: Fix BGP peer-group creation order - create peer-group before applying listen range
  # v1.7.12: Use BGP listen range (fd00::/8) for flexible Cilium peering - no hardcoded IPs, ASN-based validation
  # v1.7.11: Remove VRF isolation - FRR and Cilium now in same routing domain
  # v1.7.7: Fix MP-BGP for upstream peers - remove invalid syntax, fix IPv6 address-family activation. Enables upstream BGP to PVE VRF.
  # v1.7.6: Add tmpfs mounts for /var/run/frr, /var/lib/frr, /var/log/frr - fixes FRR daemon startup
  # v1.7.5: Use tmpfs overlay for /etc/frr - makes config directory writable in-memory without host mounts
  # v1.7.3: Use container's internal /run for writable paths - fixes daemon startup without host bind mounts
  # v1.7.1: Mount /run/frr-* from host into container via frr.yaml. Requires machine config to create host dirs.
  # v1.7.0: Use bind mounts for writable directories (more reliable than symlinks), add /var/log/frr support
  # v1.6.9: Create writable FRR runtime directories in /run tmpfs - fixes daemon startup failures
  # v1.6.8: Fix read-only filesystem error - use /run/config.json instead of /tmp/config.json
  # v1.6.7: Add IPv4 veth address configuration for dual-stack Cilium BGP peering
  # v1.2.7: Fix Dockerfile - restore multi-stage build for proper Talos extension format
  # v1.2.6: Updated with latest changes including Dockerfile and configuration updates
  # v1.2.5: Fix veth creation - use atomic netns syntax to properly create cross-namespace veth pair
  # v1.2.4: Updated configuration with latest changes
  # v1.2.3: Rebuild with current configuration for testing
  # v1.2.2: Fix namespace access - use nsenter instead of ip netns exec for accessing host namespace
  # v1.2.1: Fix syntax error in docker-start script (fi -> done for IPv6 loop)
  # v1.2.0: Implement network namespace isolation for FRR - resolves local address detection issues
  # v1.1.43: Remove update-source directives from Cilium neighbors to work around hostNetwork local address detection
  # v1.1.42: Fix loopback prefix-list syntax - add /32 and /128 prefix lengths to host addresses
  # v1.1.41: Replace MP-BGP with dual-stack traditional BGP - separate IPv4/IPv6 sessions for better Cilium compatibility
  # v1.1.40: Remove invalid passive directives from address-family blocks - passive is neighbor-level only
  # v1.1.39: Fix Cilium neighbor template - use bgp.cilium.peering.ipv6 config paths consistently
  install_custom_extensions = [
    "ghcr.io/sulibot/frr-talos-extension:v1.7.20@sha256:a361476c4458d4fee84d38c2a793ea44e0dc5b6fd10f568e71d74289f5fb6184",
  ]
}
