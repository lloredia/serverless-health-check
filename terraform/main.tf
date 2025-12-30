locals {
  dynamodb_table_name  = "${var.environment}-requests-db"
  lambda_function_name = "${var.environment}-${var.project_name}-function"
  api_gateway_name     = "${var.environment}-${var.project_name}-api"
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name  = local.dynamodb_table_name
  environment = var.environment
}

module "api_gateway" {
  source = "./modules/api-gateway"

  api_name          = local.api_gateway_name
  environment       = var.environment
  lambda_invoke_arn = module.lambda.invoke_arn
}

module "lambda" {
  source = "./modules/lambda"

  function_name             = local.lambda_function_name
  environment               = var.environment
  source_dir                = "${path.root}/../lambda"
  dynamodb_table_name       = module.dynamodb.table_name
  dynamodb_table_arn        = module.dynamodb.table_arn
  api_gateway_execution_arn = module.api_gateway.execution_arn
}