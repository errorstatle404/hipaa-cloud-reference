# Results: first deployment, Oct 30, 2026

These results come from one deployment in a lab AWS account, using synthetic data only. They show how the controls behaved in that run. They are not a HIPAA compliance certification or an audit. Identifiers such as the account ID, bucket names and usernames are removed.

**The data:** 34 synthetic patients (25 living, 9 deceased) from Synthea with seed 2026, in 36 FHIR files. No real patient data was used.

## Summary

| Check | Result |
|---|---|
| `make verify` | 14 passed, 0 failed, 1 skipped |
| Denied read to alarm | 6 minutes, with the alert email received |
| AWS Config (18 rules) | 12 compliant, 4 non-compliant, 2 no result |
| Prowler HIPAA checks, `us-east-2` | 18 failures, then 12 after fixes; 2 are in this build |
| checkov | 216 passed, 0 failed, 20 skipped with written reasons |

## `make verify`

**Audit logging (164.312(b))**
- PASS: CloudTrail is logging
- PASS: Trail is multi-region with log file validation
- PASS: VPC Flow Logs active
- PASS: 15 security alarms in place

**Encryption (164.312(a)(2)(iv))**
- PASS: PHI key rotation enabled
- PASS: Log key rotation enabled
- PASS: PHI bucket default encryption uses the PHI key

**Access control (164.312(a)(1))**
- PASS: Running as an IAM user, not root
- PASS: Bucket blocks all public access
- PASS: Admin CANNOT read a patient record from the internet
- PASS: Admin CANNOT write records directly
- PASS: Ingest role CANNOT read records back

**Transmission security (164.312(e)(1))**
- PASS: Plain HTTP (no TLS) is refused

**The app path (inside the VPC, through the endpoint)**
- PASS: App reads records and returns aggregates only

**Skipped**
- SKIP: IAM Access Analyzer. An Organization SCP blocks it in this member account.

## Detection: from denied read to email

One denied read was run as the administrator, from outside the VPC endpoint.

| Time (UTC) | Event |
|---|---|
| 20:05:25 | The read is denied, and nothing is downloaded |
| 20:11:26 | `phi-access-denied` moves from OK to ALARM, about 6 minutes later |
| 20:11:26 | CloudWatch records a successful action on the alert topic |
| After 20:11:26 | The alert email arrives at the subscribed address (confirmed by the recipient; arrival time not measured) |

This is one timed run, not a measured average.

## Audit evidence: CloudTrail data events

A redacted excerpt of the event for the denied read above:

```json
{
  "eventTime": "2026-10-30T20:05:25Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "GetObject",
  "eventCategory": "Data",
  "managementEvent": false,
  "readOnly": true,
  "errorCode": "AccessDenied",
  "userIdentity": { "type": "IAMUser", "arn": "<admin user, redacted>" },
  "requestParameters": { "bucketName": "<PHI bucket, redacted>", "key": "<record, redacted>" },
  "tlsDetails": { "tlsVersion": "TLSv1.3" }
}
```

Object-level events in the trail's log group over the 24 hours of testing, by identity and outcome:

| Identity | Action | Outcome | Events |
|---|---|---|---|
| App role | GetObject | Success | 108 |
| Ingest role | PutObject | Success | 33 |
| Admin user | GetObject | AccessDenied | 4 |
| Admin user | PutObject | AccessDenied | 3 |
| Ingest role | GetObject | AccessDenied | 3 |
| Admin user | GetObject | NoSuchKey | 2 |
| Ingest role | GetObject | NoSuchKey | 1 |

- The ingest role's 33 uploads plus 3 multipart uploads account for all 36 files.
- The 108 app reads are 3 app runs across 36 files.
- The `NoSuchKey` rows are test requests for keys that did not exist. One came from a deliberate check; the others came from a bug in `verify.sh`, since fixed.

## The key policy

The administrator was also denied direct use of both KMS keys: `kms:Encrypt` and `kms:GenerateDataKey` both returned `AccessDeniedException`. `kms:Decrypt` was not called directly on the data key, because the administrator cannot obtain a stored object to try it on. The key policy grants the administrator no decrypt permission.

## AWS Config: 18 rules

12 compliant, 4 non-compliant, 2 with no result.

