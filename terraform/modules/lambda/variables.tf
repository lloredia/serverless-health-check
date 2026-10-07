variable "function_name" {
  description = "Name of the Lambda function."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "source_dir" {
  description = "Source directory for Lambda code."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table."
  type        = string
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions. -1 leaves the function unreserved."
  type        = number
}

variable "record_ttl_days" {
  description = "TTL passed to the function as RECORD_TTL_DAYS."
  type        = number
}

variable "check_dynamodb" {
  description = "Whether GET /health calls DescribeTable."
  type        = bool
}

variable "describe_cache_ttl_seconds" {
  description = "DescribeTable cache TTL passed to the function."
  type        = number
}

variable "alarm_actions" {
  description = "ARNs notified when the function reports errors."
  type        = list(string)
  default     = []
}
