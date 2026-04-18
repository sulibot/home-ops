# Bare-Metal PXE Assets

This stack generates RouterOS USB/TFTP-friendly iPXE assets for bare-metal hosts.
RouterOS is the stage-1 DHCP/TFTP endpoint. The generated host scripts then
chain stage-2 boot to upstream HTTP endpoints such as Talos Image Factory or
`boot.netboot.xyz`.

`terragrunt apply` also syncs the rendered assets to RouterOS USB storage and
ensures the UEFI bootloader binaries are present locally first:

- `ipxe.efi` from `https://boot.ipxe.org/x86_64-efi/ipxe.efi`
- `snponly.efi` from `https://boot.ipxe.org/x86_64-efi/snponly.efi`

Current scope:

- `luna01` Talos entry with MAC-based auto-selection
- optional Proxmox/netboot entry for future reuse
- generated assets written to `tmp/pxe/routeros-usb/proxmox`

Intended RouterOS USB layout:

- `usb1/proxmox/ipxe.efi`
- `usb1/proxmox/snponly.efi`
- `usb1/proxmox/autoexec.ipxe`
- `usb1/proxmox/boot.ipxe`
- `usb1/proxmox/luna01.ipxe`

RouterOS remains the PXE/TFTP stage-1 server on `10.10.0.254`. These generated
files are shaped to match that model and can be synced onto `usb1/proxmox`
without depending on another local boot server.
