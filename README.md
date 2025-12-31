
# Serverless Health Check API

A production-ready serverless health check API built with AWS Lambda, API Gateway, and DynamoDB. Features a complete CI/CD pipeline using Terraform and GitHub Actions for multi-environment deployments.

## 🏗️ Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   API Gateway       │
│   (HTTP API)        │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐      ┌──────────────────┐
│  Lambda Function    │─────▶│   DynamoDB       │
│  (Python 3.11)      │      │  (Request Store) │
└─────────┬───────────┘      └──────────────────┘
          │
          ▼
    ┌──────────────┐
    │ CloudWatch   │
    │    Logs      │
    └──────────────┘
```

### Components

- **API Gateway (HTTP API)**: Serverless REST API with `/health` endpoint
- **Lambda Function**: Processes health check requests and stores data
- **DynamoDB**: NoSQL database for storing request metadata
- **CloudWatch Logs**: Centralized logging with 7-day retention
- **IAM Roles**: Least-privilege security policies
- **S3 + DynamoDB**: Terraform state management with locking

## ✨ Features

- ✅ **Multi-environment support** (staging & production)
- ✅ **Infrastructure as Code** with Terraform modules
- ✅ **Automated CI/CD** with GitHub Actions
- ✅ **State locking** with DynamoDB
- ✅ **Environment-specific configurations**
- ✅ **Automated Lambda packaging**
- ✅ **Least-privilege IAM policies**
- ✅ **CloudWatch monitoring**

## 📋 Prerequisites

### Required

- **AWS Account** with programmatic access
- **GitHub Account** for repository and Actions
- **Terraform** >= 1.6.0 (for local development)
- **Python** 3.11+ (for local Lambda testing)

### GitHub Secrets Configuration

Configure the following secrets in your repository:

1. Navigate to: `Settings` → `Secrets and variables` → `Actions`
2. Add these repository secrets:
   - `AWS_ACCESS_KEY_ID`: Your AWS access key
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key

> **Security Note**: Use IAM user with minimal required permissions or consider using OIDC for GitHub Actions.

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/lloredia/serverless-health-check.git
cd serverless-health-check
```

### 2. Set Up S3 Backend (One-time Setup)

Create the S3 bucket and DynamoDB table for Terraform state:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket <your-unique-bucket-name> \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket <your-unique-bucket-name> \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Update `terraform/backend.tf` with your bucket name.

### 3. Deploy via GitHub Actions

**Deploy to Staging:**

```bash
git checkout -b staging
git push origin staging
```

**Deploy to Production:**

```bash
git checkout main
git merge staging
git push origin main
```

### 4. Local Development (Optional)

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="environments/staging.tfvars"

# Apply deployment
terraform apply -var-file="environments/staging.tfvars"

# Get outputs
terraform output
```

## 🔄 CI/CD Pipeline

### Workflow Triggers

- **Push to `staging` branch**: Automatically deploys to staging environment
- **Push to `main` branch**: Deploys to both staging and production
- **Manual workflow dispatch**: Deploy specific environment on-demand

### Pipeline Stages

```
┌──────────────┐
│   Checkout   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Setup Tools │
│ (Terraform)  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Terraform    │
│   Format     │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Terraform    │
│    Init      │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Terraform    │
│  Validate    │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Terraform    │
│    Plan      │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Terraform    │
│    Apply     │
└──────────────┘
```

## 📁 Project Structure

```
serverless-health-check/
├── .github/
│   └── workflows/
│       └── deploy.yml              # CI/CD pipeline
├── lambda/
│   ├── health_check.py             # Lambda function code
│   └── requirements.txt            # Python dependencies
├── terraform/
│   ├── modules/
│   │   ├── api-gateway/           # API Gateway module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── dynamodb/              # DynamoDB module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── lambda/                # Lambda module
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   ├── environments/
│   │   ├── staging.tfvars         # Staging variables
│   │   └── prod.tfvars            # Production variables
│   ├── backend.tf                 # S3 backend configuration
│   ├── main.tf                    # Root module
│   ├── variables.tf               # Root variables
│   ├── outputs.tf                 # Root outputs
│   └── providers.tf               # AWS provider config
└── README.md
```

## 🧪 Testing the API

### Get Your API Endpoint

```bash
# From Terraform output
cd terraform
terraform output api_endpoint

# Or from GitHub Actions logs
```

### Health Check Endpoints

**GET Request:**

```bash
curl https://your-api-id.execute-api.us-east-1.amazonaws.com/health
```

**POST Request:**

```bash
curl -X POST https://your-api-id.execute-api.us-east-1.amazonaws.com/health \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "source": "manual"}'
```

### Expected Response

```json
{
  "statusCode": 200,
  "body": {
    "status": "healthy",
    "message": "Request processed and saved.",
    "request_id": "123e4567-e89b-12d3-a456-426614174000",
    "timestamp": "2025-01-01T12:00:00.000Z"
  }
}
```

### Verify DynamoDB Records

```bash
aws dynamodb scan \
  --table-name staging-requests-db \
  --region us-east-1 \
  --output table
```

### Check CloudWatch Logs

```bash
# Tail logs in real-time
aws logs tail /aws/lambda/staging-health-check-function \
  --follow \
  --region us-east-1

