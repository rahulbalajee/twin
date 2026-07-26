# Bootstrap: Terraform state storage.
#
# This tiny config is deliberately separate from the main stack — the bucket
# that stores state can't be managed by the state it stores (chicken-and-egg),
# and it must survive `terraform destroy` of any app environment.
#
# Apply ONCE with local state:
#   cd terraform/bootstrap && terraform init && terraform apply
#
# Locking uses S3 native lockfiles (use_lockfile in the main backend config),
# so no DynamoDB table is needed (Terraform >= 1.10).

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "twin-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Account-level plumbing shared by every environment — refuse to destroy
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Store"
    Environment = "global"
    ManagedBy   = "terraform"
  }
}

# Versioning lets you recover any previous state file if one is ever
# corrupted or a bad migration overwrites it
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning + frequent applies = old state versions accumulate forever;
# keep 90 days of history, expire the rest
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}
