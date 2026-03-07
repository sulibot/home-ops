apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: __CLUSTER_NAME__
  namespace: __CLUSTER_NS__
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  backup:
    volumeSnapshot:
      className: csi-rbd-rbd-vm-snapclass
      snapshotOwnerReference: backup
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: postgres-vectorchord-backup
  bootstrap:
    recovery:
      database: immich
      owner: immich
      volumeSnapshots:
        storage:
          name: __SNAP_NAME__
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  managed:
    roles:
      - name: atuin
        login: true
        ensure: present
        passwordSecret:
          name: atuin-pg-password
      - name: authentik
        login: true
        ensure: present
        passwordSecret:
          name: authentik-pg-password
      - name: firefly
        login: true
        ensure: present
        passwordSecret:
          name: firefly-pg-password
      - name: paperless
        login: true
        ensure: present
        passwordSecret:
          name: paperless-pg-password
  storage:
    resizeInUseVolumes: true
    size: __CNPG_STORAGE_SIZE__
    storageClass: csi-rbd-rbd-vm-sc-retain
