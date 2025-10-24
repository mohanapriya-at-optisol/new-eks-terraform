#!/bin/bash

# 🚀 Terraform Backend Setup Script
# Sets up:
#   - S3 backend bucket with encryption, versioning, and public access block
#   - DynamoDB table for Terraform state locking
#   - Waits for both to become fully ready before running terraform init

set -euo pipefail

# ------------------------------------------------------------------------------
# 1️⃣ Load environment variables
# ------------------------------------------------------------------------------
if [ -f .env ]; then
  echo "📦 Loading environment variables from .env file..."
  source .env
else
  echo "❌ .env file not found! Please create one with TF_BUCKET, TF_DDB_TABLE, AWS_REGION."
  exit 1
fi

# ------------------------------------------------------------------------------
# 2️⃣ Validate required variables
# ------------------------------------------------------------------------------
: "${TF_BUCKET:?TF_BUCKET not set}"
: "${TF_DDB_TABLE:?TF_DDB_TABLE not set}"
: "${AWS_REGION:?AWS_REGION not set}"

AWS_PROFILE="${AWS_PROFILE:-default}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# ------------------------------------------------------------------------------
# 3️⃣ Track created resources for cleanup
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
# 4️⃣ Validate AWS credentials
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
# 5️⃣ Ensure S3 bucket exists and is secured
# ------------------------------------------------------------------------------
if ! aws s3api head-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "🪣 Creating S3 bucket '$TF_BUCKET'..."
  CREATE_ARGS=(--bucket "$TF_BUCKET" --region "$AWS_REGION")
  [ "$AWS_REGION" != "us-east-1" ] && CREATE_ARGS+=(--create-bucket-configuration LocationConstraint="$AWS_REGION")
  aws s3api create-bucket "${CREATE_ARGS[@]}"
  CREATED_BUCKET="$TF_BUCKET"
  echo "✅ S3 bucket created"

  echo "🔒 Applying S3 best practices..."
  aws s3api put-bucket-versioning \
    --bucket "$TF_BUCKET" \
    --versioning-configuration Status=Enabled \
    --region "$AWS_REGION"
  aws s3api put-bucket-encryption \
    --bucket "$TF_BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }
      }]
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

  echo "⏳ Waiting for S3 bucket to become fully available..."
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
# 6️⃣ Ensure DynamoDB table exists and ready for state locking
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
# 7️⃣ Create backend config file for Terraform
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
# 8️⃣ Initialize Terraform with backend
# ------------------------------------------------------------------------------
echo "🚀 Initializing Terraform backend..."
terraform init -backend-config="$BACKEND_CONFIG_FILE"

# ------------------------------------------------------------------------------
# 9️⃣ Confirm workspace setup
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
