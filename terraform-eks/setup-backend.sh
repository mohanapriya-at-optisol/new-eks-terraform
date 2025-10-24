#!/bin/bash
# Terraform Backend Bootstrap Script for GitHub Actions
# Sets up:
#   - S3 backend bucket with versioning, encryption, public access block
#   - DynamoDB table for Terraform state locking
#   - Waits for both to become fully ready
#   - Creates Terraform backend config and workspace
set -euo pipefail

# ------------------------------------------------------------------------------
# 1️⃣ Load environment variables from GitHub Actions or use fallback defaults
# ------------------------------------------------------------------------------
TF_BUCKET="${GITHUB_TF_BUCKET:-my-tf-backend-bucket}"
TF_DDB_TABLE="${GITHUB_TF_DDB_TABLE:-my-tf-lock-table}"
AWS_REGION="${GITHUB_REGION:-ap-south-1}"
AWS_PROFILE="${GITHUB_AWS_PROFILE:-tf-admin}"
ENVIRONMENT="${GITHUB_ENVIRONMENT:-dev}"
GITHUB_CLUSTER_NAME="${GITHUB_CLUSTER_NAME:-eks-cluster}"
GITHUB_CLUSTER_VERSION="${GITHUB_CLUSTER_VERSION:-1.31}"
GITHUB_VPC_CIDR="${GITHUB_VPC_CIDR:-10.0.0.0/16}"
GITHUB_NODE_GROUP_NAME="${GITHUB_NODE_GROUP_NAME:-default}"
GITHUB_INSTANCE_TYPE="${GITHUB_INSTANCE_TYPE:-t3.medium}"
GITHUB_MIN_SIZE="${GITHUB_MIN_SIZE:-2}"
GITHUB_MAX_SIZE="${GITHUB_MAX_SIZE:-5}"
GITHUB_DESIRED_SIZE="${GITHUB_DESIRED_SIZE:-3}"
GITHUB_DISK_SIZE="${GITHUB_DISK_SIZE:-50}"
GITHUB_PROJECT_NAME="${GITHUB_PROJECT_NAME:-eks-karpenter}"

# ------------------------------------------------------------------------------
# 2️⃣ Track created resources for cleanup
# ------------------------------------------------------------------------------
CREATED_BUCKET=""
CREATED_DDB_TABLE=""

cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "⚠️ Script failed! Cleaning up created resources..."
    if [ -n "$CREATED_BUCKET" ]; then
      echo "🧹 Deleting S3 bucket: $CREATED_BUCKET"
      aws s3 rb "s3://$CREATED_BUCKET" --force --region "$AWS_REGION" || true
    fi
    if [ -n "$CREATED_DDB_TABLE" ]; then
      echo "🧹 Deleting DynamoDB table: $CREATED_DDB_TABLE"
      aws dynamodb delete-table --table-name "$CREATED_DDB_TABLE" --region "$AWS_REGION" || true
    fi
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# 3️⃣ Validate AWS credentials
# ------------------------------------------------------------------------------
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "❌ Invalid AWS credentials for profile '$AWS_PROFILE'"
  exit 1
fi
echo "✅ AWS credentials validated"
echo "✅ Environment: $ENVIRONMENT"
echo "✅ Region: $AWS_REGION"
echo "✅ Profile: $AWS_PROFILE"
echo ""

# ------------------------------------------------------------------------------
# 4️⃣ Ensure S3 bucket exists and is secure
# ------------------------------------------------------------------------------
if ! aws s3api head-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "🪣 Creating S3 bucket '$TF_BUCKET'..."
  CREATE_ARGS=(--bucket "$TF_BUCKET" --region "$AWS_REGION")
  [ "$AWS_REGION" != "us-east-1" ] && CREATE_ARGS+=(--create-bucket-configuration LocationConstraint="$AWS_REGION")
  aws s3api create-bucket "${CREATE_ARGS[@]}"
  CREATED_BUCKET="$TF_BUCKET"
  echo "✅ S3 bucket created"

  # Apply best practices
  aws s3api put-bucket-versioning \
    --bucket "$TF_BUCKET" \
    --versioning-configuration Status=Enabled \
    --region "$AWS_REGION"
  aws s3api put-bucket-encryption \
    --bucket "$TF_BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }' \
    --region "$AWS_REGION"
  aws s3api put-public-access-block \
    --bucket "$TF_BUCKET" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true,
      "IgnorePublicAcls": true,
      "BlockPublicPolicy": true,
      "RestrictPublicBuckets": true
    }' \
    --region "$AWS_REGION"

  # Wait for bucket propagation
  echo "⏳ Waiting for S3 bucket to be fully available..."
  for i in {1..10}; do
    if aws s3api head-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
      echo "✅ S3 bucket is now available."
      break
    fi
    echo "⌛ Still waiting for S3 bucket... retry $i/10"
    sleep 5
  done
