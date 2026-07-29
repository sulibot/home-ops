# OpenBao GCP KMS root of trust

This unit creates only the independent GCP Cloud KMS resources used by the
OpenBao auto-unseal seal:

- one global software KMS key with a single active version;
- destroy protection in both Google provider and OpenTofu lifecycle controls;
- one service account;
- one custom role containing the three permissions OpenBao requires;
- a key-scoped IAM binding.

The GCP project and billing link are intentionally outside this state. Create a
dedicated personal project, not a work subscription:

```bash
gcloud auth login
gcloud billing accounts list

export OPENBAO_GCP_KMS_PROJECT_ID=sulibot-openbao-kms
gcloud projects create "$OPENBAO_GCP_KMS_PROJECT_ID" \
  --name="SuliBot OpenBao KMS"
gcloud billing projects link "$OPENBAO_GCP_KMS_PROJECT_ID" \
  --billing-account=BILLING_ACCOUNT_ID
```

Then provision the key and restricted service account:

```bash
cd terraform/infra/live/cloud/openbao-kms
terragrunt apply
```

Do not create `google_service_account_key` in OpenTofu because its private key
would be retained in state. Create one key locally, upload it directly to a
1Password Document, and remove the temporary file:

```bash
umask 077
credential_file="$(mktemp)"
trap 'rm -f -- "$credential_file"' EXIT

gcloud iam service-accounts keys create "$credential_file" \
  --project="$OPENBAO_GCP_KMS_PROJECT_ID" \
  --iam-account="openbao-auto-unseal@$OPENBAO_GCP_KMS_PROJECT_ID.iam.gserviceaccount.com"

op document create "$credential_file" \
  --vault Kubernetes \
  --title openbao-gcp-kms \
  --file-name openbao-gcp-kms.json
```

The OpenBao Terragrunt unit performs a read-only KMS preflight with this
credential before creating any LXCs.

Protect the Google account with MFA and billing alerts. Recovery shares do not
replace this KMS key: permanently destroying every usable key version makes
OpenBao data and snapshots unrecoverable.

The key deliberately has no automatic cryptographic rotation. GCP bills each
active software key version, old seal ciphertext can require an older version,
and rotating the KMS key does not revoke a leaked service-account credential.
Rotate the restricted service-account JSON at least annually and after any
suspected exposure. Add a new KMS version only for an actual cryptographic
rotation event with a tested OpenBao seal-migration and snapshot-recovery plan.
