# 16.4 — Security Checklist, Deployment & Rollback Runbook, Monitoring Checklist, Troubleshooting Guide, Cutover Plan

`Essential` · Covers documents **11, 12, 13, 14 and 15**.

## 11. Security checklist (per API, before PROD)

| # | Control | Evidence | ✔ |
|---|---------|----------|---|
| S-01 | Inbound authentication policy applied (JWT/OAuth or client ID + network isolation) | API Manager screenshot / export | ☐ |
| S-02 | Scopes or contracts restrict methods to the intended consumers | Policy config | ☐ |
| S-03 | Rate limiting / spike control configured to the capacity plan | Policy config | ☐ |
| S-04 | Threat protection (JSON/XML limits) for external APIs | Policy config | ☐ |
| S-05 | TLS 1.2+. No `insecure` trust stores. Certificates in the inventory with expiry alerts | Code scan + inventory | ☐ |
| S-06 | mTLS / HMAC for partner callbacks where agreed | Test evidence | ☐ |
| S-07 | Fine-grained authorisation (object ownership) tested | MUnit/SIT case | ☐ |
| S-08 | Secrets only in secure properties / vault. Secrets scan clean | CI report | ☐ |
| S-09 | PII fields identified and masked in logs | Log sample from QA | ☐ |
| S-10 | Least-privilege backend users (SAP S_RFC, DB grants, SF permission set) | Approvals from admins | ☐ |
| S-11 | Input validation (RAML strictness, parameterised SQL/SOQL) | Code review | ☐ |
| S-12 | Audit events for state changes and replays | Test evidence | ☐ |
| S-13 | Dependency vulnerability scan: no critical/high open | CI report | ☐ |
| S-14 | Pen test / DAST for internet-facing APIs | Report ID | ☐ |

## 12. Deployment & rollback runbook — `order-mgmt-prc-api 1.4.0`

```markdown
## Pre-checks (T-30 min)
1. Change CHG-2231 approved; window 20:00–21:00 CET (outside order peak).
2. Confirm PROD properties: order.asyncFallback.enabled=true, new key sap.lookup.delayMs=500.
3. Confirm rollback artifact 1.3.2 available in Exchange.
4. Announce in #aim-integration-ops.
## Deploy
5. Pipeline job "order-mgmt-prc-api / deploy-prod" with version 1.4.0 → approve.
6. Watch Runtime Manager: replicas 2/2 Running (rolling update ~5 min).
## Verify (T+10 min)
7. Smoke: ./scripts/smoke.sh prod   (health, auth, read path, error contract)
8. Dashboards (15 min): 5xx < 0.5%, p95 < 2 s, 202 ratio unchanged, DLQ 0, outbox age < 10 s.
9. Business check: Sales Ops confirms 3 live orders confirmed in Salesforce.
## Rollback criteria (any one)
- 5xx > 2% for 5 min; p95 > 4 s for 10 min; data incorrect (any).
## Rollback steps
R1. Pipeline job "deploy-prod" with version 1.3.2 (pre-approved in CHG).
R2. Revert property sap.lookup.delayMs (not used by 1.3.2 — harmless if left).
R3. Re-run smoke tests; announce rollback; open incident if data impact.
## Post-deployment
10. Close change with evidence; hypercare on-call: <name>, 3 days.
```

## 13. Monitoring & alerting checklist (per API)

| Item | Configured? |
|------|------------|
| Dashboard: rate, errors (4xx/5xx split), p95/p99, CPU, heap, GC | ☐ |
| Per-dependency latency + error panels (SAP, WMS, CRM, DB) | ☐ |
| Queue panels: depth, oldest age, DLQ depth, redeliveries | ☐ |
| Business panels: orders/hour, 202 ratio, PENDING_ERP, BACKORDERED ratio | ☐ |
| Alerts with severity, routing (on-call), runbook link | ☐ |
| Log fields: correlationId, orderId, flow, event, durationMs indexed in the log platform | ☐ |
| Synthetic checks: health (1 min), mTLS handshake to partners (daily) | ☐ |
| Absence alerts: batch completion, expected partner files/events | ☐ |
| Certificate expiry alerts (60/30/14/7 days) | ☐ |
| Alert test performed (fire a test alert end to end) | ☐ |