| Result | Rule | Explanation |
|---|---|---|
| Non-compliant | `s3-account-level-public-access-blocks-periodic` | **A real gap.** An Organization SCP blocks this member account from setting it, so it must be set from the management account. It is not enabled. Block Public Access on this build's buckets is on and verified. |
| Non-compliant | `s3-bucket-versioning-enabled` | A log bucket that existed before this build. |
| Non-compliant | `vpc-default-security-group-closed` | Default security groups in two VPCs that existed before this build. This build's own default group is not flagged. |
| Non-compliant | `vpc-flow-logs-enabled` | The account's default VPC, which existed before this build. |
| No result | `mfa-enabled-for-iam-console-access`, `root-account-mfa-enabled` | Not evaluated during this run, so they are not claimed as passing. |

The other 12 rules, including key rotation, CloudTrail encryption and log file validation, are compliant.

## Prowler: HIPAA checks, `us-east-2` only

Both scans ran after deployment, so this compares before and after the fixes below. It is not a comparison with the account before the build existed. The scan covers 44 checks in one region and is not a full audit.

| | First scan | After fixes |
|---|---:|---:|
| Pass | 75 | 81 |
| Fail | 18 | 12 |
| Critical | 1 | 1 |
| High | 3 | 3 |
| Medium | 10 | 5 |
| Low | 4 | 3 |

| Where the failures are | First scan | After fixes |
|---|---:|---:|
| This build | 2 | 2 |
| Account-wide settings | 9 | 3 |
| Resources from before this build | 7 | 7 |

**What cleared:** the 6 password-policy findings, once the account password policy was applied. No new failures appeared.

**This build (2, medium):** S3 server access logging is off on the PHI and log buckets. This is deliberate: CloudTrail data events record the identity on each object access instead (ADR-007).

**Account-wide (3):**
- High: account-level S3 Block Public Access is not enabled (the gap above).
- Low, 2 findings: the check wants a trail recording object events on all S3 buckets. This build records them on the PHI bucket only.

**From before this build (7):**
- Critical: `AdministratorAccess` is attached to the operator's IAM user and to one other role.
- High, 2 findings: network ACLs in two older VPCs allow all inbound traffic.
- Medium, 3 findings: log retention on an older log group, and versioning and access logging on an older log bucket.
- Low: an older trail is not sending to CloudWatch Logs.

## Bugs that testing found

Each of these was found by running the build, not by static analysis. checkov passed all of them.

| Bug | How it showed up | Fix |
|---|---|---|
| Config could not evaluate this build's KMS keys | The key rotation rule reported non-compliant while KMS showed rotation on | Gave Config read-only access to key metadata, with no key use |
| The flow-log bucket rule named a path flow logs never use | A later Terraform plan would have removed the only working permission, a statement AWS had added itself | Pointed the rule at the real path, then confirmed new log files kept arriving |
| `verify.sh` asked for a key that did not exist | Two access tests failed with `NoSuchKey` rather than `AccessDenied` | Fixed the key lookup, and confirmed the denials with a real key |

## Teardown

The build was destroyed on Oct 31, 2026 (101 resources). A check afterward found no S3 buckets, Lambda function, VPC, trail, Config recorder or rules, alarms, log groups, SNS topic or IAM roles left from this build. Both KMS keys are scheduled for deletion after the 7-day waiting period. The account password policy and EBS default encryption were deliberately left on, so removing the lab did not weaken the account.

## Not yet proven

- **Log file integrity:** `aws cloudtrail validate-logs` could not run. The log key's policy denied the administrator `kms:Decrypt`, so separation of duties also blocks this check. A dedicated auditor role with decrypt rights on the log key is needed.
- **MFA:** the two MFA Config rules returned no result.
- **TLS version floor:** plain HTTP is refused, and the observed connection used TLS 1.3. A TLS 1.0 or 1.1 connection attempt was not run.
- **Wrong-key uploads and S3 checksums:** configured, but not tested separately.
- **Session expiry:** configured in Terraform, but not tested.
- **Rebuild from scratch:** the fixes above were applied to the running build. A fresh `make up` has not yet been run with them.
- **Cost:** see the executive brief. Actual cost is not yet measured.
