#!/bin/bash

# AWS Setup Script for GitHub Actions ECR Access
# Account ID: 463470973994

set -e

echo "🚀 Setting up AWS IAM user for GitHub Actions..."

# 1. Create ECR repository if it doesn't exist
echo "📦 Creating ECR repository..."
aws ecr create-repository --repository-name retail-store --region us-east-1 2>/dev/null || echo "Repository already exists"

# 2. Create IAM user
echo "👤 Creating IAM user: github-actions-ecr-user..."
aws iam create-user --user-name github-actions-ecr-user 2>/dev/null || echo "User already exists"

# 3. Create IAM policy
echo "📋 Creating IAM policy..."
aws iam create-policy \
  --policy-name GitHubActionsECRPolicy \
  --policy-document file://.github/workflows/iam-policy.json 2>/dev/null || echo "Policy already exists"

# 4. Attach policy to user
echo "🔗 Attaching policy to user..."
aws iam attach-user-policy \
  --user-name github-actions-ecr-user \
  --policy-arn arn:aws:iam::463470973994:policy/GitHubActionsECRPolicy

# 5. Create access keys
echo "🔑 Creating access keys..."
ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name github-actions-ecr-user --output json)

# Extract access key details
ACCESS_KEY_ID=$(echo $ACCESS_KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo $ACCESS_KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

echo ""
echo "✅ Setup completed successfully!"
echo ""
echo "🔐 GitHub Secrets to add:"
echo "=========================="
echo "AWS_ACCESS_KEY_ID: $ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"
echo "AWS_ACCOUNT_ID: 463470973994"
echo ""
echo "📝 Next steps:"
echo "1. Go to GitHub repository Settings → Secrets and variables → Actions"
echo "2. Add the three secrets above"
echo "3. Your CI/CD pipeline is ready to use!"
echo ""
echo "🔍 Verification:"
echo "aws ecr describe-repositories --repository-names retail-store --region us-east-1"