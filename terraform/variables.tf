variable "aws_region" {
  description = "AWS region for all primary resources (Lambda, API Gateway, S3)"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod"
  }
}

variable "bedrock_model_id" {
  description = "Bedrock model ID"
  type        = string
  default     = "global.amazon.nova-2-lite-v1:0"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (keep <= 30: API Gateway HTTP APIs cut the connection at ~30s)"
  type        = number
  default     = 30
}

variable "lambda_reserved_concurrency" {
  description = "Max concurrent Lambda executions (cost guard against request floods)"
  type        = number
  default     = 2
}

variable "api_throttle_burst_limit" {
  description = "API gateway throttle burst limit"
  type        = number
  default     = 10
}

variable "api_throttle_rate_limit" {
  description = "API gateway throttle rate limit"
  type        = number
  default     = 5
}

variable "use_custom_domain" {
  description = "Attach a custom domain to CloudFront distribution"
  type        = bool
  default     = false
}

variable "root_domain" {
  description = "Apex domain name, e.g. mydomain.com"
  type        = string
  default     = ""
}