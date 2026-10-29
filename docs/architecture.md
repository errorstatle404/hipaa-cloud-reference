# Architecture

```mermaid
flowchart LR
  subgraph laptop["Operator laptop (internet)"]
    admin["Admin IAM user<br/>(MFA)"]
  end

  subgraph aws["AWS account · us-east-2"]
    subgraph vpc["VPC 10.40.0.0/16 · no internet gateway, no NAT"]
      subgraph azA["Private app subnet · AZ a"]
        lambdaA["PHI reader Lambda"]
      end
      subgraph azB["Private app subnet · AZ b"]
        lambdaB["(Lambda ENI)"]
      end
      vpce["S3 gateway endpoint<br/>policy: this account's buckets only"]
    end

    ingest["Ingest role<br/>write-only"]
    phi[("PHI bucket<br/>synthetic FHIR records<br/>SSE-KMS · versioned · TLS 1.2+")]
    dataKey{{"KMS key: PHI<br/>rotation on"}}

    subgraph audit["Audit & detection"]
      trail["CloudTrail<br/>multi-region · validated<br/>+ S3 data events"]
      logs[("Log bucket<br/>SSE-KMS · 6-yr retention")]
      logsKey{{"KMS key: logs"}}
      cwl["CloudWatch Logs"]
      alarms["15 metric-filter alarms<br/>CIS 4.1–4.14 + PHI access denied"]
      sns["SNS alerts (encrypted)"]
      config["AWS Config<br/>18 HIPAA-mapped rules"]
      flow["VPC Flow Logs"]
      aa["IAM Access Analyzer"]
    end
  end

  admin -- "assume role" --> ingest
  ingest -- "PutObject (SSE-KMS)" --> phi
  admin -. "GetObject ✗ denied<br/>(not via endpoint)" .-> phi
  lambdaA -- "HTTPS 443 only" --> vpce --> phi
  phi -. encrypts with .- dataKey
  trail --> logs
  trail --> cwl --> alarms --> sns
  flow --> logs
  config --> logs
  logs -. encrypts with .- logsKey
```

## How a request flows

1. **Ingest.** The operator assumes the ingest role and uploads Synthea FHIR bundles. The bucket policy refuses `PutObject` from any other principal and refuses any key other than the PHI key.
2. **Use.** The Lambda runs in private subnets with no route to the internet. Its only egress rule is HTTPS to the S3 prefix list, through the gateway endpoint. It returns aggregate counts, never record contents.
3. **Refusal.** A `GetObject` that does not arrive through the endpoint is denied by the bucket policy, even for the account administrator. So is any request without TLS, or with TLS older than 1.2.
4. **Evidence.** Every read and write of a record is a CloudTrail data event. Denied attempts on the PHI bucket raise the `phi-access-denied` alarm within about five minutes.

## What production would add

| Gap in this lab | Production design | Why it's not here |
|---|---|---|
| One account | AWS Organization: separate log-archive, security-tooling and workload accounts, with SCPs | Creating an Organization moves a Free plan account to Paid (ADR-001) |
| No edge tier | ALB + AWS WAF in public subnets, or API Gateway with IAM auth | No user-facing app in scope; avoids an internet entry point (ADR-003) |
| Admin can assume the ingest role | Break-glass role with MFA, approval workflow, separate security account | One human operator (ADR-006) |
| Local Terraform state | S3 backend with locking, versioned and KMS-encrypted | Single operator (ADR-009) |
| Buckets deletable | S3 Object Lock (compliance mode) on the log bucket, cross-region replication | Teardown must be clean for a lab budget (ADR-010) |
| GuardDuty / Security Hub off by default | Always on, delegated admin in the security account | Billed after trial; turned on for a bounded demo window |
