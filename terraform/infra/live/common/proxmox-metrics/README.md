# Proxmox Metrics

This stack is intentionally empty because live Proxmox currently has no cluster
metrics server configured.

Host metrics remain Ansible-owned through node_exporter/SNMP. Add entries here
only if Proxmox should push metrics to InfluxDB, Graphite, or OpenTelemetry.