# Get recent logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/staging-health-check-function \
  --start-time $(date -u -d '5 minutes ago' +%s)000 \
  --region us-east-1
```

## ⚙️ Configuration

### Environment Variables

Configure in `terraform/environments/*.tfvars`:

| Variable | Description | Example |
|----------|-------------|---------|
| `environment` | Environment name | `staging` or `prod` |
| `aws_region` | AWS region | `us-east-1` |
| `table_name` | DynamoDB table name | `staging-requests-db` |

### Lambda Configuration

Modify in `terraform/modules/lambda/variables.tf`:

- **Runtime**: Python 3.11
- **Memory**: 128 MB (adjustable)
- **Timeout**: 30 seconds (adjustable)

### DynamoDB Configuration

Modify in `terraform/modules/dynamodb/main.tf`:

- **Billing Mode**: PAY_PER_REQUEST (on-demand)
- **Primary Key**: `request_id` (String)

## 🛠️ Common Operations

### Import Existing Resources

If resources exist from a previous deployment:

```bash
cd terraform

# Import DynamoDB table
terraform import \
  -var-file="environments/staging.tfvars" \
  module.dynamodb.aws_dynamodb_table.requests \
  staging-requests-db

# Import IAM role
terraform import \
  -var-file="environments/staging.tfvars" \
  module.lambda.aws_iam_role.lambda \
  staging-health-check-function-role
```

### Manual Deployment

```bash
cd terraform

# Initialize
terraform init

# Plan
terraform plan -var-file="environments/staging.tfvars" -out=staging.tfplan

# Apply
terraform apply staging.tfplan
```

### Destroy Resources

```bash
cd terraform

# Destroy staging
terraform destroy -var-file="environments/staging.tfvars"

# Destroy production
terraform destroy -var-file="environments/prod.tfvars"
```

## 🔍 Troubleshooting

### Pipeline Fails: State Lock Error

**Problem**: `Error acquiring the state lock`

**Solution**:
```bash
# Delete the lock in DynamoDB
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"<your-state-path>"}}' \
  --region us-east-1
```

### Lambda Function Fails

**Problem**: Function returns 500 error

**Solutions**:
```bash
# Check CloudWatch logs
aws logs tail /aws/lambda/staging-health-check-function --follow

# Check function configuration
aws lambda get-function \
  --function-name staging-health-check-function \
  --region us-east-1

# Test function directly
aws lambda invoke \
  --function-name staging-health-check-function \
  --payload '{"test": "data"}' \
  response.json
```

### Resources Already Exist

**Problem**: `ResourceInUseException` or `EntityAlreadyExists`

**Solution**: Import or delete existing resources (see Common Operations)

## 📊 Monitoring & Observability

### CloudWatch Metrics

Monitor these key metrics:

- Lambda invocations
- Lambda errors
- Lambda duration
- API Gateway 4xx/5xx errors
- DynamoDB read/write capacity

### Create Alarms (Optional)

```bash
# Lambda error alarm
aws cloudwatch put-metric-alarm \
  --alarm-name staging-lambda-errors \
  --alarm-description "Alert on Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=staging-health-check-function
```

## 🔐 Security Best Practices

- ✅ IAM roles follow least-privilege principle
- ✅ No hardcoded credentials in code
- ✅ Secrets stored in GitHub Secrets
- ✅ HTTPS-only API endpoints
- ✅ CloudWatch logs for audit trail
- ⚠️ **TODO**: Add API authentication (API keys/Cognito)
- ⚠️ **TODO**: Enable AWS WAF for DDoS protection

## 💡 Design Decisions

### 1. HTTP API vs REST API
**Choice**: HTTP API (API Gateway v2)
- **Why**: Lower cost, simpler configuration, sufficient for this use case
- **Trade-off**: Fewer features than REST API (no API keys, usage plans)

### 2. DynamoDB On-Demand Billing
**Choice**: PAY_PER_REQUEST
- **Why**: Cost-effective for unpredictable/low traffic patterns
- **Trade-off**: Slightly higher per-request cost vs provisioned capacity

### 3. Modular Terraform Structure
**Choice**: Separate modules for each service
- **Why**: Reusability, maintainability, easier testing
- **Trade-off**: More complex structure for a simple project

### 4. GitHub Actions vs Other CI/CD
**Choice**: GitHub Actions
- **Why**: Native GitHub integration, free for public repos, easy setup
- **Trade-off**: Vendor lock-in to GitHub

## 🚧 Future Enhancements

- [ ] Add API authentication (API keys or AWS Cognito)
- [ ] Implement request rate limiting
- [ ] Add custom domain name with ACM certificate
- [ ] Implement blue-green deployments
- [ ] Add integration tests in CI/CD pipeline
- [ ] Set up CloudWatch alarms and SNS notifications
- [ ] Add AWS WAF for security
- [ ] Implement multi-region deployment
- [ ] Add API documentation with Swagger/OpenAPI

## 📝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- AWS for serverless services
- HashiCorp for Terraform
- GitHub for Actions platform

## 📧 Contact

**Author**: Lesley Lloredia
**Repository**: [https://github.com/lloredia/serverless-health-check](https://github.com/lloredia/serverless-health-check)

---

**Built with ❤️ using AWS, Terraform, and GitHub Actions**
