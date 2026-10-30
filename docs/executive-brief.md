# Executive brief: protecting patient records in the cloud

*Portfolio exercise written for a board audience. It describes a lab build using synthetic data, for no real organization. It is not a HIPAA compliance certification.*

## The problem

A healthcare organization moving patient records to the cloud has to show three things: only the right people and systems can reach the records, the records are encrypted, and every access is recorded. Many reference designs describe these controls. Few show them working, including the moment they refuse someone.

## What was built

A small AWS environment, written entirely as code, holding synthetic patient records. An application reads records from inside a private network and returns only totals. A separate role can add records but not read them. Encryption keys are managed separately from their use, so an administrator can manage a key without being able to use it. Every record access is logged.

## Proof it works

Tested on October 30, 2026:

- **The administrator is locked out.** The administrator's attempts to read or write records from outside the private network were refused, and so were attempts to use the encryption keys.
- **Refusals raise an alert.** In a timed test, a refused read triggered an alarm about 6 minutes later, and the alert email arrived.
- **Access is attributable.** The audit log shows who attempted each access and whether it was refused.
- **All 14 control tests passed.** One further check could not run because the account's organization-wide policy blocks that service.
- **An independent scan (Prowler) points mostly outside the build.** Of 12 remaining failures, 2 are in this build and both are a documented design choice. The other 10 are account-wide settings or older resources. The scan covers HIPAA-mapped checks in one region only.

Testing also found real defects that automated code scanning had passed, including one that would have silently stopped network logs from being delivered. All were fixed and retested.

## Top risks that remain

| Risk | Before controls | After controls (of 25) | What would reduce it further |
|---|---|---|---|
| A stolen administrator credential exposes records | 15 | 6, medium | Single sign-on, short-lived credentials, separate accounts |
| An insider with administrator rights destroys the audit trail | 8 | 6, medium | A separate log-archive account and tamper-proof log storage |
| Encrypted traffic is recorded now and decrypted later by a quantum computer | 8 | 6, medium | Move to post-quantum encryption as AWS supports it; re-measure quarterly |

**Known gaps:**
- The account-wide block on public storage is not on, because it has to be set from the organization's management account.
- Log integrity validation has not been run, because it needs a dedicated auditor role.
- Multi-factor authentication checks returned no result.

## Cost

**Estimate, not a measurement:** about $3 to $5 per month for the lab if left running. Billing data showed about $0 at the time of writing, but it lags by about a day and may be net of credits, so it does not yet show true cost. This is a lab figure. It says nothing about the cost of a production system, which would add accounts, redundancy and staff time.

## Decisions asked of the board

Before any real patient data enters this design:

1. **Adopt a multi-account structure** with a separate log-archive account, so that a compromised workload cannot erase its own audit trail.
2. **Require tamper-proof log storage** (S3 Object Lock in compliance mode) and an auditor role that can verify log integrity.
3. **Sign a Business Associate Agreement with AWS**, and complete the administrative and physical safeguards that this technical build does not cover.
4. **Set the account-wide block on public storage** from the management account, and reduce standing administrator access.

## Why post-quantum matters here

Health records stay sensitive for decades. Data captured today could be decrypted years from now, once quantum computers are capable enough; this is known as "harvest now, decrypt later." The companion [PQC TLS lab and crypto inventory](https://github.com/errorstatle404/pqc-tls-lab) measures whether encrypted connections are quantum-safe, and is the planned way to track this risk. It has not yet been run against this build.

*Details: [results](results.md), [threat model and risk register](threat-model.md), [control matrix](control-matrix.md).*
