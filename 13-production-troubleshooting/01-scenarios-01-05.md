# 13.1 — Troubleshooting Scenarios 1–5

*All incidents below are illustrative training scenarios, not real AIM history.*

---

## Scenario 1 — SAP becomes unavailable during peak order volume

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | 10:05 on quarter-end day: order API p95 jumps from 1.4 s to 9 s, then 5xx/202 responses. Salesforce users see "Pending ERP". Thousands of orders affected. **P1** |
| **Reproduce** | In PERF, block SAP connectivity (firewall rule) or inject 10 s latency in the SAP stub at 10 req/s |
| **Diagnose** | Per-hop latency (logs with `durationMs` per outbound call) shows SAP Sys calls at 6 s (timeout). Error types: `HTTP:TIMEOUT` from the SAP Sys API. Inside it: `SAP:CONNECTIVITY` / JCo `RFC_ERROR_COMMUNICATION`. Check the VPN tunnel status, the SAP gateway, and SAP system status (with Basis: SM51/SM50 work processes, dumps in ST22) |
| **Signals** | 202 ratio > 50%. PENDING_ERP count rising. SAP Sys error rate. JCo pool waits. VPN tunnel metrics |
| **Root cause (example)** | The SAP application server ran out of dialog work processes due to a long-running month-end report. RFC calls queued and timed out |
| **Immediate mitigation** | Confirm the order API is in **degraded mode** (202 + persisted, breaker open), so no orders are lost. **Reduce** retry-consumer concurrency so the recovering SAP isn't flooded. Work with SAP Basis to free work processes or move the report. Communicate to sales ops: "orders captured, confirmations delayed" |
| **Permanent fix** | Dedicated RFC server group / logon group for integration traffic (SAP-side bulkhead). Circuit breaker tuned. ERP retry consumer drains at a controlled rate after recovery |
| **Prevention & alerts** | Alert on 202 ratio > 10%, SAP Sys p95 > 3 s, PENDING_ERP > 100. Month-end job calendar coordinated with integration peaks |
| **Alternatives** | Fully async order intake (always 202) removes the dependency, but costs immediate confirmations |
| **Interview answer** | "First I'd confirm we're failing safely: orders persisted and accepted as pending, not lost or duplicated, and the circuit breaker stopping us hammering SAP. Then I'd use the per-hop timings to confirm SAP as the bottleneck and work with SAP Basis on the cause, here exhausted work processes. Recovery is controlled: the retry consumer drains pending orders at a rate SAP can take, using lookup-then-create so nothing duplicates. Long term: a dedicated SAP logon group for integration and peak-aware job scheduling." |

---

## Scenario 2 — SAP commits a purchase order, but MuleSoft times out

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | Buyers report **duplicate POs** to SUP-0042 for the same shortage (4500012345 and 4500012351). Excess stock, supplier confusion. **P2** (financial) |
| **Reproduce** | SAP stub commits, then delays its response beyond the timeout. The consumer's retry creates again (the old code had no lookup) |
| **Diagnose** | Search the logs by business key `ORD-123:VLV-BL-050:1000`: attempt 1 `HTTP:TIMEOUT` after 6 s, redelivery attempt 2 → `PO_CREATED 4500012351`. SAP: both POs carry the same reference in the header text, with creation times 6.4 s apart |
| **Root cause** | A timeout was treated as a failure, the consumer retried with a **blind create**, and the business key wasn't checked against SAP |
| **Immediate mitigation** | Pause the procurement consumer (stop the flow / scale to 0) to prevent more duplicates. Identify all duplicate POs by reference with an SAP query. Buyers cancel the duplicates *before* suppliers ship and notify the suppliers |
| **Permanent fix** | (1) `procurement_request` table with a UNIQUE business key. (2) On timeout → **lookup by reference** → found = success. (3) Every retry is lookup-then-create. (4) A sweeper for stale IN_PROGRESS keys. (5) An SAP-side duplicate check on the external reference |
| **Prevention & alerts** | Daily "duplicate PO by reference" recon report (should always be 0). MUnit test for timeout → lookup. Chaos test in QA |
| **Alternatives** | Asynchronous IDoc-based PO creation (tRFC with TID gives SAP-side exactly-once per TID) |
| **Interview answer** | "A timeout means 'outcome unknown'. Retrying a create blindly is the bug. I make PO creation idempotent with a business key stored in SAP and enforced uniquely in our DB. After a timeout or on any retry, we look up by that key first and only create if it's not there. I'd also clean up the existing duplicates with procurement and add a daily duplicate-reference check so this can never be silent again." |

---

