data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/lambda.zip"
  excludes    = ["__pycache__", "**/*.pyc", ".pytest_cache"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_158:Log group uses default encryption to avoid a CMK charge
  #checkov:skip=CKV_AWS_338:Retention is configurable and defaults to 14 days to limit log storage cost
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_lambda_function" "health_check" {
  #checkov:skip=CKV_AWS_116:Dead-letter queue is omitted; callers receive the 5xx and the error alarm fires
  #checkov:skip=CKV_AWS_117:Function has no VPC dependencies; a VPC would add ENI and NAT cost
  #checkov:skip=CKV_AWS_173:Environment variables are resource names, not secrets
  #checkov:skip=CKV_AWS_272:Code signing is not configured for this portfolio function
  filename                       = data.archive_file.lambda.output_path
  function_name                  = var.function_name
  role                           = aws_iam_role.lambda.arn
  handler                        = "health_check.lambda_handler"
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  runtime                        = "python3.11"
  timeout                        = 10
  reserved_concurrent_executions = var.reserved_concurrent_executions

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE             = var.dynamodb_table_name
      RECORD_TTL_DAYS            = tostring(var.record_ttl_days)
      CHECK_DYNAMODB             = var.check_dynamodb ? "true" : "false"
      DESCRIBE_CACHE_TTL_SECONDS = tostring(var.describe_cache_ttl_seconds)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  #checkov:skip=CKV_AWS_355:X-Ray PutTraceSegments and PutTelemetryRecords require Resource *
  #checkov:skip=CKV_AWS_290:X-Ray write is limited to the two trace actions and cannot be resource-scoped
  name = "${var.function_name}-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          aws_cloudwatch_log_group.lambda.arn,
          "${aws_cloudwatch_log_group.lambda.arn}:*",
        ]
      },
      {
        Sid    = "RequestTable"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DescribeTable",
        ]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid    = "XRay"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.function_name}-errors"
  alarm_description   = "Uncaught Lambda errors for ${var.function_name}. Application 500s alarm on the API 5xx metric."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.health_check.function_name
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
