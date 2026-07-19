terraform {
  required_version = ">= 1.0.0"

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