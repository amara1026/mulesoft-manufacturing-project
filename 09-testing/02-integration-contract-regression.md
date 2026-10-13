# 09.2 — Integration, Contract and Regression Testing

`Essential`

## 1. Environments and what each test level needs

| Level | Environment | Backends | Owner |
|-------|-------------|----------|-------|
| Unit (MUnit) | Developer laptop / CI | Mocked | Developer |
| Component / contract | DEV CloudHub | **Mock services** (Anypoint mocking service, WireMock, or the mini project's mock flows) | Developer + QA |
| Integration (SIT) | QA | **Real test systems**: SAP QA client, WMS test, Salesforce sandbox | QA + integration team |
| UAT | UAT (prod-like) | SAP pre-prod, real-ish data | Business users |
| Performance | PERF (prod-sized) | SAP stubs with realistic latency, or a dedicated SAP perf client | Perf engineer |

**Test data is the hardest part in manufacturing.** SAP QA needs customers, materials, stock, pricing conditions and open periods. Book the test data setup with the SAP team **per sprint**, or SIT stalls.

## 2. Integration test scenarios (SIT) — sample

| ID | Scenario | Preconditions | Steps | Expected result |
|----|----------|---------------|-------|-----------------|
| SIT-01 | Order fully in stock | Customer 100234 active. 10 × PMP-CF-200 in DC-US-01 | POST order (5 pumps) | 201. SAP order visible in VA03. WMS reservation. Salesforce status Confirmed ≤ 60 s |
| SIT-02 | Partial stock → PO | 5 valves in stock, supplier SUP-0042 info record | Order 40 valves | 201 BACKORDERED. PR/PO for 35 in SAP (ME23N). PO sent to supplier mock |
| SIT-03 | Duplicate submit | — | Same request twice, same key | Identical responses. Exactly 1 SAP order |
| SIT-04 | SAP down | Stop the SAP gateway access (firewall rule in QA) | Submit order | 202 PENDING_ERP. After restore, the order is created within 5 min. Exactly 1 order |
| SIT-05 | Supplier confirmation out of order | PO exists | Send seq 2, then seq 1 | SAP PO confirmations applied in sequence 1 → 2 |
| SIT-06 | Dispatch → booking → POD → invoice | Order CONFIRMED + delivery | WMS dispatch webhook, carrier POD webhook | Shipment booked, PGI posted, invoice created once, Salesforce Invoiced |
| SIT-07 | Replay DLQ message | Force a consumer failure, then fix it | Replay via API | Processed once. Audit row written |
| SIT-08 | Batch with bad rows | File with 1,000 rows, 5 invalid | Drop the file on SFTP | 995 processed, 5 in the error report. File archived |
| SIT-09 | Expired token | Revoke the Salesforce token mid-run | Status sync event | Token refreshed automatically. Event processed |
| SIT-10 | Invalid supplier certificate | Supplier presents an untrusted cert | POST confirmation | TLS handshake fails. Nothing enqueued. Security log entry |

## 3. Contract testing

**Goal:** catch breaking changes **before** they reach consumers.

| Direction | Technique on AIM |
|-----------|------------------|
| Provider conforms to its own RAML | APIkit validates requests at runtime. **Newman** tests validate responses against the JSON schemas derived from RAML types |
| Consumer expectations | Each consumer team contributes example requests/responses (contract examples) to the API repo. CI replays them against the new version |
| Spec-level breaking-change detection | Compare the new RAML/OAS with the last published Exchange version. Fail the PR on removed fields, new required fields or type changes |
| Events | Publish JSON Schemas for each event type (schemaVersion). Consumer tests validate sample events. Producers can't remove fields within a major version |

**Newman in CI (example):**
```bash
newman run postman/aim-order-integration.postman_collection.json \
  -e postman/env-qa.json --reporters cli,junit --reporter-junit-export results/contract.xml
```

Postman test snippet (response contract):
```javascript
pm.test("201 contract", function () {
  pm.response.to.have.status(201);
  const b = pm.response.json();
  pm.expect(b).to.have.property("orderId").that.matches(/^AIM-[0-9]{8}-[A-Z0-9]{8}$/);
  pm.expect(b.status).to.be.oneOf(["CONFIRMED", "BACKORDERED"]);
  pm.expect(pm.response.headers.get("x-correlation-id")).to.exist;
});
```

## 4. Regression testing

- **Automated regression pack** = MUnit (every build) + Newman SIT subset (nightly on QA) + golden-file mapping tests.
- **Trigger a broader regression when:** a shared fragment changes, the runtime is upgraded (e.g. 4.6 → 4.9 with Java 17), connector versions change, or a SAP transport changes BAPI behaviour.
- **Runtime upgrade regression checklist:** Java 17 compatibility of all connectors and custom modules, DW behaviour changes (check the release notes), TLS defaults, and performance baseline comparison.

## 5. Negative and chaos testing (senior-level)

| Experiment | How | What you learn |
|------------|-----|----------------|
| Kill a replica mid-order | Restart the app during a load test | Do idempotency + outbox prevent loss and duplicates? |
| Inject SAP latency 8 s | Mock SAP with a delay (the mini project's `TIMEOUT-` prefix) | Timeout recovery, 202 ratio, circuit breaker |
| MQ unavailable | Block MQ egress in QA | Outbox accumulation and drain |
| DB pool exhaustion | Set `maxPoolSize=2` under load | Fail-fast behaviour, error codes, alerts |
| Duplicate storm | Replay 1,000 identical events | Inbox efficiency, no duplicates downstream |

Next: [09.3 Performance & smoke testing](03-performance-and-smoke-testing.md)
