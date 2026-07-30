# Authentik brand assets

`frosted-theme.css` and `frosted-flow.jpg` are vendored from
[`iUnstable0/authentik-frosted-theme`](https://github.com/iUnstable0/authentik-frosted-theme)
at commit `06c32287fefdb4e24ba4e9b0b3adc02d97be59a6`.

Upstream SHA-256 checksums:

- `frosted-theme.css`: `1152c6fe31373a287ab9b627c878d39b6b7e2051b1ce0681ce1ad3812e9762ec`
- `frosted-flow.jpg`: `57508cb4cef402dade77bc46a7e2f401ff4762e2b4f6681f05a21148651f83b1`

`logo.svg` and `logo-192.png` are exact copies of the repository's canonical
`images/logo.svg` and `images/logo-192.png`. Keep the copies synchronized when
the canonical logo changes.

The assets are generated into the `authentik-brand-assets` ConfigMap and
mounted read-only at `/data/media/public/branding` in both the server and
worker. The Brand blueprint reads the CSS with Authentik's `!File` tag and
references the images using Authentik media paths.

Flux excludes common image extensions from GitRepository artifacts by default.
The adjacent `.sourceignore` explicitly includes the required JPG and PNG.