## 14. Production troubleshooting guide (structure)

```markdown
# Troubleshooting Guide – AIM Order Integration
## How to start (method)        → 13.0 (S-I-S-H-T-F-L)
## Where to look
- Logs: <log platform> index aim-prod-*, search correlationId:"..." or orderId:"..."
- Dashboards: "AIM Order Flow", "AIM Messaging", "AIM SAP Dependency"
- DB views: v_order_timeline(order_id), v_pending_erp, v_outbox_backlog
- MQ: Anypoint MQ console (read-only role), DLQ via replay API
## Symptom → runbook index
| Symptom | Runbook |
| 202 ratio high / PENDING_ERP growing | RB-SAP-01/02 (scenarios 1, 2) |
| Duplicate POs/invoices reported      | RB-PROC-01 (scenarios 2, 4) / RB-BILL-01 (08.5 case 5) |
| Queue age alert                      | RB-MQ-01 (scenario 5) |
| DLQ > 0                              | RB-MQ-02 (replay procedure 08.4) |
| Heap / OOM restarts                  | RB-PERF-01 (scenario 6) |
| DB pool errors                       | RB-DB-01 (scenario 9) |
| TLS/PKIX errors                      | RB-SEC-01 (scenario 14) |
| Inventory recon diffs spike          | RB-INV-01 (scenario 11) |
## Escalation
L2 → L3 on-call (pager) → SAP Basis / WMS vendor / MuleSoft support (ticket template)
## Safe actions L2 may take
Pause/resume consumers, replay DLQ (≤ 100 msgs, otherwise L3 approval), restart app,
toggle order.asyncFallback.enabled. NOT allowed: edit payloads, DB updates, deploys.
```

## 15. Cutover plan (go-live of order integration)

**Context:** moving from manual re-keying to the integrated flow during a weekend. Salesforce goes live on Monday 06:00 plant time.

| # | When | Activity | Owner | Go/No-go check |
|---|------|----------|-------|----------------|
| C-1 | T-14 d | Final UAT sign-off. Performance test passed | QA lead | Sign-off doc |
| C-2 | T-7 d | PROD connectivity check (DNS, firewall, TLS) for all backends | Integration + Network | All green |
| C-3 | T-7 d | Partner readiness: SupplierHub/carrier PROD credentials, certs exchanged | Partner mgr | Confirmations |
| C-4 | T-3 d | SAP transports (custom field, BAdI duplicate check) in PROD | SAP lead | Transport log |
| C-5 | Fri 18:00 | **Order freeze** in the old manual process. Last manual orders keyed | Sales Ops | Count reconciled |
| C-6 | Fri 20:00 | Deploy all apps 1.0.0 to PROD. Policies applied | Release mgr | Smoke tests green |
| C-7 | Sat 09:00 | **Data migration**: open Salesforce orders not yet in SAP → load via a one-off batch with idempotency keys | Integration | Recon: counts match |
| C-8 | Sat 14:00 | Dress rehearsal: 5 synthetic orders end to end (test customer), then cancel | QA + Sales Ops | All steps pass |
| C-9 | Sun 18:00 | **Go/No-go meeting** | Program mgr | All owners ✅ |
| C-10 | Mon 06:00 | Enable the Salesforce "Submit to SAP" button (feature flag) | SF admin | First 10 orders monitored |
| C-11 | Mon–Wed | **Hypercare**: war room, hourly checks, daily recon reports | Integration on-call | No P1/P2 open |
| **Rollback** | Any time before C-10 | Keep the button disabled and continue the manual process. After C-10: disable the button, re-key failed orders manually (list from the integration DB) | Program mgr | — |

**Why a feature flag at C-10:** deployment (technical) and release (business) are decoupled. Rolling back is just a toggle.

Next: [16.5 Incident report & postmortem](05-incident-postmortem.md)
