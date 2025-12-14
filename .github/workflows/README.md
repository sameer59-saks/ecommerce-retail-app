# GitHub Workflow for Retail Store Application

This directory contains the automated CI/CD workflow for the retail store microservices application.

## Automatic CI/CD Pipeline (`ci-cd.yml`)

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` branch

**Features:**
- **Change Detection**: Automatically detects which services have changed using path filters
- **Parallel Builds**: Only builds and pushes Docker images for services that have changes
- **ECR Integration**: Pushes images to Amazon ECR with commit SHA tags
- **Helm Chart Updates**: Automatically updates values.yaml files with new image tags

**Services Monitored:**
- `cart` (Java/Spring Boot)
- `catalog` (Go)
- `checkout` (Node.js/NestJS)
- `orders` (Java/Spring Boot)
- `ui` (Java/Spring Boot)

## Setup Requirements

### 1. AWS Secrets

Add these secrets to your GitHub repository:

```
AWS_ACCESS_KEY_ID       # AWS access key for ECR access
AWS_SECRET_ACCESS_KEY   # AWS secret key for ECR access
AWS_ACCOUNT_ID          # Your AWS account ID (12-digit number)
```

### 2. ECR Repository

Create a single ECR repository for all services:

```bash
aws ecr create-repository --repository-name ecommerce-store --region us-west-2
```

### 3. GitHub Token Permissions

Ensure the `GITHUB_TOKEN` has permissions to:
- Read repository contents
- Write to repository (for updating Helm charts)
- Create commits and push changes

## Workflow Behavior

### Change Detection Logic

The workflow uses path filters to detect changes:
- `src/cart/**` → Triggers cart service build
- `src/catalog/**` → Triggers catalog service build
- `src/checkout/**` → Triggers checkout service build
- `src/orders/**` → Triggers orders service build
- `src/ui/**` → Triggers ui service build

### Image Tagging Strategy

- **Service + Latest**: Tagged as `{service}-latest` (e.g., `cart-latest`)
- **Service + Commit SHA**: Tagged as `{service}-{commit-sha}` for traceability
- **Single Repository**: All services use the same ECR repository with different tags

### Helm Chart Updates

The workflow automatically updates:
- `image.repository`: Points to your ECR registry
- `image.tag`: Updates to the new commit SHA

Example update in `values.yaml`:
```yaml
image:
  repository: 463470973994.dkr.ecr.us-west-2.amazonaws.com/ecommerce-store
  tag: "cart-a1b2c3d4e5f6789012345678901234567890abcd"
```

## Usage

### Automatic Deployment
1. Make changes to any service in `src/` directory
2. Commit and push to `main` or `develop`
3. Workflow automatically detects changes and deploys affected services
4. Check GitHub Actions tab to monitor progress

## Monitoring

- Check GitHub Actions tab for workflow status
- Each job shows detailed logs for debugging
- Failed builds will show specific error messages
- ECR console shows pushed images with tags

## Customization

### Adding New Services
1. Add service path to `detect-changes` job filters
2. Add service to build matrix in `build-and-push` job
3. Add service to update matrix in `update-helm-charts` job

### Changing AWS Region
Update the `AWS_REGION` environment variable in the workflow file.

### Custom Image Repositories
Modify the `ECR_REPOSITORY` naming pattern in the build step.