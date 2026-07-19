output "api_gateway_url" {
  description = "URL of the API gateway"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cloudfront_url" {
  description = "URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution (used for cache invalidation on deploy)"
  value       = aws_cloudfront_distribution.main.id
}

output "s3_frontend_bucket" {
  description = "Name of the S3 bucket for the frontend"
  value       = aws_s3_bucket.frontend.id
}

output "s3_memory_bucket" {
  description = "Name of the S3 bucket for the memory"
  value       = aws_s3_bucket.memory.id
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

output "custom_domain_url" {
  description = "URL of the custom domain"
  value       = var.use_custom_domain ? "https://${var.root_domain}" : null
}