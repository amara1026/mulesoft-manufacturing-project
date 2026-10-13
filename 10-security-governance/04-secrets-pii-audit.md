# 10.4 — Secure Properties, Secret Rotation, Least Privilege, PII Masking and Audit Trails

`Essential`

## 1. Secure properties

**Encrypt values with the Secure Properties Tool (a JAR from MuleSoft docs):**
```bash
java -cp secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool \
  string encrypt AES CBC "$SECURE_KEY" "S3cr3t-DB-Pa55"
# -> output pasted as  db.password: "![base64-ciphertext]"
```
Reference it in XML as `${secure::db.password}`. The key `secure.key` is supplied at deploy time as a **protected (hidden)** property in Runtime Manager or by the CI/CD pipeline from a vault.

**Limits of secure properties:** the key itself must still be managed. Rotating a secret means re-encrypting and redeploying (or restarting), and anyone with the key and the repo can decrypt.

**Enterprise upgrade:** a vault (Azure Key Vault, HashiCorp Vault, AWS Secrets Manager):
- Option A: the pipeline fetches secrets and sets them as protected Runtime Manager properties at deploy.
- Option B: a vault-backed **custom properties provider** reads secrets at startup.
- Gains: central rotation, access policies, audit of secret reads, no ciphertext in Git.

## 2. Secret rotation playbook (example: SupplierHub OAuth secret)

| Step | Action |
|------|--------|
| 1 | SupplierHub issues a **second** valid secret (dual-secret overlap supported) |
| 2 | Update the vault. The pipeline updates the protected property in each environment, lowest first |
| 3 | Rolling restart. Replicas pick up the new secret one by one with no downtime |
| 4 | Verify (token requests succeed, error rate is normal) |
| 5 | Revoke the old secret after a soak period |
| 6 | Record in the change log. Calendar the next rotation (e.g. 90 days) |

If the partner **doesn't support overlap**, coordinate a time-boxed switch window and accept brief failures that queue and retry. Never do it without a plan.

## 3. Least privilege and role-based access control

| Area | Practice on AIM |
|------|-----------------|
| Anypoint Platform | **Teams** mapped to roles: developers deploy to DEV/QA only, release managers to PROD, support can view logs and restart, not deploy. Connected apps for CI with minimal scopes |
| SAP | One technical user per System API. `S_RFC` limited to the needed function groups/BAPIs. No dialog logon |
| Database | One DB user per app with grants only on its own schema. The read model user is read-only |
| Salesforce | An integration user with a permission set limited to Order, Account and custom fields |
| MQ | Client apps per Mule app, with permission only on the queues/exchanges it uses |
| Secrets | Each app can read only its own vault path |

## 4. PII masking and secure logging

**PII in AIM payloads:** contact names, emails, phone numbers, ship-to addresses (sometimes personal for small customers), and driver names/phones in carrier events.

**Rules**
1. Log **identifiers and metrics**, not payloads, at INFO: `orderId`, `externalOrderId`, `correlationId`, `status`, `durationMs`.
2. Payloads only at DEBUG, masked, and DEBUG never enabled in PROD without a change ticket and a time limit.
3. Never log `Authorization` headers, tokens, client secrets, passwords or certificates.

**Masking helper (DataWeave):**
```dataweave
%dw 2.0
output application/json
var piiFields = ["contactName", "email", "phone", "line1", "line2", "driverName", "driverPhone"]
fun mask(v) = if (v is String and sizeOf(v) > 2) v[0] ++ "***" ++ v[-1] else "***"
fun maskDeep(data) = data match {
  case o is Object -> o mapObject (v, k) ->
      { (k): if (piiFields contains (k as String)) mask(v) else maskDeep(v) }
  case a is Array -> a map maskDeep($)
  else -> data
}
---
maskDeep(payload)
```
Input `{"shipTo":{"contactName":"Maria Lopez","email":"m.lopez@riverside.example","city":"Austin"}}` → `{"shipTo":{"contactName":"M***z","email":"m***e","city":"Austin"}}`.

**Log4j2 structured logging (JSON layout)** with standard fields lets the log aggregator index `correlationId` and `orderId`. Ship logs to the corporate SIEM/log platform (Splunk, ELK, Datadog) through a log appender or the platform's log forwarding. *On CloudHub 2.0, check the current log forwarding options and retention limits for your subscription.*

## 5. Audit trails

| Audit question | Source |
|----------------|--------|
| Who called which API, when, and with what result? | API Manager analytics + gateway logs (client ID, status, latency) |
| What happened to order X across systems? | `audit_log` table: each state transition with correlationId, actor (system/client), from→to, timestamp |
| Who replayed or edited messages? | Replay API audit records (user, reason, approval, message IDs) |
| Who deployed what, when? | CI/CD logs + Runtime Manager audit log (Anypoint audit logging) |
| Who changed SAP data? | SAP change documents (CDHDR/CDPOS) |

**Integrity:** audit tables are insert-only for the app user (no UPDATE/DELETE grants). Retention follows the legal requirement (7 years for invoice-related records, as assumed for AIM).

## 6. Security checklist (pre-go-live excerpt; full checklist in [16.4](../16-project-documents/04-operations-documents.md))
- [ ] All Exp APIs have authentication policies. No "temporarily open" endpoints
- [ ] No `insecure="true"` TLS. TLS 1.2+ only
- [ ] No secrets in Git. A secrets scan passes in CI
- [ ] PII masking verified in logs (sample a QA run)
- [ ] Fine-grained authorisation tested (supplier A can't access supplier B's PO)
- [ ] Certificate inventory complete, with expiry alerts
- [ ] Least-privilege users confirmed by the SAP security, DBA and Salesforce admins
- [ ] Pen test / DAST findings closed or risk-accepted

## Interview angle
**Q: "A developer logged a full order payload at INFO in production. What do you do?"**
> "Treat it as a data-protection incident, not just a code smell. Find out how long the logs were exposed and who could access them. Work with security on whether purging or access restriction is required. Fix the code: log IDs, and mask at DEBUG. Then add a preventive control. A code-review checklist item helps, but an automated check is better, such as a lint rule that flags loggers referencing `payload`, plus masking in the logging framework as a safety net."

Next section: [11 — Deployment & CI/CD](../11-deployment-cicd/01-deployment-options.md)
