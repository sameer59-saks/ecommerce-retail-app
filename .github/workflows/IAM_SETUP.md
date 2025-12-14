# IAM Setup for GitHub Actions ECR Access

## Security Best Practices Applied

### 1. **Principle of Least Privilege**
- Only permissions needed for ECR push operations
- No administrative or broad AWS permissions
- Resource-specific access only

### 2. **Minimal Permissions Required**

#### ECR Authentication:
- `ecr:GetAuthorizationToken` - Required to authenticate with ECR

#### ECR Repository Operations:
- `ecr:BatchCheckLayerAvailability` - Check if image layers exist
- `ecr:GetDownloadUrlForLayer` - Download existing layers (for caching)
- `ecr:BatchGetImage` - Pull existing images (for layer reuse)
- `ecr:InitiateLayerUpload` - Start uploading new layers
- `ecr:UploadLayerPart` - Upload layer chunks
- `ecr:CompleteLayerUpload` - Finish layer upload
- `ecr:PutImage` - Push the final image manifest

## Step-by-Step Setup

### 1. Create IAM User
```bash
aws iam create-user --user-name github-actions-ecr-user
```

### 2. Create IAM Policy
```bash
# Replace YOUR_ACCOUNT_ID with your actual AWS account ID
aws iam create-policy \
  --policy-name GitHubActionsECRPolicy \
  --policy-document file://.github/workflows/iam-policy.json
```

### 3. Attach Policy to User
```bash
# Replace YOUR_ACCOUNT_ID with your actual AWS account ID
aws iam attach-user-policy \
  --user-name github-actions-ecr-user \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActionsECRPolicy
```

### 4. Create Access Keys
```bash
aws iam create-access-key --user-name github-actions-ecr-user
```

**Important**: Save the Access Key ID and Secret Access Key - you'll need them for GitHub Secrets.

## Alternative: Using AWS CLI with Policy File

### 1. Update the Policy File
Replace `YOUR_ACCOUNT_ID` in `iam-policy.json` with your actual AWS account ID:

```json
"Resource": "arn:aws:ecr:us-east-1:123456789012:repository/retail-store"
```

### 2. Create Everything at Once
```bash
# Create user
aws iam create-user --user-name github-actions-ecr-user

# Create policy (update YOUR_ACCOUNT_ID first)
aws iam create-policy \
  --policy-name GitHubActionsECRPolicy \
  --policy-document file://.github/workflows/iam-policy.json

# Attach policy (replace YOUR_ACCOUNT_ID)
aws iam attach-user-policy \
  --user-name github-actions-ecr-user \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActionsECRPolicy

# Create access keys
aws iam create-access-key --user-name github-actions-ecr-user
```

## Security Considerations

### ✅ **What This Policy ALLOWS:**
- Authenticate with ECR
- Push images to the specific `retail-store` repository
- Pull existing layers for efficient builds

### ❌ **What This Policy DENIES:**
- Access to other ECR repositories
- ECR repository management (create/delete repositories)
- Access to other AWS services
- Administrative permissions

### 🔒 **Additional Security Measures:**

#### 1. **Resource-Specific Access**
The policy only grants access to your specific ECR repository:
```json
"Resource": "arn:aws:ecr:us-east-1:YOUR_ACCOUNT_ID:repository/retail-store"
```

#### 2. **No Wildcard Permissions**
Except for `GetAuthorizationToken` which requires `"Resource": "*"` by AWS design.

#### 3. **Region-Specific**
Policy is locked to `us-east-1` region only.

#### 4. **No Delete Permissions**
User cannot delete images or repositories.

## Verification

### Test the Setup
```bash
# Configure AWS CLI with the new credentials
aws configure --profile github-actions

# Test ECR access
aws ecr describe-repositories --repository-names retail-store --profile github-actions

# Test authentication
aws ecr get-login-password --region us-east-1 --profile github-actions
```

## Troubleshooting

### Common Issues:

1. **"User not authorized"** - Check policy attachment
2. **"Repository not found"** - Ensure ECR repository exists
3. **"Invalid credentials"** - Verify access keys in GitHub Secrets

### Debug Commands:
```bash
# Check user policies
aws iam list-attached-user-policies --user-name github-actions-ecr-user

# Check policy details
aws iam get-policy-version --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActionsECRPolicy --version-id v1
```

## Cleanup (if needed)
```bash
# Detach policy
aws iam detach-user-policy \
  --user-name github-actions-ecr-user \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActionsECRPolicy

# Delete access keys (list them first)
aws iam list-access-keys --user-name github-actions-ecr-user
aws iam delete-access-key --user-name github-actions-ecr-user --access-key-id AKIA...

# Delete user
aws iam delete-user --user-name github-actions-ecr-user

# Delete policy
aws iam delete-policy --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActionsECRPolicy
```