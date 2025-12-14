# CI/CD Pipeline Design Document

## Architecture Overview

The CI/CD pipeline follows a **multi-stage, parallel processing** architecture with three main phases:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│  Change         │    │  Build & Push    │    │  Update Helm        │
│  Detection      │───▶│  (Parallel)      │───▶│  Charts             │
│                 │    │                  │    │                     │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
```

## Design Decisions

### 1. Change Detection Strategy
**Decision**: Use GitHub Actions `paths-filter` action
**Rationale**: 
- Efficient - only processes changed services
- Reliable - uses Git diff to detect changes
- Flexible - supports complex path patterns

**Implementation**:
```yaml
filters: |
  cart: 'src/cart/**'
  catalog: 'src/catalog/**'
  # ... other services
```

### 2. Parallel Build Strategy
**Decision**: Use GitHub Actions matrix strategy with conditional execution
**Rationale**:
- Faster builds - services build in parallel
- Resource efficient - only builds what changed
- Scalable - easy to add new services

**Implementation**:
```yaml
strategy:
  matrix:
    service: [cart, catalog, checkout, orders, ui]
if: matrix.needs_change == 'true'
```

### 3. Image Tagging Strategy
**Decision**: Dual tagging with commit SHA and "latest"
**Rationale**:
- Traceability - commit SHA links image to exact code version
- Convenience - "latest" tag for development use
- Immutability - SHA tags never change

**Tags**:
- `{ECR_REGISTRY}/retail-store-{service}:{commit-sha}`
- `{ECR_REGISTRY}/retail-store-{service}:latest`

### 4. Helm Chart Update Strategy
**Decision**: In-place updates with automatic commits
**Rationale**:
- GitOps compatible - all changes tracked in Git
- Atomic - chart updates happen immediately after successful builds
- Auditable - clear commit history of deployments

## Component Design

### 1. Change Detection Job
```yaml
detect-changes:
  outputs:
    cart: ${{ steps.changes.outputs.cart }}
    # ... other services
```

**Responsibilities**:
- Analyze Git diff between commits
- Output boolean flags for each service
- Provide input for downstream jobs

### 2. Build and Push Job
```yaml
build-and-push:
  needs: detect-changes
  strategy:
    matrix:
      service: [cart, catalog, checkout, orders, ui]
```

**Responsibilities**:
- Build Docker images for changed services
- Push to ECR with proper tags
- Handle AWS authentication
- Provide build status feedback

### 3. Helm Chart Update Job
```yaml
update-helm-charts:
  needs: [detect-changes, build-and-push]
```

**Responsibilities**:
- Update values.yaml files with new image references
- Commit changes back to repository
- Maintain chart formatting and structure

## Data Flow

### 1. Input Data
- **Git Changes**: File paths that changed between commits
- **Service Mapping**: Which files belong to which services
- **AWS Credentials**: For ECR access
- **GitHub Token**: For repository write access

### 2. Processing Flow
```
Git Push → Change Detection → Service Flags → Build Matrix → ECR Images → Chart Updates → Git Commit
```

### 3. Output Data
- **ECR Images**: Tagged container images in registry
- **Updated Charts**: Modified values.yaml files in repository
- **Build Artifacts**: Logs and status information

## Security Design

### 1. Credential Management
- **AWS Credentials**: Stored in GitHub Secrets
- **GitHub Token**: Automatic token with repository scope
- **ECR Access**: IAM user with ECR push permissions only

### 2. Least Privilege Access
```yaml
permissions:
  contents: write    # For updating Helm charts
  packages: write    # For pushing to ECR
```

### 3. Secret Isolation
- No secrets in workflow files
- Environment variables for runtime injection
- Separate AWS account/region configuration

## Error Handling Design

### 1. Build Failures
- **Strategy**: Fail fast for individual services
- **Impact**: Other services continue building
- **Recovery**: Manual retry or code fix required

### 2. ECR Push Failures
- **Strategy**: Retry with exponential backoff
- **Fallback**: Manual push with same tags
- **Notification**: GitHub Actions status check

### 3. Chart Update Failures
- **Strategy**: Fail entire pipeline if charts can't be updated
- **Rationale**: Inconsistent state between images and charts is dangerous
- **Recovery**: Manual chart update required

## Scalability Design

### 1. Adding New Services
**Process**:
1. Add service to path filters
2. Add service to build matrix
3. Add service to chart update matrix
4. Create ECR repository

**No changes needed**:
- Core workflow logic
- AWS authentication
- Git operations

### 2. Performance Optimization
- **Parallel Execution**: All services build simultaneously
- **Conditional Execution**: Skip unchanged services
- **Caching**: Docker layer caching in GitHub Actions
- **Resource Limits**: Appropriate runner sizes

## Integration Points

### 1. External Systems
- **GitHub**: Source code and workflow execution
- **Amazon ECR**: Container image storage
- **AWS IAM**: Authentication and authorization

### 2. Internal Dependencies
- **Dockerfiles**: Must exist in each service directory
- **Helm Charts**: Must follow standard structure
- **Git Repository**: Must allow workflow commits

## Monitoring and Observability

### 1. Built-in Monitoring
- **GitHub Actions UI**: Real-time build status
- **Workflow Logs**: Detailed execution information
- **Commit History**: Audit trail of chart updates

### 2. Key Metrics
- **Build Duration**: Time from trigger to completion
- **Success Rate**: Percentage of successful builds
- **Change Frequency**: How often services are updated

### 3. Alerting
- **GitHub Notifications**: Email/Slack on failures
- **Status Checks**: PR blocking on build failures
- **ECR Events**: CloudWatch for image push events