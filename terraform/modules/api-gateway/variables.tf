variable "api_name" {
  description = "Name of the API Gateway."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for API Gateway access logs."
  type        = number
}

variable "throttle_rate_limit" {
  description = "Default steady-state requests per second."
  type        = number
}

variable "throttle_burst_limit" {
  description = "Default burst limit."
  type        = number
}

variable "post_auth_type" {
  description = "NONE, AWS_IAM, or JWT for POST /health."
  type        = string
}

variable "jwt_issuer" {
  description = "JWT issuer. Used when post_auth_type is JWT."
  type        = string
  default     = ""
}

variable "jwt_audience" {
  description = "JWT audiences. Used when post_auth_type is JWT."
  type        = list(string)
  default     = []
}

variable "alarm_actions" {
  description = "ARNs notified when the API returns 5xx."
  type        = list(string)
  default     = []
}
