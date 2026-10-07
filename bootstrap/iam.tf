data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region

  names = {
    for env in var.environments : env => {
      function = "${env}-${var.project_name}-function"
      role     = "${env}-${var.project_name}-function-role"
      api      = "${env}-${var.project_name}-api"
      table    = "${env}-requests-db"
      topic    = "${env}-${var.project_name}-alerts"
    }
  }

  function_arns = flatten([
    for n in local.names : [
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${n.function}",
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${n.function}:*",
    ]
  ])

  role_arns = [
    for n in local.names : "arn:aws:iam::${local.account_id}:role/${n.role}"
  ]

  table_arns = [
    for n in local.names : "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${n.table}"
  ]

  log_arns = flatten([
    for n in local.names : [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${n.function}",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${n.function}:*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/${n.api}",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/${n.api}:*",
    ]
  ])

  alarm_arns = flatten([
    for n in local.names : [
      "arn:aws:cloudwatch:${local.region}:${local.account_id}:alarm:${n.function}-errors",
      "arn:aws:cloudwatch:${local.region}:${local.account_id}:alarm:${n.api}-5xx",
    ]
  ])

  topic_arns = flatten([
    for n in local.names : [
      "arn:aws:sns:${local.region}:${local.account_id}:${n.topic}",
      "arn:aws:sns:${local.region}:${local.account_id}:${n.topic}:*",
    ]
  ])

  lock_table_arn = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${var.lock_table_name}"
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    sid     = "GitHubActions"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:environment:staging",
        "repo:${var.github_org}/${var.github_repo}:environment:production",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_org}/${var.github_repo}/${var.github_workflow_ref}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = var.deploy_role_name
  description          = "GitHub Actions deploy role for ${var.github_org}/${var.github_repo}"
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  max_session_duration = 3600

  tags = {
    Name = var.deploy_role_name
  }

  lifecycle {
    precondition {
      condition     = var.create_oidc_provider || length(var.existing_oidc_provider_arn) > 0
      error_message = "existing_oidc_provider_arn is required when create_oidc_provider is false."
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid    = "StateBucketList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid    = "StateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/serverless-health-check/*"]
  }

  statement {
    sid    = "StateLock"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [local.lock_table_arn]
  }

  statement {
    sid    = "RequestTables"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = local.table_arns
  }

  statement {
    sid    = "LambdaFunctions"
    effect = "Allow"
    actions = [
      "lambda:AddPermission",
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:DeleteFunctionConcurrency",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetFunctionConfiguration",
      "lambda:GetPolicy",
      "lambda:GetRuntimeManagementConfig",
      "lambda:ListTags",
      "lambda:ListVersionsByFunction",
      "lambda:PutFunctionConcurrency",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = local.function_arns
  }

  statement {
    sid    = "LambdaRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = local.role_arns
  }

  statement {
    sid       = "PassLambdaRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "HttpApi"
    effect = "Allow"
    actions = [
      "apigateway:DELETE",
      "apigateway:GET",
      "apigateway:PATCH",
      "apigateway:POST",
      "apigateway:PUT",
    ]
    resources = [
      "arn:aws:apigateway:${local.region}::/apis",
      "arn:aws:apigateway:${local.region}::/apis/*",
      "arn:aws:apigateway:${local.region}::/tags/*",
    ]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagLogGroup",
      "logs:TagResource",
      "logs:UntagLogGroup",
      "logs:UntagResource",
    ]
    resources = local.log_arns
  }

  statement {
    sid    = "Alarms"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = local.alarm_arns
  }

  statement {
    sid    = "Alerts"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetSubscriptionAttributes",
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTagsForResource",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:TagResource",
      "sns:Unsubscribe",
      "sns:UntagResource",
    ]
    resources = local.topic_arns
  }
}

resource "aws_iam_role_policy" "deploy" {
  #checkov:skip=CKV_AWS_286:Deploy role must create the Lambda role and pass it only to lambda.amazonaws.com
  #checkov:skip=CKV_AWS_287:PassRole is conditioned on lambda.amazonaws.com and limited to the two function roles
  #checkov:skip=CKV_AWS_355:API Gateway resource ARNs are ID-based, so they are region-scoped rather than name-scoped
  #checkov:skip=CKV_AWS_290:Allowed actions are the Terraform operations for this stack, not a full service wildcard
  name   = "${var.deploy_role_name}-policy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
