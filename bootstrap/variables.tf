variable "aws_region" {
  description = "AWS region for the state bucket, lock table, and deploy role."
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
  default     = "lloredia"
}

variable "github_repo" {
  description = "GitHub repository name, without the owner."
  type        = string
  default     = "serverless-health-check"
}

variable "project_name" {
  description = "Must match the application project_name. Used to scope the deploy role."
  type        = string
  default     = "health-check"
}

variable "environments" {
  description = "Application environments the deploy role may manage. Names must match var.environment in the app stack."
  type        = list(string)
  default     = ["staging", "prod"]
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket for Terraform state."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB lock table. Do not reuse the application request tables."
  type        = string
  default     = "serverless-health-check-tf-locks"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false when the account already has one."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider. Required when create_oidc_provider is false."
  type        = string
  default     = ""
}

variable "deploy_role_name" {
  description = "IAM role assumed by GitHub Actions via OIDC."
  type        = string
  default     = "serverless-health-check-gha-deploy"
}

variable "github_workflow_ref" {
  description = "Workflow path and ref pinned in the role trust policy (job_workflow_ref)."
  type        = string
  default     = ".github/workflows/deploy.yml@refs/heads/main"
}
