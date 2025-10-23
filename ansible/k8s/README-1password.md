# 1Password Connect Credentials Automation

This directory contains Ansible automation for managing 1Password Connect credentials for External Secrets in your Kubernetes cluster.

## Overview

The automation handles the complete lifecycle of updating 1Password Connect credentials:

1. **Fetch** credentials from 1Password vault using Service Account
2. **Create** Kubernetes secret with the credentials
3. **Encrypt** the secret using SOPS
4. **Commit** and push changes to git
5. **Deploy** via Flux CD
6. **Verify** the deployment is working

## Prerequisites

### Required Tools

Install these tools before running the automation:

```bash
# macOS with Homebrew
brew install 1password-cli sops kubectl fluxcd/tap/flux ansible git
```

### 1Password Setup

#### Step 1: Store Connect Credentials in 1Password

First, you need to generate and store your Connect Server credentials:

1. Go to [my.1password.com](https://my.1password.com)
2. Navigate to **Integrations** → **1Password Connect**
3. Click **Create Server**
4. Download the `1password-credentials.json` file
5. Store this file in your 1Password vault:
   - Vault: `Kubernetes`
   - Item name: `1password-connect`
   - Field name: `credentials`
   - Store the entire JSON content

#### Step 2: Create Service Account Token

Create a Service Account for the automation:

1. In 1Password, go to **Integrations** → **Service Accounts**
2. Click **Create Service Account**
3. Name it: `kubernetes-automation`
4. Grant access to the `Kubernetes` vault (Read access)
5. Copy the token (starts with `ops_...`)
6. Set it as an environment variable:

```bash
export OP_SERVICE_ACCOUNT_TOKEN='ops_...'

# Make it persistent (add to your shell profile)
echo 'export OP_SERVICE_ACCOUNT_TOKEN="ops_..."' >> ~/.zshrc
source ~/.zshrc
```

### Kubernetes Setup

Ensure kubectl is configured and pointing to the correct cluster:

```bash
# Check current context
kubectl config current-context

# Switch context if needed
kubectl config use-context your-cluster-name
```

## Usage

### Quick Start

The easiest way to run the automation is using the helper script:

```bash
cd ansible/k8s
./update-1password.sh
```

The script will:
- ✅ Check all requirements
- ✅ Verify environment variables
- ✅ Confirm kubectl context
- ✅ Run the Ansible playbook
- ✅ Display the results

### Command Options

```bash
# Normal run with all checks
./update-1password.sh

# Check requirements only (don't run)
./update-1password.sh --check

# Verbose output for debugging
./update-1password.sh --verbose

# Show help
./update-1password.sh --help
```

### Running Ansible Directly

If you prefer to run Ansible directly:

```bash
cd ansible/k8s
ansible-playbook playbooks/update-1password-credentials.yaml
```

With verbose output:

```bash
ansible-playbook playbooks/update-1password-credentials.yaml -vv
```

## Configuration

### Customizing Variables

You can override variables in the playbook by creating an extra vars file:

```yaml
# vars/1password-custom.yaml
op_vault: MyCustomVault
op_item: my-connect-server
pod_ready_timeout: 180
```

Then run with:

```bash
ansible-playbook playbooks/update-1password-credentials.yaml \
  -e @vars/1password-custom.yaml
```

### Available Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `op_vault` | `Kubernetes` | 1Password vault name |
| `op_item` | `1password-connect` | Item name in vault |
| `op_field` | `credentials` | Field name containing credentials |
| `k8s_namespace` | `external-secrets` | Kubernetes namespace |
| `k8s_secret_name` | `onepassword-secret` | Secret name |
| `clustersecretstore_name` | `onepassword-connect` | ClusterSecretStore name |
| `pod_ready_timeout` | `120` | Seconds to wait for pod |
| `css_ready_timeout` | `120` | Seconds to wait for ClusterSecretStore |
| `flux_timeout` | `180` | Seconds for Flux operations |

## Automation and Scheduling

### Set Up Automatic Renewal

Create a cron job to automatically renew credentials before they expire:

```bash
# Edit crontab
crontab -e

# Add this line to run on the 1st of every month at 2 AM
0 2 1 * * cd /Users/sulibot/repos/github/home-ops/ansible/k8s && ./update-1password.sh >> /tmp/1password-update.log 2>&1
```

### Launchd (macOS)

For better macOS integration, use launchd:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.homeops.1password-update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/sulibot/repos/github/home-ops/ansible/k8s/update-1password.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OP_SERVICE_ACCOUNT_TOKEN</key>
        <string>ops_...</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Day</key>
        <integer>1</integer>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/1password-update.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/1password-update-error.log</string>
</dict>
</plist>
```

Save to `~/Library/LaunchAgents/com.homeops.1password-update.plist` and load:

```bash
launchctl load ~/Library/LaunchAgents/com.homeops.1password-update.plist
```

## Troubleshooting

### Common Issues

#### 1. "OP_SERVICE_ACCOUNT_TOKEN is not set"

**Solution**: Set the environment variable:

```bash
export OP_SERVICE_ACCOUNT_TOKEN='ops_...'
```

Make it persistent by adding to `~/.zshrc` or `~/.bash_profile`.

#### 2. "Failed to fetch credentials from 1Password"

**Possible causes**:
- Service Account token is invalid or expired
- The item doesn't exist in the vault
- Service Account doesn't have access to the vault

**Solution**: Verify the item exists:

```bash
op item get 1password-connect --vault Kubernetes
```

#### 3. "Pod is not ready"

**Check pod logs**:

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=onepassword -c api
```

**Common causes**:
- Credentials are malformed
- Credentials have expired
- Network connectivity issues

#### 4. "ClusterSecretStore is not Ready"

**Check status**:

```bash
kubectl describe clustersecretstore onepassword-connect
```

**Common causes**:
- onepassword service is not accessible
- Credentials are invalid
- The vault "Kubernetes" doesn't exist in 1Password

### Debug Mode

Run with verbose Ansible output:

```bash
./update-1password.sh --verbose
```

Or directly:

```bash
ansible-playbook playbooks/update-1password-credentials.yaml -vvv
```

### Manual Verification

Check each component manually:

```bash
# 1. Check if secret exists and is encrypted
cat kubernetes/manifests/apps/external-secrets/external-secrets/stores/secret.sops.yaml | grep "sops:"

# 2. Check if secret is deployed
kubectl get secret onepassword-secret -n external-secrets

# 3. Check onepassword pod
kubectl get pods -n external-secrets -l app.kubernetes.io/name=onepassword

# 4. Check ClusterSecretStore
kubectl get clustersecretstore onepassword-connect

# 5. Test fetching a secret from 1Password
kubectl get externalsecret -A
```

## Security Considerations

1. **Service Account Token**: Store securely, never commit to git
2. **SOPS Encryption**: Ensures credentials are encrypted at rest in git
3. **Age Key**: Required for SOPS decryption, should be backed up securely
4. **Credential Rotation**: Credentials expire periodically, use automation to renew

## Credential Lifecycle

### When to Update

1Password Connect credentials typically expire after **~6 months**. Update when:

- ✅ **Scheduled**: Set up monthly automation (credentials last longer than this)
- ⚠️  **On Error**: If you see authentication failures in logs
- 🔄 **After Rotation**: If you regenerate the Connect Server in 1Password

### Signs Credentials Need Updating

Watch for these errors in logs:

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=onepassword -c api
```

Look for:
- `401 Unauthorized`
- `Invalid bearer token`
- `JWT expired`

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Update 1Password Credentials

on:
  schedule:
    - cron: '0 2 1 * *'  # Monthly on the 1st at 2 AM
  workflow_dispatch:  # Manual trigger

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install tools
        run: |
          brew install 1password-cli sops kubectl fluxcd/tap/flux ansible

      - name: Configure kubectl
        run: |
          echo "${{ secrets.KUBECONFIG }}" > ~/.kube/config

      - name: Run automation
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          cd ansible/k8s
          ./update-1password.sh
```

## Files Overview

```
ansible/k8s/
├── playbooks/
│   └── update-1password-credentials.yaml  # Main Ansible playbook
├── update-1password.sh                     # Helper script
└── README-1password.md                     # This file
```

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review Ansible playbook output for specific errors
3. Check External Secrets operator logs
4. Verify 1Password Service Account permissions

## References

- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [1Password Connect](https://developer.1password.com/docs/connect/)
- [External Secrets Operator](https://external-secrets.io/)
- [SOPS](https://github.com/getsops/sops)
- [Flux CD](https://fluxcd.io/)
