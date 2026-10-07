variable "environment" {
  description = "Environment name. Resource names use this value (staging or prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in resource names. Must match bootstrap project_name."
  type        = string
  default     = "health-check"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for Lambda and API Gateway access logs."
  type        = number
  default     = 14

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days,
    )
    error_message = "log_retention_days must be a CloudWatch Logs retention value."
  }
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for the Lambda. Use -1 for unreserved."
  type        = number
  default     = 5

  validation {
    condition     = var.reserved_concurrent_executions == -1 || var.reserved_concurrent_executions >= 0
    error_message = "reserved_concurrent_executions must be -1 or greater than or equal to 0."
  }
}

variable "record_ttl_days" {
  description = "Days before a POST record expires through the DynamoDB TTL attribute."
  type        = number
  default     = 7

  validation {
    condition     = var.record_ttl_days > 0
    error_message = "record_ttl_days must be greater than 0."
  }
}

variable "check_dynamodb" {
  description = "When true, GET /health calls DescribeTable (cached). When false, GET does not call AWS."
  type        = bool
  default     = true
}

variable "describe_cache_ttl_seconds" {
  description = "How long a warm Lambda caches the DescribeTable health result."
  type        = number
  default     = 30

  validation {
    condition     = var.describe_cache_ttl_seconds >= 0
    error_message = "describe_cache_ttl_seconds must be greater than or equal to 0."
  }
}

variable "throttle_rate_limit" {
  description = "API Gateway default steady-state requests per second."
  type        = number
  default     = 5

  validation {
    condition     = var.throttle_rate_limit > 0
    error_message = "throttle_rate_limit must be greater than 0."
  }
}

variable "throttle_burst_limit" {
  description = "API Gateway default burst limit. Must be greater than or equal to throttle_rate_limit."
  type        = number
  default     = 10

  validation {
    condition     = var.throttle_burst_limit > 0
    error_message = "throttle_burst_limit must be greater than 0."
  }
}

variable "post_auth_type" {
  description = "Authorization for POST /health. GET /health stays open. HTTP APIs do not support usage-plan API keys; use AWS_IAM (SigV4) or JWT. NONE leaves POST public."
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["AWS_IAM", "JWT", "NONE"], var.post_auth_type)
    error_message = "post_auth_type must be AWS_IAM, JWT, or NONE."
  }
}

variable "jwt_issuer" {
  description = "JWT issuer URL. Required when post_auth_type is JWT."
  type        = string
  default     = ""
}

variable "jwt_audience" {
  description = "JWT audiences. Required when post_auth_type is JWT."
  type        = list(string)
  default     = []
}

variable "alarm_email" {
  description = "Optional email subscribed to the alarm topic. Empty skips the subscription."
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email must be empty or a single email address."
  }
}
