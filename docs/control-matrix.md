# Control matrix: HIPAA Security Rule technical safeguards (45 CFR 164.312)

Each row maps a safeguard to what this build implements, the NIST SP 800-53 Rev. 5 controls it supports, and how it is checked. "R" = required, "A" = addressable implementation specification. The NIST mapping follows the spirit of NIST SP 800-66 Rev. 2 [verify specific crosswalk entries before quoting].

**Evidence status** is filled in from `evidence/verify-*.txt`, AWS Config results and the Prowler report after deployment.

| HIPAA ref | Safeguard | Implementation in this build | NIST 800-53 | Automated check | Evidence |
|---|---|---|---|---|---|
| 164.312(a)(1) | Access control | Least-privilege roles; reads only via the VPC endpoint; writes only by the ingest role; Block Public Access (bucket + account); Access Analyzer | AC-3, AC-6, SC-7 | Config: `S3_BUCKET_PUBLIC_READ_PROHIBITED`, `S3_BUCKET_PUBLIC_WRITE_PROHIBITED`, `S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS_PERIODIC`, `IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS`, `IAM_ROOT_ACCESS_KEY_CHECK`; `verify.sh` access tests | pending |
| 164.312(a)(2)(i) R | Unique user identification | Named IAM user for the operator; role session names on every assumed role; no shared credentials; root not used | AC-2, IA-2 | CloudTrail `userIdentity`; alarm `root-account-usage` | pending |
| 164.312(a)(2)(ii) R | Emergency access procedure | Key administrator retains management of both keys; documented break-glass in production design | AC-2, CP-2 | Manual (ADR-006) | design only |
| 164.312(a)(2)(iii) A | Automatic logoff | Role sessions expire after 1 hour (`max_session_duration`) | AC-11, AC-12 | Terraform | pending |
| 164.312(a)(2)(iv) A | Encryption and decryption | Customer-managed KMS keys, rotation on; SSE-KMS on both buckets; encrypted log groups and SNS topic; admins cannot decrypt | SC-12, SC-13, SC-28 | Config: `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED`, `CMK_BACKING_KEY_ROTATION_ENABLED`, `CLOUD_TRAIL_ENCRYPTION_ENABLED`, `CLOUDWATCH_LOG_GROUP_ENCRYPTED` | pending |
| 164.312(b) | Audit controls | Multi-region CloudTrail with S3 data events on the PHI bucket; VPC Flow Logs; 6-year log retention; 15 alarms | AU-2, AU-3, AU-6, AU-11, AU-12, SI-4 | Config: `CLOUD_TRAIL_ENABLED`, `VPC_FLOW_LOGS_ENABLED`; `verify.sh` | pending |
| 164.312(c)(1) | Integrity | Versioning on records and logs; writes restricted to one role; wrong-key writes denied; CloudTrail digest validation | SI-7, AU-9, CP-9 | Config: `S3_BUCKET_VERSIONING_ENABLED`, `CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED` | pending |
| 164.312(c)(2) A | Mechanism to authenticate ePHI | S3 checksums on upload; CloudTrail log file validation for the audit trail | SI-7 | `aws cloudtrail validate-logs` | pending |
| 164.312(d) | Person or entity authentication | MFA for console users; role assumption for data access; optional MFA condition on ingest | IA-2, IA-5 | Config: `ROOT_ACCOUNT_MFA_ENABLED`, `MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS`; alarm `console-login-without-mfa` | pending |
| 164.312(e)(1) | Transmission security | TLS required, TLS 1.2 minimum; no internet route from the VPC; endpoint restricted to this account's buckets | SC-7, SC-8 | Config: `S3_BUCKET_SSL_REQUESTS_ONLY`, `VPC_DEFAULT_SECURITY_GROUP_CLOSED`, `LAMBDA_INSIDE_VPC`; `verify.sh` plain-HTTP test | pending |
| 164.312(e)(2)(i) A | Integrity controls (in transit) | TLS provides integrity; SigV4 request signing on every AWS API call | SC-8 | `verify.sh` | pending |
| 164.312(e)(2)(ii) A | Encryption (in transit) | TLS 1.2+ enforced by bucket policy; PQC readiness measured by the project 3b inventory | SC-8, SC-13 | `verify.sh`; crypto inventory CBOM | pending |

## Out of scope (administrative and physical safeguards)

164.308 (risk analysis, workforce training, contingency plan, BAAs) and 164.310 (facility access, workstation and device controls) are organizational. The threat model and risk register in [threat-model.md](threat-model.md) are an input to the 164.308(a)(1)(ii)(A) risk analysis. Physical safeguards for the data center are AWS's side of the shared responsibility model, documented in AWS Artifact.
