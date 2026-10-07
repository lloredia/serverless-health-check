#!/usr/bin/env bash
# Best-effort teardown for one environment when Terraform state is unavailable.
# Prefer:
#   terraform -chdir=terraform init -backend-config=backends/<env>.hcl
#   terraform -chdir=terraform destroy -var-file=environments/<env>.tfvars
#
# This script does not delete the Terraform state bucket or the lock table.
# Usage: ./cleanup.sh [staging|prod]

set -u

ENV="${1:-staging}"
REGION="${AWS_REGION:-us-east-1}"
PROJECT="health-check"
FUNCTION="${ENV}-${PROJECT}-function"
ROLE="${FUNCTION}-role"
TABLE="${ENV}-requests-db"
API_NAME="${ENV}-${PROJECT}-api"
TOPIC_NAME="${ENV}-${PROJECT}-alerts"

echo "Cleaning ${ENV} in ${REGION}"

aws lambda delete-function --function-name "$FUNCTION" --region "$REGION" 2>/dev/null || true

aws logs delete-log-group --log-group-name "/aws/lambda/${FUNCTION}" --region "$REGION" 2>/dev/null || true
aws logs delete-log-group --log-group-name "/aws/apigateway/${API_NAME}" --region "$REGION" 2>/dev/null || true

if policies="$(aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)"; then
  for policy in $policies; do
    if [ -n "$policy" ] && [ "$policy" != "None" ]; then
      aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$policy" || true
    fi
  done
fi

if policies="$(aws iam list-role-policies --role-name "$ROLE" --query 'PolicyNames[]' --output text 2>/dev/null)"; then
  for policy in $policies; do
    if [ -n "$policy" ] && [ "$policy" != "None" ]; then
      aws iam delete-role-policy --role-name "$ROLE" --policy-name "$policy" || true
    fi
  done
fi

aws iam delete-role --role-name "$ROLE" 2>/dev/null || true

API_IDS="$(aws apigatewayv2 get-apis --region "$REGION" --query "Items[?Name=='${API_NAME}'].ApiId" --output text 2>/dev/null || true)"
for API_ID in $API_IDS; do
  if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
    aws apigatewayv2 delete-api --api-id "$API_ID" --region "$REGION" || true
  fi
done

aws dynamodb delete-table --table-name "$TABLE" --region "$REGION" 2>/dev/null || true

aws cloudwatch delete-alarms --region "$REGION" --alarm-names \
  "${FUNCTION}-errors" \
  "${API_NAME}-5xx" \
  2>/dev/null || true

TOPIC_ARN="$(aws sns list-topics --region "$REGION" --query "Topics[?contains(TopicArn, ':${TOPIC_NAME}')].TopicArn" --output text 2>/dev/null || true)"
if [ -n "${TOPIC_ARN}" ] && [ "${TOPIC_ARN}" != "None" ]; then
  aws sns delete-topic --topic-arn "$TOPIC_ARN" || true
fi

echo "Cleanup finished. The state bucket and lock table were left in place."
