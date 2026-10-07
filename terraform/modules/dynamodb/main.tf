resource "aws_dynamodb_table" "requests" {
  # AWS-owned key encryption. A customer-managed key would add a standing KMS charge.
  #checkov:skip=CKV_AWS_119:AWS-owned SSE avoids a dedicated CMK charge for this demo table

  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
