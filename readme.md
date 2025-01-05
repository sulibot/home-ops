# Kubernetes Deployment with Flux and Helm

This repository is designed to manage Kubernetes deployments for both staging and production environments using Flux and Helm. It provides a structured approach to manage and promote changes from staging to production with environment-specific overrides.

***

## Managing Deployments: Staging and Production

### Workflow Overview

1. **Branch-Based Configuration**:

   * Each environment (`staging` and `production`) is managed on a separate branch.

   * Environment-specific Helm values files and Flux configurations are maintained in their respective branches.

   * Example branches:

     * `staging`: Contains all changes for testing.
     * `production`: Contains only validated and approved configurations.

2. **Testing in Staging**:

   * Changes are first applied to the `staging` branch.
   * Verify the application's behavior in the staging environment.

3. **Promoting to Production**:

   * After successful testing, merge the changes from the `staging` branch into the `production` branch.
   * Flux will automatically apply the changes to the production cluster.

***

## How the Repository is Structured

```
graphql
Copy code
kubernetes/
    base/                           # Common configurations shared across environments
        apps/                       # Applications (Sonarr, Radarr, etc.)
            media/
                pvc-media.yaml      # Shared PersistentVolumeClaim for media storage
                sonarr/
                    pvc-config.yaml # PVC for Sonarr's /config directory
                    helmrelease.yaml # HelmRelease for Sonarr
                    kustomization.yaml
        infrastructure/             # Networking and infrastructure (e.g., Nginx)
            network/
                nginx/
                    helmrelease.yaml
                    kustomization.yaml
        core/                       # Core services (e.g., Cilium, Ceph-CSI)
            network/
                cilium/
                    namespace.yaml
                    helmrelease.yaml
                    kustomization.yaml
    shared/                         # Shared Helm repositories and resources
        repo/
            helm/
                nginx-helmrepository.yaml
                cilium-helmrepository.yaml
    clusters/
        staging/                    # Cluster-specific configurations for staging
            apps.yaml
            infrastructure.yaml
            kustomization.yaml
        production/                 # Cluster-specific configurations for production
            apps.yaml
            infrastructure.yaml
            kustomization.yaml
```

***

## Managing Staging Deployments

1. **Set Up the Staging Environment**:

   * Deploy the base configurations using the `staging` branch:

     ```
     bash
     Copy code
     flux apply -k ./clusters/staging
     ```

2. **Modify and Test Changes**:

   * Update the appropriate `values.yaml` files under `base/apps` or `staging-overrides` for your application.
   * Example: Update `kubernetes/base/apps/media/sonarr/helmrelease.yaml` to modify Sonarr settings.

3. **Verify Changes in Staging**:

   * Monitor the deployment using `kubectl`:

     ```
     bash
     Copy code
     kubectl get pods -n media
     ```

4. **Iterate Until Validation**:

   * Repeat modifications until the application works as intended.

***

## Promoting Changes to Production

1. **Merge Staging to Production**:

   * Once changes are validated, merge the `staging` branch into the `production` branch:

     ```
     bash
     Copy code
     git checkout production
     git merge staging
     git push origin production
     ```

2. **Deploy Production Configurations**:

   * Flux automatically applies the changes to the production environment:

     ```
     bash
     Copy code
     flux apply -k ./clusters/production
     ```

3. **Verify Production Deployment**:

   * Ensure the production environment reflects the changes:

     ```
     bash
     Copy code
     kubectl get pods -n media
     ```

***

## Managing Environment-Specific Overrides

* **Staging Environment**:

  * Override files are stored under `staging-overrides/`.
  * Example: `kubernetes/staging-overrides/apps/media/sonarr/values.yaml`.

* **Production Environment**:

  * Overrides are managed in the `production` branch.
  * Flux applies the appropriate configurations from the branch automatically.

***

## Deployment Lifecycle Example

1. **Add a Feature**:

   * Update `values.yaml` or `helmrelease.yaml` for the desired application in the `staging` branch.

2. **Deploy to Staging**:

   * Apply configurations in `clusters/staging`:

     ```
     bash
     Copy code
     flux apply -k ./clusters/staging
     ```

3. **Test and Validate**:

   * Confirm the application is working as expected.

4. **Promote to Production**:

   * Merge the `staging` branch into `production` and deploy:

     ```
     bash
     Copy code
     git checkout production
     git merge staging
     flux apply -k ./clusters/production
     ```

***

## Key Principles

1. **Isolation of Environments**:
   * `staging` is for testing; `production` is for live deployments.
2. **Promotion via Git**:
   * Ensure changes are thoroughly tested before merging into `production`.
3. **Centralized Configurations**:
   * Shared configurations (e.g., Helm repositories) are stored in `shared/repo/helm/`.

***

## Contributing

* Submit pull requests for new features or fixes.
* Ensure all changes are validated in `staging` before merging into `production`.

***

## License

This repository is licensed under the MIT License. See the `LICENSE` file for details.
