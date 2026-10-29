#!/usr/bin/env bash
# Upload synthetic records to the PHI bucket as the ingest role.
# Your admin user is denied direct writes by the bucket policy, so this
# script assumes the ingest role (the only identity allowed to add records).
set -euo pipefail

cd "$(dirname "$0")/.."
TF="terraform -chdir=terraform"
BUCKET=$($TF output -raw phi_bucket)
KEY=$($TF output -raw data_key_arn)
ROLE=$($TF output -raw ingest_role_arn)

[[ -d data/output/fhir ]] || { echo "No data yet. Run: make data"; exit 1; }

echo "Assuming $ROLE ..."
read -r AK SK ST < <(aws sts assume-role --role-arn "$ROLE" --role-session-name "ingest-$(date +%s)" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)

AWS_ACCESS_KEY_ID=$AK AWS_SECRET_ACCESS_KEY=$SK AWS_SESSION_TOKEN=$ST \
  aws s3 cp data/output/fhir/ "s3://$BUCKET/fhir/" --recursive \
  --sse aws:kms --sse-kms-key-id "$KEY" --only-show-errors

echo "Uploaded $(ls data/output/fhir/*.json | wc -l) files to s3://$BUCKET/fhir/"
