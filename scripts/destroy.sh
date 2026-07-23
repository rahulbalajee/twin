#!/bin/bash
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Error: Environment parameter is required"
    echo "Usage: $0 <environment> [project_name]"
    echo "Example: $0 dev"
    echo "Available environments: dev, test, prod"
    exit 1
fi

ENVIRONMENT=$1
PROJECT_NAME=${2:-twin}

echo "Preparing to destroy $ENVIRONMENT environment for $PROJECT_NAME project"

cd "$(dirname "$0")/../terraform"

if ! terraform workspace list | grep -qw "$ENVIRONMENT"; then
    echo "Error: Environment $ENVIRONMENT not found"
    echo "Available workspaces: $(terraform workspace list)"
    exit 1
fi

terraform workspace select "$ENVIRONMENT"

echo ""
echo "⚠️  This permanently deletes ALL $ENVIRONMENT infrastructure,"
echo "    including every stored conversation in the memory bucket."
read -r -p "Type '$ENVIRONMENT' to confirm destruction: " CONFIRM
if [ "$CONFIRM" != "$ENVIRONMENT" ]; then
    echo "Aborted — nothing was destroyed."
    exit 1
fi

echo "Emptying S3 buckets..."

# Ask Terraform for the real bucket names (single source of truth); fall back
# to the naming convention only if the outputs are unavailable
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket 2>/dev/null || echo "${PROJECT_NAME}-${ENVIRONMENT}-frontend-${AWS_ACCOUNT_ID}")
MEMORY_BUCKET=$(terraform output -raw s3_memory_bucket 2>/dev/null || echo "${PROJECT_NAME}-${ENVIRONMENT}-memory-${AWS_ACCOUNT_ID}")

empty_bucket() {
    local bucket=$1
    if aws s3 ls "s3://$bucket" >/dev/null 2>&1; then
        echo "  Emptying $bucket..."
        aws s3 rm "s3://$bucket" --recursive >/dev/null
    else
        echo "  Bucket $bucket not found, skipping"
    fi
}

empty_bucket "$FRONTEND_BUCKET"
empty_bucket "$MEMORY_BUCKET"

echo "🔥 Running terraform destroy (CloudFront teardown takes 15-20 minutes)..."

if [ "$ENVIRONMENT" = "prod" ] && [ -f "prod.tfvars" ]; then
    terraform destroy -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
else
    terraform destroy -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
fi

echo "✅ Infrastructure for ${ENVIRONMENT} has been destroyed!"
echo ""
echo "💡 To remove the workspace completely, run:"
echo "   terraform workspace select default"
echo "   terraform workspace delete $ENVIRONMENT"
