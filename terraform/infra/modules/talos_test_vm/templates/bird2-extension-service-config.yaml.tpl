apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: bird2
configFiles:
  - content: |
      ${replace(bird2_config_conf, "\n", "\n      ")}
    mountPath: /usr/local/etc/bird.conf
