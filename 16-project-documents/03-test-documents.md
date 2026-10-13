# 16.3 — MUnit Test Plan, Integration Test Scenarios, Performance Test Plan

`Essential` · Covers documents **8, 9 and 10**.

## 8. MUnit test plan — `order-mgmt-prc-api`

```markdown
# MUnit Test Plan – order-mgmt-prc-api v1.4   Owner: senior dev   Reviewed by: tech lead
## Scope
All implementation flows, DW modules, error handlers. Excludes: APIkit-generated routing.
## Approach
- Connectors mocked by doc:name; DB uses embedded H2 (PostgreSQL mode) for idempotency/outbox tests.
- Golden-file tests for all mappings (input/expected in src/test/resources/golden/).
- Coverage gate: application ≥ 80%, each impl flow ≥ 70%.
## Environments
Local + CI (mvn verify). No external connectivity required.
## Entry/exit criteria
Entry: LLD approved, mapping spec signed. Exit: all tests pass, coverage met, no skipped tests.
```

| ID | Flow/module | Scenario | Type | Mocks | Key assertions | Status |
|----|-------------|----------|------|-------|----------------|--------|
| U-01 | prc-create-order-flow | Full stock happy path | Positive | CRM, WMS, SAP | status CONFIRMED. 1 SAP call. Outbox row | ✅ |
| U-02 | prc-create-order-flow | Partial stock | Positive | WMS short | BACKORDERED. Shortage event | ✅ |
| U-03 | prc-create-order-flow | Duplicate key, same body | Negative | — | Same response. SAP calls = 1 in total | ✅ |
| U-04 | prc-create-order-flow | Key reuse, different body | Negative | — | `AIM:IDEMPOTENCY_KEY_REUSED` | ✅ |
| U-05 | prc-create-order-flow | Customer blocked | Negative | CRM BLOCKED | `AIM:CUSTOMER_INVALID`. SAP not called | ✅ |
| U-06 | prc-create-order-flow | SAP business error | Negative | SAP 422 | Reservation released (verify 1). Error propagated | ✅ |
| U-07 | prc-create-order-flow | SAP unknown outcome | Negative | SAP 504 | PENDING_ERP. 202. No release | ✅ |
| U-08 | sys-sap-create-flow | Timeout → lookup found | Negative | create TIMEOUT, lookup found | 201 recovered | ✅ |
| U-09 | dwl canonical→BAPI | Golden file, 2 lines | Mapping | — | XML equals expected | ⬜ |
| U-10 | global error handler | Unknown error | Negative | — | 500 + AIM-GEN-5001, no internals | ⬜ |

## 9. Integration test scenarios (SIT)

Full table: [09.2 §2](../09-testing/02-integration-contract-regression.md). The document format adds:

| Field | Example |
|-------|---------|
| Scenario ID / BR trace | SIT-02 / BR-03 |
| Preconditions & test data | Customer 100234. Material VLV-BL-050 stock 5 in DC-US-01. Supplier info record SUP-0042 |
| Steps | 1. POST order (40 EA). 2. Wait ≤ 15 min. 3. Check ME23N |
| Expected | 201 BACKORDERED. PR/PO for 35 EA to SUP-0042. PO transmitted (SupplierHub sandbox shows it) |
| Evidence | Screenshots, correlation ID, Postman run export |
| Result / defect ID | Pass / — |

## 10. Performance test plan

```markdown
# Performance Test Plan – Order Intake   v1.0
## Objectives
Validate NFR-P1 (10 orders/s peak), NFR-P2 (p95 ≤ 4 s), NFR-A2 (graceful 202 under SAP slowness).
## Scope
customer-order-exp-api → order-mgmt-prc-api → sys APIs (SAP/WMS/CRM stubbed with latency model).
## Workload model
| Profile | Rate | Duration | Notes |
| Baseline | 2/s | 30 min | normal day |
| Peak     | 10/s | 30 min | quarter-end |
| Spike    | 25/s | 5 min  | burst, verify rate limit/spike control |
| Soak     | 3/s | 4 h    | leaks |
| SAP-degraded | 10/s, SAP p95 = 7 s | 20 min | expect 202 ratio ↑, no 5xx storm |
Order size distribution: 70% 1–10 lines, 25% 11–50, 5% 51–200.
## Environment
PERF Private Space, prod-equivalent sizing; PostgreSQL perf instance; MQ perf queues.
## Metrics & pass criteria
p95 ≤ 4 s @10/s; error rate < 0.5% (excl. expected 202); no pool waits > 100 ms p95;
heap < 75% steady state; DLQ = 0; outbox oldest PENDING < 10 s.
## Tools
JMeter 5.x, Anypoint Monitoring, PostgreSQL stats, MQ stats.
## Risks
SAP stub realism; test data uniqueness (idempotency keys unique per request).
## Reporting
Results vs baseline, bottleneck analysis, tuning changes, sign-off by architect.
```

Next: [16.4 Operations documents](04-operations-documents.md)
