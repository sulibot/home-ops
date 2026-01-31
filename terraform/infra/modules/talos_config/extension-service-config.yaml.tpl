apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      ${replace(frr_config_yaml, "\n", "\n      ")}
    mountPath: /usr/local/etc/frr/config.yaml
  - content: |
      zebra=true
      zebra_options="-A 127.0.0.1"
      bgpd=true
      bgpd_options=""
      staticd=true
      staticd_options="-A 127.0.0.1"
%{ if enable_bfd ~}
      bfdd=true
      bfdd_options="-A 127.0.0.1"
%{ endif ~}
    # mountPath: /var/lib/frr/daemons
    mountPath: /usr/local/etc/frr/daemons
  - content: |
      service integrated-vtysh-config
      hostname ${hostname}
    # mountPath: /var/lib/frr/vtysh.conf
    mountPath: /usr/local/etc/frr/vtysh.conf
