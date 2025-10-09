provider "aws"{
    region = var.region
    allowed_account_ids = [var.aws_account_id]
}

terraform{
    required_providers{
      aws = {
        source = "hashicorp/aws"
        version = ">= 5.0"
      }
    }
}

resource "aws_s3_bucket" "state_s3_bucket" {
  bucket = "${var.environment}-${var.state_bucket}"
  tags = {
    Name        = "Terraform State Bucket"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.state_s3_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.state_s3_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.state_s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.environment}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Environment = var.environment
  }
}
