# 01.3 — Functional and Non-Functional Requirements

`Essential` · *All numbers are **illustrative assumptions** for practice. In a real project they come from the business and from capacity analysis.*

## 1. Functional requirements (FR)

| ID | Requirement | Priority | Acceptance criteria (example) |
|----|-------------|----------|-------------------------------|
| FR-01 | Accept customer orders from Salesforce and the B2B portal through one API | Must | `POST /api/v1/orders` returns `201` (confirmed) or `202` (accepted, ERP pending) |
| FR-02 | Validate the customer (exists, active, not credit-blocked) | Must | A blocked customer returns `422 AIM-ORD-4223` |
| FR-03 | Validate materials and units of measure | Must | An unknown material returns `422` with line details |
| FR-04 | Price the order with SAP pricing | Must | The response contains SAP net value and currency |
| FR-05 | Check availability across DCs | Must | Per-line available quantity and promise date |
| FR-06 | Soft-reserve available stock for 30 min (TTL) | Must | The reservation is released if the order is not confirmed |
| FR-07 | Create the SAP sales order exactly once per external order | Must | A repeated request with the same `Idempotency-Key` returns the original response |
| FR-08 | Raise production demand for make-to-order items | Must | SAP production order created and released to MES |
| FR-09 | Raise procurement for buy items that are short | Must | One PO line per shortage line. No duplicates |
| FR-10 | Receive supplier confirmations and ASNs | Must | Confirmed delivery dates posted to the SAP PO |
| FR-11 | Process WMS goods receipts and update reservations | Must | Backordered lines become reserved |
| FR-12 | Consume MES production completion events | Must | SAP confirmation + goods receipt of FG + WMS put-away |
| FR-13 | Book shipments with carriers on dispatch | Must | Tracking number stored and pushed to Salesforce |
| FR-14 | Process carrier tracking webhooks and proof of delivery | Must | Order status becomes `DELIVERED` |
| FR-15 | Trigger SAP billing and sync the invoice to Salesforce | Must | Exactly one invoice per delivery |
| FR-16 | Synchronise order status to Salesforce at each milestone | Must | Status visible within 60 s (assumption) |
| FR-17 | Nightly bulk inventory snapshot from WMS via SFTP | Must | 2M records processed, with failures reported per record |
| FR-18 | Reconcile WMS vs SAP inventory and Mule vs SAP orders | Must | Report + auto-correction for allow-listed differences |
| FR-19 | Controlled replay of failed messages from the DLQ | Must | Operator replays with an audit trail, without creating duplicates |
| FR-20 | Publish operational events to analytics | Should | Every status change is emitted as an event |
| FR-21 | Order status query API | Must | `GET /api/v1/orders/{orderId}` |
| FR-22 | Order cancellation before dispatch | Should | Saga compensation for the reservation, SAP order and PO |

## 2. Non-functional requirements (NFR)

### Performance and throughput (assumptions)

| ID | Metric | Target |
|----|--------|--------|
| NFR-P1 | Order intake throughput | 2 orders/s average, **10 orders/s peak** (quarter-end), bursts of 25/s for 5 min |
| NFR-P2 | Order API latency (sync path) | p95 ≤ **4 s**, p99 ≤ 8 s, hard timeout 15 s at the client |
| NFR-P3 | Availability check API | p95 ≤ 800 ms |
| NFR-P4 | Event propagation to Salesforce | p95 ≤ 60 s |
| NFR-P5 | Nightly inventory batch | 2M records within a **60-minute** window |
| NFR-P6 | Tracking webhook ingestion | 200 events/s burst, ack ≤ 300 ms |

### Availability, scalability and recovery

| ID | Requirement | Target (assumption) | How it is achieved |
|----|-------------|---------------------|--------------------|
| NFR-A1 | Experience API availability | 99.9% monthly | ≥ 2 replicas, multi-AZ, health checks |
| NFR-A2 | Graceful degradation when SAP is down | Accept orders as `202 PENDING_ERP` | Async fallback + retry consumer |
| NFR-S1 | Horizontal scalability | Scale replicas without code change | Stateless apps. State lives in DB/OSv2/MQ |
| NFR-R1 | RPO for accepted orders | **0** (no loss after ack) | Persist before responding. Outbox |
| NFR-R2 | RTO | ≤ 1 h for the region failure runbook | IaC, multi-region DR plan |
| NFR-R3 | Message durability | No silent loss | Anypoint MQ persistence, DLQ, alerting |

### Security, compliance and auditability

| ID | Requirement |
|----|-------------|
| NFR-SEC1 | All external APIs use OAuth 2.0 client credentials (Salesforce, portal) or mTLS (suppliers, carriers) |
| NFR-SEC2 | TLS 1.2+ everywhere. No plain HTTP outside localhost |
| NFR-SEC3 | Secrets only in secure properties or a secrets manager. Never in Git |
| NFR-SEC4 | PII (contact names, phone, email, addresses) is masked in logs |
| NFR-SEC5 | Least-privilege technical users in SAP (RFC authorisations limited to the required BAPIs) |
| NFR-AUD1 | Every order state transition is recorded with timestamp, actor and correlation ID |
| NFR-AUD2 | Audit retention: 7 years for invoice-related records. Operational logs 30 days hot, 1 year archived |

### Operability

| ID | Requirement |
|----|-------------|
| NFR-O1 | A correlation ID is propagated through every hop (HTTP header `x-correlation-id`, MQ property) |
| NFR-O2 | Structured JSON logs with standard fields (app, env, flow, correlationId, orderId, durationMs) |
| NFR-O3 | Dashboards: throughput, error rate, latency, queue depth, DLQ count, SAP response time |
| NFR-O4 | Alerts on DLQ > 0, queue age > 5 min, error rate > 2%, cert expiry < 30 days |
| NFR-O5 | Runbooks for each top-10 incident type |

## 3. How requirements drive design decisions (interview gold)

| Requirement | Design decision it forces |
|-------------|---------------------------|
| NFR-R1 (RPO 0) + NFR-A2 | **Persist-then-respond** and the **outbox pattern**. Without them a crash after the SAP call loses the event |
| FR-07 (exactly once in SAP) | Idempotency key + **lookup-by-external-reference** after a timeout. Blind retries are never used |
| NFR-P2 (p95 4 s) | Parallel scatter-gather for the validations, timeout budgets, cached master data |
| NFR-P1 bursts + SAP capacity | **Queue-based load levelling**. At peak, intake switches to `202 Accepted` |
| FR-17 (2M records / 60 min) | **Batch Job** with streaming, tuned block size, no full payload in memory |
| FR-09 (no duplicate POs) | **Idempotent receiver** in the Procurement consumer + supplier-side idempotency key |
| NFR-SEC1 (suppliers by mTLS) | Separate Supplier Exp API with its own policies and network ingress |

> **Practice:** Pick any three NFRs and explain how you would *test* that they are met. For example, NFR-P2 is checked by a JMeter run at 10 orders/s for 30 minutes with mocked SAP latency of 1.5 s, asserting p95 ≤ 4 s. See [09.3](../09-testing/03-performance-and-smoke-testing.md).

Next: [02 — Architecture](../02-architecture/01-system-context.md)
