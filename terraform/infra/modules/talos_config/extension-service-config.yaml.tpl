apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
configFiles:
  - content: |
      ${replace(frr_config_yaml, "\n", "\n      ")}
    mountPath: /etc/frr/config.default.yaml
  - content: |
      zebra=true
      zebra_options="-n -A 127.0.0.1"
      bgpd=true
      bgpd_options="-A 127.0.0.1"
      staticd=true
      staticd_options="-A 127.0.0.1"
%{ if enable_bfd ~}
      bfdd=true
      bfdd_options="-A 127.0.0.1"
%{ endif ~}
    mountPath: /etc/frr/daemons
  - content: |
      service integrated-vtysh-config
      hostname ${hostname}
    mountPath: /etc/frr/vtysh.conf
