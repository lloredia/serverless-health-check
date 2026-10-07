locals {
  dynamodb_table_name  = "${var.environment}-requests-db"
  lambda_function_name = "${var.environment}-${var.project_name}-function"
  api_gateway_name     = "${var.environment}-${var.project_name}-api"
  alarm_actions        = [aws_sns_topic.alerts.arn]
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "alerts" {
  name              = "${var.environment}-${var.project_name}-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid     = "AllowCloudWatchAlarms"
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-${var.project_name}-*",
      ]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name  = local.dynamodb_table_name
  environment = var.environment
}

module "api_gateway" {
  source = "./modules/api-gateway"

  api_name             = local.api_gateway_name
  environment          = var.environment
  lambda_invoke_arn    = module.lambda.invoke_arn
  log_retention_days   = var.log_retention_days
  throttle_rate_limit  = var.throttle_rate_limit
  throttle_burst_limit = var.throttle_burst_limit
  post_auth_type       = var.post_auth_type
  jwt_issuer           = var.jwt_issuer
  jwt_audience         = var.jwt_audience
  alarm_actions        = local.alarm_actions
}

module "lambda" {
  source = "./modules/lambda"

  function_name                  = local.lambda_function_name
  environment                    = var.environment
  source_dir                     = "${path.root}/../lambda"
  dynamodb_table_name            = module.dynamodb.table_name
  dynamodb_table_arn             = module.dynamodb.table_arn
  api_gateway_execution_arn      = module.api_gateway.execution_arn
  log_retention_days             = var.log_retention_days
  reserved_concurrent_executions = var.reserved_concurrent_executions
  record_ttl_days                = var.record_ttl_days
  check_dynamodb                 = var.check_dynamodb
  describe_cache_ttl_seconds     = var.describe_cache_ttl_seconds
  alarm_actions                  = local.alarm_actions
}