else
  echo "ℹ️ S3 bucket '$TF_BUCKET' already exists — skipping creation"
fi
echo ""

# ------------------------------------------------------------------------------
# 5️⃣ Ensure DynamoDB table exists and ready for state locking
# ------------------------------------------------------------------------------
if ! aws dynamodb describe-table --table-name "$TF_DDB_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "🧱 Creating DynamoDB table '$TF_DDB_TABLE' for Terraform state locking..."
  aws dynamodb create-table \
    --table-name "$TF_DDB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
  CREATED_DDB_TABLE="$TF_DDB_TABLE"
  echo "⏳ Waiting for DynamoDB table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "$TF_DDB_TABLE" --region "$AWS_REGION"
  echo "✅ DynamoDB table is active."
else
  echo "ℹ️ DynamoDB table '$TF_DDB_TABLE' already exists — skipping creation"
fi
echo ""

# ------------------------------------------------------------------------------
# 6️⃣ Create backend config file for Terraform
# ------------------------------------------------------------------------------
mkdir -p backend-config
BACKEND_CONFIG_FILE="backend-config/${ENVIRONMENT}.tfbackend"
cat > "$BACKEND_CONFIG_FILE" <<EOF
bucket         = "${TF_BUCKET}"
key            = "terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${TF_DDB_TABLE}"
encrypt        = true
EOF
echo "✅ Backend config file created: $BACKEND_CONFIG_FILE"

# ------------------------------------------------------------------------------
# 7️⃣ Create environment variables file for Terraform
# ------------------------------------------------------------------------------
mkdir -p envs
ENV_VARS_FILE="envs/${ENVIRONMENT}.tfvars"
cat > "$ENV_VARS_FILE" <<EOF
region_name = "${AWS_REGION}"
cluster_version = "${GITHUB_CLUSTER_VERSION}"
vpc_cidr = "${GITHUB_VPC_CIDR}"
node_group_name = "${GITHUB_NODE_GROUP_NAME}"
cluster_name = "${ENVIRONMENT}-${GITHUB_CLUSTER_NAME}"
environment = "${ENVIRONMENT}"
node_instance_type = "${GITHUB_INSTANCE_TYPE}"
min_size = ${GITHUB_MIN_SIZE}
max_size = ${GITHUB_MAX_SIZE}
desired_size = ${GITHUB_DESIRED_SIZE}
disk_size = ${GITHUB_DISK_SIZE}
tags = {
  Environment = "${ENVIRONMENT}"
  Project     = "${GITHUB_PROJECT_NAME}"
  ManagedBy   = "terraform"
}
EOF
echo "✅ Environment variables file created: $ENV_VARS_FILE"

# ------------------------------------------------------------------------------
# 8️⃣ Initialize Terraform
# ------------------------------------------------------------------------------
echo "🚀 Initializing Terraform backend..."
terraform init -backend-config="$BACKEND_CONFIG_FILE"

# ------------------------------------------------------------------------------
# 9️⃣ Ensure correct Terraform workspace
# ------------------------------------------------------------------------------
WORKSPACE_EXISTS=$(terraform workspace list | grep -w "$ENVIRONMENT" || true)
if [ -z "$WORKSPACE_EXISTS" ]; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# ------------------------------------------------------------------------------
# ✅ Done
# ------------------------------------------------------------------------------
CREATED_BUCKET=""
CREATED_DDB_TABLE=""
echo ""
echo "🎉 Terraform backend setup completed successfully!"
echo "----------------------------------------------"
echo "S3 Bucket        : $TF_BUCKET"
echo "DynamoDB Table   : $TF_DDB_TABLE"
echo "Region           : $AWS_REGION"
echo "Environment      : $ENVIRONMENT"
echo "State Locking    : ✅ Enabled via DynamoDB"
echo "----------------------------------------------"
