# Gomplate Kubernetes App Templating

This project uses `gomplate` to generate Kubernetes manifests from Go-based templates.

## Usage

### 1. Scaffold a new app
```bash
task scaffold-default-values NAME=radarr NAMESPACE=media
```

### 2. Render manifests from values.yaml
```bash
task create-app NAME=radarr NAMESPACE=media
```

### 3. Render all
```bash
task render-all
```

### 4. Validate
```bash
task validate-all
```

## Template files
All template files are in `.taskfiles/app/*.tmpl`.

## Requirements
- gomplate
- yamllint
- kubeconform
