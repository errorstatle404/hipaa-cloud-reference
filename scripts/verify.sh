#!/usr/bin/env bash
# Prove the controls work, not just that they exist. Each check prints PASS or
# FAIL, and the full run is saved under evidence/ for the README.
set -uo pipefail

cd "$(dirname "$0")/.."
TF="terraform -chdir=terraform"
REGION=$($TF output -raw region)
BUCKET=$($TF output -raw phi_bucket)
DATA_KEY=$($TF output -raw data_key_arn)
LOGS_KEY=$($TF output -raw logs_key_arn)
TRAIL=$($TF output -raw trail_name)
FN=$($TF output -raw app_function_name)
ROLE=$($TF output -raw ingest_role_arn)
VPC=$($TF output -raw vpc_id)
export AWS_DEFAULT_REGION=$REGION

mkdir -p evidence
OUT="evidence/verify-$(date +%Y%m%d-%H%M).txt"
exec > >(tee "$OUT") 2>&1
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { # check "description" <expected-substring> <command...>
  local desc=$1 want=$2; shift 2
  local got; got=$("$@" 2>&1)
  if grep -q -- "$want" <<<"$got"; then echo "PASS  $desc"; pass=$((pass+1))
  else echo "FAIL  $desc"; echo "      expected '$want', got: $(head -c 300 <<<"$got")"; fail=$((fail+1)); fi
}

echo "HIPAA reference build: control verification, $(date -u +%FT%TZ)"
echo "Bucket $BUCKET | region $REGION"
echo

echo "== Identity"
check "Running as an IAM user, not root" ":user/" aws sts get-caller-identity --query Arn --output text

echo "== Audit logging (164.312(b))"
check "CloudTrail is logging" "True" aws cloudtrail get-trail-status --name "$TRAIL" --query IsLogging --output text
check "Trail is multi-region with log file validation" "True	True" \
  aws cloudtrail describe-trails --trail-name-list "$TRAIL" --query 'trailList[0].[IsMultiRegionTrail,LogFileValidationEnabled]' --output text
check "VPC Flow Logs active" "ACTIVE" aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC" --query 'FlowLogs[].FlowLogStatus' --output text
check "15 security alarms in place" "15" \
  aws cloudwatch describe-alarms --alarm-name-prefix hipaa-ref- --query 'length(MetricAlarms)' --output text

echo "== Encryption (164.312(a)(2)(iv))"
check "PHI key rotation enabled" "True" aws kms get-key-rotation-status --key-id "$DATA_KEY" --query KeyRotationEnabled --output text
check "Log key rotation enabled" "True" aws kms get-key-rotation-status --key-id "$LOGS_KEY" --query KeyRotationEnabled --output text
check "PHI bucket default encryption uses the PHI key" "$DATA_KEY" \
  aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' --output text

echo "== Access control (164.312(a)(1))"
check "Bucket blocks all public access" "True	True	True	True" \
  aws s3api get-public-access-block --bucket "$BUCKET" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text
KEY1=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix fhir/ --max-items 1 --query 'Contents[0].Key' --output text 2>/dev/null | head -1)
if [[ -n "$KEY1" && "$KEY1" != "None" ]]; then
  check "Admin CANNOT read a patient record from the internet" "AccessDenied" \
    aws s3api get-object --bucket "$BUCKET" --key "$KEY1" "$TMP/record.json"
else
  echo "SKIP  Admin read test (no records yet: run make data upload)"
fi
echo "not a record" > "$TMP/x.txt"
check "Admin CANNOT write records directly" "AccessDenied" \
  aws s3api put-object --bucket "$BUCKET" --key fhir/admin-test.json --body "$TMP/x.txt"

read -r AK SK ST < <(aws sts assume-role --role-arn "$ROLE" --role-session-name verify \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
if [[ -n "$KEY1" && "$KEY1" != "None" ]]; then
  check "Ingest role CANNOT read records back" "AccessDenied" \
    env AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST" \
    aws s3api get-object --bucket "$BUCKET" --key "$KEY1" "$TMP/record2.json"
fi

echo "== Transmission security (164.312(e)(1))"
check "Plain HTTP (no TLS) is refused" "AccessDenied" \
  aws s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 --endpoint-url "http://s3.$REGION.amazonaws.com"

echo "== The app path works (inside the VPC, through the endpoint)"
aws lambda invoke --function-name "$FN" --cli-binary-format raw-in-base64-out --payload '{}' "$TMP/out.json" >/dev/null 2>&1
echo "      app returned: $(cat "$TMP/out.json" 2>/dev/null)"
check "App reads records and returns aggregates only" '"patients": [1-9]' cat "$TMP/out.json"

echo "== Findings"
AA=$(aws accessanalyzer list-analyzers --type ACCOUNT --query 'analyzers[?name==`hipaa-ref-analyzer`].arn' --output text 2>/dev/null)
if [[ -n "$AA" && "$AA" != "None" ]]; then
  check "IAM Access Analyzer: no active external-access findings" "^0$" \
    aws accessanalyzer list-findings-v2 --analyzer-arn "$AA" --filter '{"status":{"eq":["ACTIVE"]}}' --query 'length(findings)' --output text
else
  echo "SKIP  IAM Access Analyzer (not created here: enable_access_analyzer = false)"
fi
echo "      AWS Config rule results (may take ~15 min after deploy to settle):"
aws configservice describe-compliance-by-config-rule \
  --query 'ComplianceByConfigRules[?starts_with(ConfigRuleName,`hipaa-ref`)].[Compliance.ComplianceType,ConfigRuleName]' --output text 2>/dev/null \
  | sort | sed 's/^/      /'

echo
echo "Result: $pass passed, $fail failed. Saved to $OUT"
