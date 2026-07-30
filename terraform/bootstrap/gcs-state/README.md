# Terraform state GCS bootstrap

This standalone OpenTofu root provisions the backend used by the Terragrunt
units under `terraform/infra`. It intentionally uses isolated local state so
the GCS backend never depends on itself.

Controls:

- regional Standard storage in `us-central1`;
- uniform bucket-level access and enforced public-access prevention;
- Object Versioning with noncurrent generations removed after 90 days;
- 14-day soft delete and no retention lock;
- provider- and OpenTofu-level deletion protection;
- one bucket-scoped custom role with only the permissions required by
  Terragrunt and the GCS backend;
- no service-account keys;
- operator access through ADC plus service-account impersonation;
- GitHub Actions access through an actor- and repository-restricted Workload
  Identity Federation provider.

Apply only after creating an encrypted copy of this directory's local state:

```bash
cd terraform/bootstrap/gcs-state
tofu init
tofu plan -out=bootstrap.tfplan
tofu apply bootstrap.tfplan
```

The local state and plan can contain sensitive infrastructure metadata. They
are ignored by Git and must be encrypted with the repository's age recovery
recipient before copying them outside this workstation.
