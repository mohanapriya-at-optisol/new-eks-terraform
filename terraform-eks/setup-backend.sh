#!/bin/bash

set -e

# Track created resources for cleanup
CREATED_BUCKET=""
CREATED_DDB_TABLE=""
CREATED_FILES=()

cleanup() {
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    CREATED_BUCKET=""
    CREATED_DDB_TABLE=""
    CREATED_FILES=()
    return
  fi

  echo "⚠️ Script failed! Cleaning up created resources..."

  if [ -n "$CREATED_BUCKET" ]; then
    aws s3 rm "s3://$CREATED_BUCKET" --recursive >/dev/null 2>&1 || true
    aws s3api delete-bucket --bucket "$CREATED_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1 || true
    echo "✅ S3 bucket deleted"
  fi

  if [ -n "$CREATED_DDB_TABLE" ]; then
    aws dynamodb delete-table --table-name "$CREATED_DDB_TABLE" --region "$AWS_REGION" >/dev/null 2>&1 || true
    echo "✅ DynamoDB table deleted"
  fi

  for file in "${CREATED_FILES[@]}"; do
    [ -f "$file" ] && rm -f "$file" && echo "✅ File deleted"
  done

  exit $exit_code
}

trap cleanup SIGINT SIGTERM EXIT

# Read from GitHub secrets (don't echo values - they're masked anyway)
ENVIRONMENT="${GITHUB_ENVIRONMENT}"
AWS_REGION="${GITHUB_REGION}"
AWS_PROFILE="${GITHUB_AWS_PROFILE:-tf-admin}"
TF_BUCKET="${GITHUB_TF_BUCKET}"
TF_DDB_TABLE="${GITHUB_TF_DDB_TABLE}"

# Validate required variables
if [ -z "$ENVIRONMENT" ] || [ -z "$AWS_REGION" ] || [ -z "$TF_BUCKET" ] || [ -z "$TF_DDB_TABLE" ]; then
  echo "❌ Missing required GitHub secrets"
  echo "Required: GITHUB_ENVIRONMENT, GITHUB_REGION, GITHUB_TF_BUCKET, GITHUB_TF_DDB_TABLE"
  exit 1
fi

echo "✅ Environment: $ENVIRONMENT"
echo "✅ Region: $AWS_REGION"
echo "✅ Profile: $AWS_PROFILE"
# Don't echo bucket/table names as they might contain sensitive info

# Validate AWS credentials (fast check)
if ! timeout 10 aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  echo "❌ AWS credentials invalid or timeout"
  exit 1
fi
echo "✅ AWS credentials validated"

# Create directories
mkdir -p backend-config envs

# Create backend config
BACKEND_CONFIG_FILE="backend-config/${ENVIRONMENT}.tfbackend"
cat > "$BACKEND_CONFIG_FILE" <<EOF
bucket         = "${TF_BUCKET}"
key            = "terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${TF_DDB_TABLE}"
encrypt        = true
EOF
CREATED_FILES+=("$BACKEND_CONFIG_FILE")
echo "✅ Backend config created"

# Create environment variables file
ENV_VARS_FILE="envs/${ENVIRONMENT}.tfvars"
cat > "$ENV_VARS_FILE" <<EOF
region_name = "${AWS_REGION}"
cluster_version = "${GITHUB_CLUSTER_VERSION:-1.31}"
vpc_cidr = "${GITHUB_VPC_CIDR:-10.0.0.0/16}"
azs = ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]
node_group_name = "${GITHUB_NODE_GROUP_NAME:-default}"
cluster_name = "${ENVIRONMENT}-${GITHUB_CLUSTER_NAME:-eks-cluster}"
environment = "${ENVIRONMENT}"
enable_efs_storage = "GITHUB_ENABLE_EFS_STORAGE"
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
echo "✅ Environment variables file created"

# Check S3 bucket exists (with timeout)
if timeout 15 aws s3api head-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "✅ S3 bucket already exists"
else
  echo "Creating S3 bucket..."
  CREATE_ARGS=(--bucket "$TF_BUCKET" --region "$AWS_REGION")
  [ "$AWS_REGION" != "us-east-1" ] && CREATE_ARGS+=(--create-bucket-configuration LocationConstraint="$AWS_REGION")
  aws s3api create-bucket "${CREATE_ARGS[@]}"
  CREATED_BUCKET="$TF_BUCKET"
  echo "✅ S3 bucket created"
  echo "⏳ Waiting for S3 propagation..."
  sleep 60
fi

# Check DynamoDB table exists (with timeout)
if timeout 15 aws dynamodb describe-table --table-name "$TF_DDB_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "✅ DynamoDB table already exists"
else
  echo "Creating DynamoDB table..."
  aws dynamodb create-table \
    --table-name "$TF_DDB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
  CREATED_DDB_TABLE="$TF_DDB_TABLE"
  aws dynamodb wait table-exists --table-name "$TF_DDB_TABLE" --region "$AWS_REGION"
  echo "✅ DynamoDB table created"
fi

# Initialize Terraform with speed optimizations
export TF_PLUGIN_TIMEOUT=120
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

if [ "$SKIP_TF_INIT" = "true" ]; then
  echo "⚡ Skipping Terraform init (SKIP_TF_INIT=true)"
elif [ ! -d ".terraform" ]; then
  echo "🚀 Initializing Terraform (fast mode)..."
  terraform init -backend-config="$BACKEND_CONFIG_FILE" -upgrade=false -get=true
else
  echo "✅ Terraform already initialized, skipping"
fi

# Handle workspace
WORKSPACE_EXISTS=$(terraform workspace list | grep -w "$ENVIRONMENT" || true)
if [ -z "$WORKSPACE_EXISTS" ]; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Clear tracking variables
CREATED_BUCKET=""
CREATED_DDB_TABLE=""
CREATED_FILES=()

echo "🎉 Bootstrap completed for environment '$ENVIRONMENT'"
