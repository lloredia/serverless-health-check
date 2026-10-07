provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ServerlessHealthCheck"
      ManagedBy = "Terraform"
      Component = "bootstrap"
    }
  }
}