## Scenario 3 — Inventory is reserved, but production or ERP order creation fails

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | Warehouse reports stock "reserved" for orders that don't exist in SAP. Available stock is understated, so new orders are backordered unnecessarily. **P2** |
| **Reproduce** | SAP returns a business error (credit block) after the reservation. Old code: the compensation call failed (WMS 503) and nobody retried it |
| **Diagnose** | Query reservations with no matching `order_state` CONFIRMED/BACKORDERED. Logs show `AIM:SAP_BUSINESS_ERROR`, then `compensate-release-reservation` failed with `HTTP:SERVICE_UNAVAILABLE`, and the error was swallowed by on-error-continue |
| **Root cause** | Compensation was best-effort and in-line. Its failure was logged but not retried. The reservation had **no TTL** |
| **Immediate mitigation** | Release orphaned reservations via a script/API after verifying in SAP that no order exists |
| **Permanent fix** | (1) WMS reservations with a **TTL** (30 min) that auto-expire unless confirmed. (2) A compensation failure publishes `reservation.release-required` to a queue with retry + DLQ. (3) A confirm-reservation step after SAP success. (4) Reconciliation: reservations older than the TTL without an order |
| **Prevention & alerts** | Metric "compensation failures". Alert on orphan reservations > 0 |
| **Alternatives** | Reserve *after* SAP confirmation (no orphans, but a race window where stock is promised by SAP ATP and taken by another order). Let SAP own reservations (ATP + schedule lines) and make the WMS reservation a downstream event |
| **Interview answer** | "Compensations are distributed operations too: they can fail, so they need the same reliability as forward steps. They go to a retry queue, not a log line. I'd also make the reservation self-healing with a TTL, so a failed compensation degrades to a 30-minute delay instead of permanently locked stock. And I'd distinguish definitive failures, where we compensate, from unknown outcomes, where we don't." |

---

## Scenario 4 — Duplicate messages create duplicate purchase orders

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | After an MQ hiccup, 37 shortages produced 2 POs each. **P2** |
| **Reproduce** | Consumer processing time 70 s > ack timeout 60 s, so the message is redelivered to the second replica while the first is still processing |
| **Diagnose** | MQ metrics: redelivery count rising. Logs: the same `eventId` processed by replica-1 and replica-2 ~60 s apart. The inbox insert ran **after** PO creation (wrong order). The supplier API was slow that day (25 s), so processing time crossed the ack timeout |
| **Root cause** | Ack timeout < processing time, plus a missing pre-processing business key claim |
| **Immediate mitigation** | Pause the consumer. Cancel duplicate POs. Raise the ack timeout as a temporary measure |
| **Permanent fix** | Claim the business key **before** side effects (IN_PROGRESS → COMPLETED). The second delivery sees IN_PROGRESS → nack with delay. Set the ack timeout > p99 processing time with margin. Reduce processing time by moving the supplier transmission into a separate step/queue |
| **Prevention & alerts** | Alert on redelivery rate > 1%. Load-test with a slow supplier stub |
| **Alternatives** | Lock-extension / renew-lock patterns if the broker supports them. Smaller units of work per message |
| **Interview answer** | "At-least-once delivery plus long processing means concurrent duplicates, not just sequential ones. I'd fix it in layers: claim the business key before doing anything, so a concurrent duplicate sees 'in progress' and backs off; make the ack timeout comfortably exceed processing time; and split slow partner calls into their own step. Inbox dedupe alone doesn't catch duplicates that are processed concurrently." |

---

## Scenario 5 — A message queue backlog keeps growing

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | `status-sync-q` depth went from ~0 to 48,000 over 3 hours, and the oldest message is 2.5 h old. Salesforce statuses are stale and customer service is blind. **P2** |
| **Reproduce** | Consumer throughput < producer rate (e.g. a Salesforce latency spike, or a consumer stuck on a poison message with no max deliveries) |
| **Diagnose** | Compare **publish rate vs consume rate**. Consumer error rate: high (retrying) or low (just slow)? Per-message processing time. Salesforce API responses: `REQUEST_LIMIT_EXCEEDED`? `UNABLE_TO_LOCK_ROW`? Replica count, flow `maxConcurrency`. A recent deploy that changed concurrency? |
| **Root cause (example)** | Salesforce daily API limit nearly exhausted → throttled responses. Consumer retries consumed even more API calls |
| **Immediate mitigation** | Stop the retry amplification (nack with longer delay). Prioritise: process only the latest status per order (collapse duplicates). Coordinate with the Salesforce admin about the limit |
| **Permanent fix** | **Coalesce updates**: one upsert per order with the latest status. Use **Composite/Bulk API** for batches (200 records per call). Monitor API consumption |
| **Prevention & alerts** | Queue age > 10 min. Consume/publish ratio < 0.8 for 15 min. Salesforce API usage > 70% of the daily limit |
| **Alternatives** | Salesforce reads status from an external object / Salesforce Connect (no pushes). Platform Events as a target |
| **Interview answer** | "A growing backlog means consumption is slower than production. I'd find out why: errors and retries, slowness, or too little concurrency. Scaling consumers only helps if the downstream has capacity. Here the downstream was Salesforce's API limit, so more consumers would make it worse. The fix was to reduce calls: coalesce to the latest status per order and use bulk/composite calls. Then I'd add alerts on queue age and API consumption." |

Next: [Scenarios 6–10](02-scenarios-06-10.md)
