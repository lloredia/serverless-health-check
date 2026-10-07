terraform {
  backend "s3" {
    # Partial backend. Do not put a bucket or lock table here.
    # Copy backends/*.hcl.example and pass it at init:
    #   terraform init -backend-config=backends/staging.hcl
    # The lock table must be the dedicated table from bootstrap
    # (default name: serverless-health-check-tf-locks), never the
    # application table staging-requests-db or prod-requests-db.
  }
}
