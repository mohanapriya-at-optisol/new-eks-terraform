#!/bin/bash

# Exit on error
set -e

# Defaults
ENVIRONMENT=""
AWS_REGION=""
AWS_PROFILE_NAME=""

# Parse flags (backward compatible with single positional <environment>)
if [ $# -eq 1 ] && [[ $1 != -* ]]; then
  ENVIRONMENT=$1
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --environment|-e)
        ENVIRONMENT="$2"; shift 2;;
      --region|-r)
        AWS_REGION="$2"; shift 2;;
      --profile|-p)
        AWS_PROFILE_NAME="$2"; shift 2;;
      --help|-h)
        echo "Usage: $0 [--environment <env>] [--region <aws-region>] [--profile <aws-profile>]"
        echo "       $0 <environment>   # backward compatible"
        exit 0;;
      *)
        echo "Unknown argument: $1"; exit 1;;
    esac
  done
fi

if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: $0 [--environment <env>] [--region <aws-region>] [--profile <aws-profile>]"
  echo "       $0 <environment>   # backward compatible"
  echo "Example: $0 --environment dev --region us-east-2 --profile your-aws-profile"
  exit 1
fi

# Optionally export AWS env vars for downstream commands
if [ -n "$AWS_REGION" ]; then
  export AWS_DEFAULT_REGION="$AWS_REGION"
fi

if [ -n "$AWS_PROFILE_NAME" ]; then
  export AWS_PROFILE="$AWS_PROFILE_NAME"
fi

BACKEND_CONFIG_FILE="backend-config/${ENVIRONMENT}.tfbackend"

# Ensure standard directories exist
mkdir -p backend-config envs

# Determine the env vars file path early so we can read cluster_name if present
ENV_VARS_FILE="envs/${ENVIRONMENT}.tfvars"

