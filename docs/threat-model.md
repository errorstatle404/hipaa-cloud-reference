# Threat model (STRIDE) and risk register

**System:** synthetic patient records (FHIR) stored in S3, read by a Lambda inside a private VPC, uploaded by a write-only ingest role, audited by CloudTrail, Config and CloudWatch alarms.
**Assets:** patient records (ePHI, synthetic here), encryption keys, audit logs, IAM credentials.
**Trust boundaries:** (1) internet ↔ AWS APIs, (2) operator laptop ↔ AWS account, (3) VPC ↔ S3 via the gateway endpoint, (4) workload roles ↔ data and keys.

## STRIDE

| # | Category | Threat | Control in this build | Verified by |
|---|---|---|---|---|
| S1 | Spoofing | Stolen admin access key used from anywhere | MFA on console; ingest needs role assumption; bucket refuses reads outside the VPC endpoint even for admin | `verify.sh`: admin read denied |
| S2 | Spoofing | Root user used for daily work | Root MFA, no root access keys, root-usage alarm | Config `ROOT_ACCOUNT_MFA_ENABLED`, `IAM_ROOT_ACCESS_KEY_CHECK`; alarm `root-account-usage` |
| T1 | Tampering | Records altered or overwritten | Versioning; writes only by the ingest role; wrong-key uploads denied | `verify.sh`: admin write denied |
| T2 | Tampering | Audit logs altered to hide activity | CloudTrail log file validation (SHA-256 digest chain); separate KMS key; log bucket TLS-only | `aws cloudtrail validate-logs` |
| R1 | Repudiation | "I never opened that record" | CloudTrail S3 data events record identity, time, source IP for each GetObject/PutObject | CloudTrail event history |
| I1 | Information disclosure | Bucket made public by mistake | Bucket and account-level Block Public Access; Access Analyzer; Config rules | `verify.sh`; Access Analyzer findings = 0 |
| I2 | Information disclosure | Data exfiltrated from inside the VPC to an attacker's bucket | VPC endpoint policy allows only this account's buckets; no internet route | Endpoint policy; Flow Logs |
| I3 | Information disclosure | Admin or cloud-insider decrypts data | Key policy without IAM delegation: admins manage, cannot decrypt; usage only via S3 | Key policy review; admin GetObject denied |
| I4 | Information disclosure | Interception in transit / downgrade | `aws:SecureTransport` deny; TLS < 1.2 deny | `verify.sh`: plain HTTP denied |
| I5 | Information disclosure | App leaks record contents in logs or responses | Handler returns and logs aggregates only; unit test asserts no names in output | `tests/test_handler.py` |
| D1 | Denial of service | Encryption key disabled or scheduled for deletion | 7-day deletion window; `kms-key-disable-or-delete` alarm | Alarm |
| D2 | Denial of service | Single-AZ outage | Lambda attached to subnets in two AZs; S3 is regional | Architecture |
| E1 | Elevation of privilege | Workload role gets broader policy attached | Permissions boundary denies IAM, role chaining, key admin | Boundary policy |
| E2 | Elevation of privilege | IAM policy changed to grant access | `iam-policy-changes` alarm; Config `IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS` | Alarm, Config |
| E3 | Elevation of privilege | Detective controls switched off before an attack | Alarms on CloudTrail and Config changes | Alarms `cloudtrail-config-changes`, `config-changes` |

## Risk register

Likelihood and impact on a 1–5 scale; score = L × I. Residual risk is after the controls above.

| ID | Risk | L | I | Inherent | Main controls | Residual | Owner decision |
|---|---|---|---|---|---|---|---|
| R1 | Admin credential compromise leads to record exposure | 3 | 5 | 15 | S1, I3, MFA, VPC-only reads | 6 (Med) | Accept for lab; production adds SSO, short-lived creds, separate accounts |
| R2 | Accidental public exposure of the bucket | 3 | 5 | 15 | I1 | 2 (Low) | Accept |
| R3 | Audit trail destroyed by an insider with admin rights | 2 | 4 | 8 | T2, E3 | 6 (Med) | Mitigate in production: log-archive account + Object Lock (ADR-001, ADR-010) |
| R4 | Exfiltration from compromised workload | 2 | 5 | 10 | I2, E1, no internet route | 3 (Low) | Accept |
| R5 | Key deletion makes data unrecoverable | 1 | 5 | 5 | D1 | 2 (Low) | Accept |
| R6 | Classical TLS captured now, decrypted later by a quantum computer | 2 | 4 | 8 | TLS 1.2+ floor; PQC inventory (project 3b) | 6 (Med) | Track: migrate as AWS endpoints adopt hybrid ML-KEM; re-scan quarterly |
| R7 | Cost overrun on Free plan credits | 3 | 2 | 6 | No NAT/EC2/RDS, detectors off by default, same-day teardown, budget alert | 2 (Low) | Accept |
