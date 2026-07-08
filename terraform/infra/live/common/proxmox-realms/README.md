# Proxmox Realms

This stack adopts API-level Proxmox authentication realms.

The current `idm` OpenID realm is imported without managing the write-only client
secret. Rotate or adopt that secret later with `client_key_wo` and an explicit
version counter if needed.
