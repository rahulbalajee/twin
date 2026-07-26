terraform {
  # 1.10+ required for S3-native state locking (use_lockfile)
  required_version = ">= 1.10.0"

  # Remote state in S3 with native lockfile locking (no DynamoDB needed).
  # Backend blocks can't interpolate variables, so the bucket name is
  # hardcoded. The bucket itself is created once via terraform/bootstrap.
  # Workspace states are stored automatically under an env:/ prefix.
  backend "s3" {
    bucket       = "twin-terraform-state-400644524171"
    key          = "twin/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Default provider: all primary resources (Lambda, API Gateway, S3) deploy here
provider "aws" {
  region = var.aws_region
}

# CloudFront only accepts ACM certificates from us-east-1 (hard AWS
# constraint for a global service). Used ONLY by the ACM cert resources.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}