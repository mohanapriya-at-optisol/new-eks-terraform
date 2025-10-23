#!/bin/bash

# ========================================
# Exit immediately on errors
# ========================================
set -e

# ========================================
# Track resources created during bootstrap
# ========================================
CREATED_BUCKET=""
CREATED_DDB_TABLE=""
CREATED_FILES=()

# ========================================
# Cleanup function to delete temporary resources on failure
# ========================================
cleanup() {
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    # Successful run, clear tracking
    CREATED_BUCKET=""
    CREATED_DDB_TABLE=""
    CREATED_FILES=()
    return
  fi

  echo "⚠️ Script failed! Cleaning up created resources..."

  # Delete S3 bucket if created
  if [ -n "$CREATED_BUCKET" ]; then
    aws s3 rm "s3://$CREATED_BUCKET" --recursive >/dev/null 2>&1 || true
    aws s3api delete-bucket --bucket "$CREATED_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1 || true
    echo "✅ S3 bucket '$CREATED_BUCKET' deleted"
  fi

  # Delete DynamoDB table if created
  if [ -n "$CREATED_DDB_TABLE" ]; then
    aws dynamodb delete-table --table-name "$CREATED_DDB_TABLE" --region "$AWS_REGION" >/dev/null 2>&1 || true
    echo "✅ DynamoDB table '$CREATED_DDB_TABLE' deleted"
  fi

  # Delete any created files
  for file in "${CREATED_FILES[@]}"; do
    [ -f "$file" ] && rm -f "$file" && echo "✅ File '$file' deleted"
  done

  exit $exit_code
}

# Trap cleanup for exit, termination, interrupt
trap cleanup SIGINT SIGTERM EXIT

# ========================================
# Parse input from GitHub Secrets
# ========================================
ENVIRONMENT="${GITHUB_ENVIRONMENT}"
AWS_REGION="${GITHUB_REGION}"
AWS_PROFILE="${GITHUB_AWS_PROFILE:-default}"
TF_BUCKET="${GITHUB_TF_BUCKET}"
TF_DDB_TABLE="${GITHUB_TF_DDB_TABLE}"
echo "Using S3 bucket: $TF_BUCKET"
echo "Using DB Table: $TF_DDB_TABLE"

if [ -z "$ENVIRONMENT" ] || [ -z "$AWS_REGION" ]; then
  echo "❌ Missing required GitHub secrets: GITHUB_ENVIRONMENT or GITHUB_REGION"
  exit 1
fi

echo "Environment: $ENVIRONMENT, Region: $AWS_REGION, Profile: $AWS_PROFILE"

# ========================================
# Validate AWS credentials
# ========================================
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "❌ AWS credentials invalid or no access"
  exit 1
fi
echo "✅ AWS credentials validated"

# ========================================
# Determine backend and env files
# ========================================
BACKEND_CONFIG_FILE="backend-config/${ENVIRONMENT}.tfbackend"
ENV_VARS_FILE="envs/${ENVIRONMENT}.tfvars"
mkdir -p backend-config envs

# ========================================
# Create environment variables file
# ========================================
if [ ! -f "$ENV_VARS_FILE" ]; then
  cat > "$ENV_VARS_FILE" <<EOF
region_name = "${AWS_REGION}"
cluster_version = "${GITHUB_CLUSTER_VERSION:-1.31}"
vpc_cidr = "${GITHUB_VPC_CIDR:-10.0.0.0/16}"
azs = ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]
node_group_name = "${GITHUB_NODE_GROUP_NAME:-default}"
enable_efs_storage = true
project = "${GITHUB_PROJECT_NAME:-eks-karpenter}"
cluster_name = "${ENVIRONMENT}-${GITHUB_CLUSTER_NAME}"
environment = "${ENVIRONMENT}"
node_instance_type = "${GITHUB_INSTANCE_TYPE:-t3.medium}"
min_size = ${GITHUB_MIN_SIZE:-2}
max_size = ${GITHUB_MAX_SIZE:-5}
desired_size = ${GITHUB_DESIRED_SIZE:-3}
disk_size = ${GITHUB_DISK_SIZE:-50}
tags = {
  Environment = "${ENVIRONMENT}"
  Project     = "${GITHUB_PROJECT_NAME:-eks-karpenter}"
  ManagedBy   = "terraform"
}
EOF
  CREATED_FILES+=("$ENV_VARS_FILE")
  echo "✅ Environment variables file '$ENV_VARS_FILE' created"
fi

# ========================================
# Create backend config file
# ========================================
if [ ! -f "$BACKEND_CONFIG_FILE" ]; then
  cat > "$BACKEND_CONFIG_FILE" <<EOF
bucket         = "${TF_BUCKET}"
key            = "terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${TF_DDB_TABLE}"
encrypt        = true
EOF
  CREATED_FILES+=("$BACKEND_CONFIG_FILE")
  echo "✅ Backend config '$BACKEND_CONFIG_FILE' created"
fi

# ========================================
# Parse backend config values
# ========================================
TF_BUCKET=$(grep -E '^\s*bucket\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
TF_KEY=$(grep -E '^\s*key\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
TF_REGION_CFG=$(grep -E '^\s*region\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
TF_DDB_TABLE=$(grep -E '^\s*dynamodb_table\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')

# ========================================
# Ensure S3 bucket exists
# ========================================
if ! aws s3api head-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "S3 bucket '$TF_BUCKET' not found. Creating..."
  CREATE_ARGS=(--bucket "$TF_BUCKET" --region "$AWS_REGION")
  [ "$AWS_REGION" != "us-east-1" ] && CREATE_ARGS+=(--create-bucket-configuration LocationConstraint="$AWS_REGION")
  aws s3api create-bucket "${CREATE_ARGS[@]}"
  CREATED_BUCKET="$TF_BUCKET"
  echo "✅ S3 bucket '$TF_BUCKET' created"
fi

# ========================================
# Ensure DynamoDB table exists
# ========================================
if ! aws dynamodb describe-table --table-name "$TF_DDB_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "DynamoDB table '$TF_DDB_TABLE' not found. Creating..."
  aws dynamodb create-table \
    --table-name "$TF_DDB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
  CREATED_DDB_TABLE="$TF_DDB_TABLE"
  aws dynamodb wait table-exists --table-name "$TF_DDB_TABLE" --region "$AWS_REGION"
  echo "✅ DynamoDB table '$TF_DDB_TABLE' created"
fi

# ========================================
# Initialize Terraform
# ========================================
terraform init -backend-config="$BACKEND_CONFIG_FILE"

# ========================================
# Workspace handling
# ========================================
WORKSPACE_EXISTS=$(terraform workspace list | grep -w "$ENVIRONMENT" || true)
if [ -z "$WORKSPACE_EXISTS" ]; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# ========================================
# Cleanup tracking variables
# ========================================
CREATED_BUCKET=""
CREATED_DDB_TABLE=""
CREATED_FILES=()

echo "🎉 Terraform bootstrap completed for environment '$ENVIRONMENT'"
