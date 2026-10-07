resource "aws_apigatewayv2_api" "health_api" {
  name          = var.api_name
  protocol_type = "HTTP"

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "access" {
  #checkov:skip=CKV_AWS_158:Access logs use default encryption to avoid a CMK charge
  #checkov:skip=CKV_AWS_338:Retention is configurable and defaults to 14 days to limit log storage cost
  name              = "/aws/apigateway/${var.api_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.health_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
      errorMessage     = "$context.error.message"
    })
  }

  default_route_settings {
    throttling_burst_limit   = var.throttle_burst_limit
    throttling_rate_limit    = var.throttle_rate_limit
    detailed_metrics_enabled = true
  }

  lifecycle {
    precondition {
      condition     = var.throttle_burst_limit >= var.throttle_rate_limit
      error_message = "throttle_burst_limit must be greater than or equal to throttle_rate_limit."
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.health_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  count            = var.post_auth_type == "JWT" ? 1 : 0
  api_id           = aws_apigatewayv2_api.health_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.api_name}-jwt"

  jwt_configuration {
    audience = var.jwt_audience
    issuer   = var.jwt_issuer
  }
}

resource "aws_apigatewayv2_route" "health_get" {
  #checkov:skip=CKV_AWS_309:GET /health is a public read-only check; POST defaults to AWS_IAM
  api_id             = aws_apigatewayv2_api.health_api.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "health_post" {
  api_id             = aws_apigatewayv2_api.health_api.id
  route_key          = "POST /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = var.post_auth_type
  authorizer_id      = var.post_auth_type == "JWT" ? aws_apigatewayv2_authorizer.jwt[0].id : null

  lifecycle {
    precondition {
      condition     = var.post_auth_type != "JWT" || (length(var.jwt_issuer) > 0 && length(var.jwt_audience) > 0)
      error_message = "jwt_issuer and jwt_audience are required when post_auth_type is JWT."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.api_name}-5xx"
  alarm_description   = "API Gateway 5xx responses for ${var.api_name}, including Lambda application errors."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ApiId = aws_apigatewayv2_api.health_api.id
    Stage = aws_apigatewayv2_stage.default.name
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
