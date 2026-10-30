# Architecture decision log

One entry per significant choice: what was decided, why, and what it costs. Entries continue the numbering style of the log in the PQC TLS lab.

### ADR-001: One AWS account, documented as a deliberate gap
**Decision.** Build everything in a single account.
**Why.** A real healthcare workload belongs in an AWS Organization with separate log-archive, security-tooling and workload accounts, so that a compromised workload account cannot erase its own audit trail. Creating or joining an Organization moves a Free plan account to the Paid plan with no way back. The single-account build demonstrates the controls; the architecture doc shows the multi-account target.
**Trade-off.** An administrator in this account can, in principle, reach both the data and the logs.
**In an Organization.** An SCP blocks this member account from managing account-level S3 Block Public Access, so it has to be set from the management account. It is currently **not enabled**: a real gap, listed as a finding, with bucket-level Block Public Access on as the remaining control. An SCP also blocks Access Analyzer. Each account-wide setting has its own switch (`manage_password_policy`, `manage_ebs_default_encryption`, `manage_account_public_access_block`, `enable_access_analyzer`) so a blocked one can be turned off without losing the others.

### ADR-002: Terraform, us-east-2, same toolchain as the PQC lab
**Decision.** Terraform with the AWS provider 6.x, in us-east-2.
**Why.** Terraform is the most requested IaC skill in cloud security job posts and is already installed and working from the PQC lab. One home region keeps cost and CloudTrail review simple.

### ADR-003: No internet gateway, no NAT gateway, no public subnets
**Decision.** Two private application subnets across two Availability Zones. Nothing else.
**Why.** There is no user-facing component in scope, so an internet entry point would be pure attack surface. Removing the NAT gateway also removes its hourly charge (about $33/month per NAT gateway, plus data processing [verify]). The S3 gateway endpoint gives private access to S3 for free.
**Trade-off.** Anything that needs another AWS API (for example Secrets Manager) needs an interface endpoint, at about $7/month per AZ each [verify].

### ADR-004: S3 as the data tier, not RDS
**Decision.** Store records as FHIR R4 JSON bundles in S3.
**Why.** Synthea produces FHIR bundles natively, FHIR is the format US healthcare APIs are moving to, and S3 gives versioning, SSE-KMS and object-level audit (CloudTrail data events) with no running database to patch or pay for. RDS would add roughly 10 minutes per deploy and an always-on hourly charge.
**Trade-off.** No relational queries. A production analytics path would add Athena or AWS HealthLake [verify HealthLake pricing].

### ADR-005: Customer-managed KMS keys with separated duties
**Decision.** Two keys (PHI data, audit logs), annual rotation, and key policies with no "delegate to IAM" root statement.
**Why.** With the usual root statement, any IAM policy that grants `kms:*` (including AdministratorAccess) can decrypt the data. Without it, only principals named in the key policy can use the key. The administrator can manage the keys (rotate, tag, schedule deletion) but cannot decrypt patient records. Usage is further limited to calls made through S3 (`kms:ViaService`).
**Trade-off.** A typo in a key policy can lock you out of a key. The Terraform identity is always listed as key administrator, and AWS's lockout safety check rejects any key policy that would stop the caller from updating it.

### ADR-006: Workload roles with a permissions boundary; write-only ingest
**Decision.** Two roles: the app role (read) and the ingest role (write). Both carry a permissions boundary that caps them to the PHI bucket, the PHI key through S3, their own logs and Lambda networking, and explicitly denies IAM, Organizations, role chaining and key administration.
**Why.** Separation of duties at the identity layer: the uploader cannot read records back, the app cannot write, and neither can escalate even if a broader policy is attached later.
**Trade-off.** The administrator can still assume the ingest role. In production, assuming it would require MFA (`require_mfa_for_ingest = true`) and run from a separate security account.

### ADR-007: CloudTrail S3 data events instead of S3 server access logs
**Decision.** Log every object read and write on the PHI bucket as CloudTrail data events.
**Why.** HIPAA 164.312(b) asks for audit controls that record activity in systems containing ePHI. Data events carry the IAM identity, are delivered to the KMS-encrypted log bucket with integrity validation, and feed the alarms. S3 server access logs cannot be delivered to an SSE-KMS bucket and carry weaker identity information.
**Cost.** $0.10 per 100,000 data events; negligible at lab volume.

### ADR-008: Lambda instead of EC2 for the app tier
**Decision.** The application tier is a Python Lambda attached to the private subnets.
**Why.** The account's EC2 quota is 1 vCPU (this is what stopped the PQC lab's AWS run). Lambda also removes OS patching from the threat model and costs nothing at this volume.
**Accepted scanner findings.** No reserved concurrency: new accounts get a low concurrency quota (5 on this account) and AWS rejects reservations that leave fewer than the minimum unreserved. No code signing: AWS Signer is a production addition. No DLQ: the function is only invoked synchronously.

### ADR-009: Local Terraform state
**Decision.** State stays on the operator's laptop and is gitignored.
**Why.** One operator, short-lived environment. Production would use an S3 backend with locking, versioned and KMS-encrypted, in the security account.

### ADR-010: Lab teardown over immutability
**Decision.** `force_destroy = true` on both buckets, 7-day KMS deletion window, no Object Lock, no cross-region replication.
**Why.** The environment must tear down cleanly the same day to protect the Free plan credits. Production would put Object Lock (compliance mode) on the log bucket and replicate it to another region or account.

### ADR-011: Synthetic data only (Synthea)
**Decision.** All records are generated by Synthea with a fixed seed. No real patient data, ever.
**Why.** Real ePHI requires a signed Business Associate Agreement with AWS (through AWS Artifact) and a full compliance program. Synthea's output is realistic in shape (FHIR R4, full medical histories) and reproducible from the seed.

### ADR-012: Hand-picked AWS Config rules instead of the full HIPAA conformance pack
**Decision.** 18 managed rules, each mapped to a 164.312 safeguard in the control matrix.
**Why.** AWS publishes an "Operational Best Practices for HIPAA Security" conformance pack, but it evaluates well over 100 rules, most of them for services this build doesn't use, and each evaluation is billed. A small mapped set is cheaper and each rule is explainable in an interview. The full pack is a one-command extension.

### ADR-013: Detection services on a bounded window
**Decision.** GuardDuty and Security Hub are variables that default to off.
**Why.** Both bill by usage after their free trials. They are turned on for the scan and demo window, the findings are saved to `evidence/`, and they are turned off again. The CloudWatch alarms and Config rules stay on for the life of the environment.

### ADR-014: Transport encryption floor, and the post-quantum link
**Decision.** The PHI bucket denies requests without TLS and requests using TLS older than 1.2.
**Why.** HIPAA 164.312(e)(1) requires transmission security. This is also where the build meets the PQC track: the crypto inventory from project 3b can scan this account and its endpoints, so this build's "encrypted in transit" claim becomes a measured statement about which connections negotiate hybrid post-quantum key exchange and which are still classical. Long-retention health records are exactly the "harvest now, decrypt later" target that motivates PQC migration.
