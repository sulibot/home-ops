# Proxmox Access

This stack adopts the existing Proxmox Terraform service identity:

- user: `terraform@pve`
- role: `Terraform`
- root ACL: `/?terraform@pve?Terraform`
- provider token metadata: `terraform@pve!provider`

The token value is not retrievable from Proxmox after creation. Importing this
resource tracks token metadata only; the actual provider secret must remain in
the encrypted credentials file or the execution environment.

Initial adoption commands:

```sh
terragrunt import proxmox_virtual_environment_role.this Terraform
terragrunt import proxmox_virtual_environment_user.this terraform@pve
terragrunt import proxmox_acl.root '/?terraform@pve?Terraform'
terragrunt import proxmox_user_token.provider 'terraform@pve!provider'
terragrunt plan
```
