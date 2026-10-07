output "deploy_role_arn" {
  description = "Set this as the GitHub Actions secret AWS_ROLE_ARN."
  value       = aws_iam_role.deploy.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN trusted by the deploy role."
  value       = local.oidc_provider_arn
}

output "state_bucket_name" {
  description = "Set this as the GitHub Actions secret TF_STATE_BUCKET."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  description = "Set this as the GitHub Actions secret TF_LOCK_TABLE."
  value       = aws_dynamodb_table.locks.name
}

output "github_subjects" {
  description = "OIDC subjects allowed to assume the deploy role."
  value = [
    "repo:${var.github_org}/${var.github_repo}:environment:staging",
    "repo:${var.github_org}/${var.github_repo}:environment:production",
  ]
}
