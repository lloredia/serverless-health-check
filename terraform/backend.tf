terraform {
  backend "s3" {
    # Configure these values via backend config file or CLI
     bucket         = "stage-s3-serverless-healthcheck"
     key            = "serverless-health-check/terraform.tfstate"
     region         = "us-east-1"
     dynamodb_table = "stage-requests-db"
     encrypt        = true
  }
}