# Try to read cluster_name from existing env vars (if present)
if [ -f "$ENV_VARS_FILE" ]; then
  EXISTING_CLUSTER_NAME=$(grep -E '^\s*cluster_name\s*=\s*' "$ENV_VARS_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
fi

# Establish a cluster name default if not present
CLUSTER_NAME="${EXISTING_CLUSTER_NAME:-${ENVIRONMENT}-eks-karpenter-cluster}"

# Auto-create env vars file if missing
if [ ! -f "$ENV_VARS_FILE" ]; then
  echo "Environment variables file '$ENV_VARS_FILE' not found. Creating one..."

  VARS_REGION="${AWS_REGION:-us-east-2}"

  cat > "$ENV_VARS_FILE" <<EOF
aws_region  = "${VARS_REGION}"
cluster_version = "1.33"
vpc_cidr    = "10.0.0.0/16"
azs         = ["${VARS_REGION}a", "${VARS_REGION}b", "${VARS_REGION}c"]
node_group_name = "default"
enable_efs_storage = true
project     = "eks-karpenter"

cluster_name = "${CLUSTER_NAME}"
environment = "${ENVIRONMENT}"
node_group_min_size = 2
node_group_max_size = 5
node_group_desired_size = 3
node_group_instance_types = ["t3.medium"]
node_group_disk_size = 50

# Optional: Override default tags
tags = {
  Environment = "${ENVIRONMENT}"
  Project     = "eks-karpenter"
  ManagedBy   = "terraform"
}
EOF
  echo "Created $ENV_VARS_FILE with baseline values. Please adjust as needed for '${ENVIRONMENT}'."
fi
# Auto-create backend config if missing (now that CLUSTER_NAME is known)
if [ ! -f "$BACKEND_CONFIG_FILE" ]; then
  echo "Backend config '$BACKEND_CONFIG_FILE' not found. Creating one..."

  # Determine region for backend creation: prefer flag, else default to us-east-2
  BOOTSTRAP_REGION="${AWS_REGION:-us-east-2}"
  if [ -z "$AWS_REGION" ]; then
    echo "No --region provided. Defaulting backend region to '${BOOTSTRAP_REGION}'."
  fi

  # Derive defaults for S3 bucket and DynamoDB table from cluster name
  DEFAULT_BUCKET_NAME="${ENVIRONMENT}-ek"
  DEFAULT_DDB_TABLE="${ENVIRONMENT}-ek"

  cat > "$BACKEND_CONFIG_FILE" <<EOF
bucket         = "${DEFAULT_BUCKET_NAME}"
key            = "terraform.tfstate"
region         = "${BOOTSTRAP_REGION}"
 dynamodb_table = "${DEFAULT_DDB_TABLE}"
encrypt        = true
EOF
  echo "Created $BACKEND_CONFIG_FILE with defaults: bucket='${DEFAULT_BUCKET_NAME}', ddb='${DEFAULT_DDB_TABLE}', region='${BOOTSTRAP_REGION}'."
fi

  # Read backend values from config file
  TF_BUCKET=$(grep -E '^\s*bucket\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
  TF_KEY=$(grep -E '^\s*key\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
  TF_REGION_CFG=$(grep -E '^\s*region\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')
  TF_DDB_TABLE=$(grep -E '^\s*dynamodb_table\s*=' "$BACKEND_CONFIG_FILE" | sed -E 's/.*=\s*"?([^"\s]+)"?.*/\1/')

# Prefer explicit flag region, else backend-config region
EFFECTIVE_REGION="${AWS_REGION:-$TF_REGION_CFG}"
if [ -z "$EFFECTIVE_REGION" ]; then
  echo "Error: No AWS region provided. Specify with --region or in $BACKEND_CONFIG_FILE"
fi

# Initialize Terraform with the backend config
echo "Initializing Terraform with backend configuration for environment: ${ENVIRONMENT}"
if [ -n "$AWS_PROFILE_NAME" ]; then
  echo "Using AWS profile: ${AWS_PROFILE_NAME}"
fi
if [ -n "$AWS_REGION" ]; then
  echo "Using AWS region: ${AWS_REGION} (exported as AWS_DEFAULT_REGION)"
fi

# Ensure S3 bucket exists (prompt to create if missing)
echo "Checking S3 bucket: ${TF_BUCKET} in region ${EFFECTIVE_REGION}..."
if aws s3api head-bucket --bucket "$TF_BUCKET" >/dev/null 2>&1; then
  echo "S3 bucket '$TF_BUCKET' exists and is accessible."
  # Ask whether to use existing bucket or create a new name
  while true; do
    read -r -p "Do you want to use the existing S3 bucket '$TF_BUCKET'? [Y/n]: " USE_EXISTING_BUCKET
    if [[ "$USE_EXISTING_BUCKET" =~ ^[Nn]$ ]]; then
      # Prompt for a new bucket name and try to create
      while true; do
        read -r -p "Enter a new S3 bucket name to create in '${EFFECTIVE_REGION}': " NEW_BUCKET
        if [ -z "$NEW_BUCKET" ]; then
          echo "No bucket name provided. Exiting."; exit 1
        fi
        TF_BUCKET="$NEW_BUCKET"
        sed -i -E "s|^\s*bucket\s*=.*$|bucket         = \"$TF_BUCKET\"|" "$BACKEND_CONFIG_FILE"

        echo "Creating bucket '$TF_BUCKET'..."
        CREATE_ARGS=(--bucket "$TF_BUCKET" --region "$EFFECTIVE_REGION")
        if [ "$EFFECTIVE_REGION" != "us-east-1" ]; then
          CREATE_ARGS+=(--create-bucket-configuration LocationConstraint="$EFFECTIVE_REGION")
        fi
        if aws s3api create-bucket "${CREATE_ARGS[@]}" >/dev/null 2>&1; then
          echo "Bucket created successfully."
          echo "Applying public access block..."
          aws s3api put-public-access-block --bucket "$TF_BUCKET" \
            --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
          echo "Enabling versioning..."
          aws s3api put-bucket-versioning --bucket "$TF_BUCKET" --versioning-configuration Status=Enabled
          echo "Enabling default encryption (SSE-S3)..."
          aws s3api put-bucket-encryption --bucket "$TF_BUCKET" \
            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
          break 2
        else
          echo "Failed to create bucket '$TF_BUCKET'. It may already exist or you may not have access."
          # Loop again to ask for another name
        fi
      done
    else
      break
    fi
  done
else
  echo "S3 bucket '$TF_BUCKET' not found or not accessible."
  while true; do
    read -r -p "Do you want to create the S3 bucket '$TF_BUCKET' in region '${EFFECTIVE_REGION}' now? [y/N]: " CREATE_BUCKET
    if [[ ! "$CREATE_BUCKET" =~ ^[Yy]$ ]]; then
      read -r -p "Any other Suggestion to create the bucket name? [Y/n]: " SUGGEST_BUCKET
      if [[ "$SUGGEST_BUCKET" =~ ^[Yy]$ ]] || [[ -z "$SUGGEST_BUCKET" ]]; then
        read -r -p "Enter a new S3 bucket name to create: " NEW_BUCKET
        if [ -n "$NEW_BUCKET" ]; then
          TF_BUCKET="$NEW_BUCKET"
          sed -i -E "s|^\s*bucket\s*=.*$|bucket         = \"$TF_BUCKET\"|" "$BACKEND_CONFIG_FILE"
          # Continue to create the new bucket
        else
          echo "No bucket name provided. S3 bucket creation aborted by user. Exiting."
          echo ""
          echo "Note: If you confirm S3 bucket only then you can create DynamoDB table"
          exit 1
        fi
      else
        echo "S3 bucket creation aborted by user. Exiting."
        echo ""
        echo "Note: If you confirm S3 bucket only then you can create DynamoDB table"
        exit 1
      fi
    fi
    
    # User chose to create the bucket (either default or new name)
    echo "Creating bucket '$TF_BUCKET'..."
    CREATE_ARGS=(--bucket "$TF_BUCKET" --region "$EFFECTIVE_REGION")
    if [ "$EFFECTIVE_REGION" != "us-east-1" ]; then
      CREATE_ARGS+=(--create-bucket-configuration LocationConstraint="$EFFECTIVE_REGION")
    fi
    if aws s3api create-bucket "${CREATE_ARGS[@]}" >/dev/null 2>&1; then
      echo "Bucket created successfully."
      break
    else
      echo "Failed to create bucket '$TF_BUCKET'. It may already exist (globally) or you may not have access."
      read -r -p "Enter an alternative S3 bucket name to use: " NEW_BUCKET
      if [ -z "$NEW_BUCKET" ]; then
        echo "No bucket name provided. Exiting."
        exit 1
      fi
      # Update in-memory variable and backend-config file
      TF_BUCKET="$NEW_BUCKET"
      sed -i -E "s|^\s*bucket\s*=.*$|bucket         = \"$TF_BUCKET\"|" "$BACKEND_CONFIG_FILE"
    fi
  done

  echo "Applying public access block..."
  aws s3api put-public-access-block --bucket "$TF_BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  echo "Enabling versioning..."
  aws s3api put-bucket-versioning --bucket "$TF_BUCKET" --versioning-configuration Status=Enabled
  echo "Enabling default encryption (SSE-S3)..."
  aws s3api put-bucket-encryption --bucket "$TF_BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

# Ensure DynamoDB table exists (prompt to create if missing)
if [ -n "$TF_DDB_TABLE" ]; then
  echo "Checking DynamoDB table: ${TF_DDB_TABLE} in region ${EFFECTIVE_REGION}..."
  if ! aws dynamodb describe-table --table-name "$TF_DDB_TABLE" --region "$EFFECTIVE_REGION" >/dev/null 2>&1; then
    echo "DynamoDB table '$TF_DDB_TABLE' not found."
    while true; do
      read -r -p "Do you want to create the DynamoDB table '$TF_DDB_TABLE' for state locking now? [y/N]: " CREATE_DDB
      if [[ ! "$CREATE_DDB" =~ ^[Yy]$ ]]; then
        read -r -p "Any other Suggestion to create the DynamoDB table name? [Y/n]: " SUGGEST_DDB
        if [[ "$SUGGEST_DDB" =~ ^[Yy]$ ]] || [[ -z "$SUGGEST_DDB" ]]; then
          read -r -p "Enter a new DynamoDB table name to create: " NEW_DDB
          if [ -n "$NEW_DDB" ]; then
            TF_DDB_TABLE="$NEW_DDB"
            sed -i -E "s|^\s*dynamodb_table\s*=.*$|dynamodb_table = \"$TF_DDB_TABLE\"|" "$BACKEND_CONFIG_FILE"
            # Continue to create the new table
          else
            echo "No table name provided. DynamoDB table creation aborted by user. Exiting."
            echo ""
            echo "Note: If you confirm DynamoDB only then you can create EKS Cluster"
            exit 1
          fi
        else
          echo "DynamoDB table creation aborted by user. Exiting."
          echo ""
          echo "Note: If you confirm DynamoDB only then you can create EKS Cluster"
          exit 1
        fi
      else
        # User chose to create the default table
        break
      fi
    done

    echo "Creating DynamoDB table '$TF_DDB_TABLE'..."
    if aws dynamodb create-table \
      --table-name "$TF_DDB_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "$EFFECTIVE_REGION" >/dev/null 2>&1; then
      echo "✅ DynamoDB table created successfully."
      echo "Waiting for DynamoDB table to become ACTIVE..."
      aws dynamodb wait table-exists --table-name "$TF_DDB_TABLE" --region "$EFFECTIVE_REGION"
      echo "❌ Failed to create DynamoDB table '$TF_DDB_TABLE'. It may already exist or name is reserved."
      read -r -p "Enter an alternative DynamoDB table name to use: " NEW_DDB
      if [ -z "$NEW_DDB" ]; then
        echo "No table name provided. Exiting."
        exit 1
      fi
      TF_DDB_TABLE="$NEW_DDB"
      sed -i -E "s|^\s*dynamodb_table\s*=.*$|dynamodb_table = \"$TF_DDB_TABLE\"|" "$BACKEND_CONFIG_FILE"
      
      # Retry with new name
      echo "Creating DynamoDB table '$TF_DDB_TABLE'..."
      if aws dynamodb create-table \
        --table-name "$TF_DDB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$EFFECTIVE_REGION" >/dev/null 2>&1; then
        echo "✅ DynamoDB table created successfully with alternative name."
        echo "Waiting for DynamoDB table to become ACTIVE..."
        aws dynamodb wait table-exists --table-name "$TF_DDB_TABLE" --region "$EFFECTIVE_REGION"
      else
        echo "❌ Failed to create DynamoDB table '$TF_DDB_TABLE'. Exiting."
        exit 1
      fi
    fi
  else
    echo "DynamoDB table '$TF_DDB_TABLE' exists."
    # Ask whether to use existing table or create a new one
    while true; do
      read -r -p "Do you want to use the existing DynamoDB table '$TF_DDB_TABLE'? [Y/n]: " USE_EXISTING_DDB
      if [[ "$USE_EXISTING_DDB" =~ ^[Nn]$ ]]; then
        read -r -p "Enter a new DynamoDB table name to create: " NEW_DDB
        if [ -z "$NEW_DDB" ]; then
          echo "No table name provided. Exiting."; exit 1
        fi
        TF_DDB_TABLE="$NEW_DDB"
        sed -i -E "s|^\s*dynamodb_table\s*=.*$|dynamodb_table = \"$TF_DDB_TABLE\"|" "$BACKEND_CONFIG_FILE"
        echo "Creating DynamoDB table '$TF_DDB_TABLE'..."
        if aws dynamodb create-table \
          --table-name "$TF_DDB_TABLE" \
          --attribute-definitions AttributeName=LockID,AttributeType=S \
          --key-schema AttributeName=LockID,KeyType=HASH \
          --billing-mode PAY_PER_REQUEST \
          --region "$EFFECTIVE_REGION" >/dev/null 2>&1; then
          echo "Waiting for DynamoDB table to become ACTIVE..."
          aws dynamodb wait table-exists --table-name "$TF_DDB_TABLE" --region "$EFFECTIVE_REGION"
          break
        else
          echo "Failed to create DynamoDB table '$TF_DDB_TABLE'. It may already exist or name is reserved."
          # Ask again
        fi
      else
        break
      fi
    done
  fi
fi

INIT_ARGS=(-backend-config="$BACKEND_CONFIG_FILE")
echo "Running: terraform init ${INIT_ARGS[*]}"
if ! terraform init "${INIT_ARGS[@]}"; then
  echo "Terraform init failed. Attempting to reconfigure backend..."
  if terraform init -reconfigure "${INIT_ARGS[@]}"; then
    echo "Terraform backend reconfigured successfully."
  else
    echo "Terraform init still failing after reconfigure."
    read -r -p "Would you like to attempt migrating existing state with 'terraform init -migrate-state'? [y/N]: " MIGRATE
    if [[ "$MIGRATE" =~ ^[Yy]$ ]]; then
      terraform init -migrate-state "${INIT_ARGS[@]}"
    else
      echo "Skipping state migration per user choice. Exiting."
      exit 1
    fi
  fi
fi

# Create workspace if it doesn't exist
WORKSPACE_EXISTS=$(terraform workspace list | grep -w "$ENVIRONMENT" || true)
if [ -z "$WORKSPACE_EXISTS" ]; then
  echo "Creating new workspace '${ENVIRONMENT}'..."
  terraform workspace new "$ENVIRONMENT"
else
  echo "Using existing workspace '${ENVIRONMENT}'..."
  terraform workspace select "$ENVIRONMENT"
fi

echo ""
echo "Terraform is now configured to use the '${ENVIRONMENT}' workspace."
echo "You can now run 'terraform plan' or 'terraform apply' to manage your infrastructure."