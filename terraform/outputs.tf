output "api_endpoint" {
  description = "GET /health URL. POST uses the same path and requires the configured authorizer."
  value       = "${module.api_gateway.api_endpoint}/health"
}

output "post_auth_type" {
  description = "Authorization required for POST /health."
  value       = var.post_auth_type
}

output "dynamodb_table_name" {
  description = "DynamoDB table name."
  value       = module.dynamodb.table_name
}

output "lambda_function_name" {
  description = "Lambda function name."
  value       = module.lambda.function_name
}

output "alerts_topic_arn" {
  description = "SNS topic that receives Lambda error and API 5xx alarms."
  value       = aws_sns_topic.alerts.arn
}
