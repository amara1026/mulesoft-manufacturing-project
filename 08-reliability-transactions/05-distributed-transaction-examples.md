# 08.5 — Six Manufacturing Distributed-Transaction Cases (Worked Answers)

`Essential` — each case is a likely interview question. Each one follows the same structure: **situation → what's actually guaranteed → design → residual risk**.

---

## Case 1 — SAP creates the purchase order, but the caller times out

**Situation:** The procurement consumer calls `BAPI_PO_CREATE1` and the HTTP call to the SAP Sys API times out after 6 s. SAP finishes and commits PO `4500012345` at 6.4 s.
**Guarantee available:** SAP's commit is atomic within SAP. We get no confirmation of it.
**Design**
1. The PO request carries the **business key** `ORD-123:VLV-BL-050:1000` in a searchable SAP field (header text / external reference / a custom field agreed with the SAP team).
2. On timeout: **lookup by key** (after a short delay) → found → record the PO number and complete.
3. Not found → nack with delay. The next attempt does **lookup-then-create** again.
4. The `procurement_request` row stays `IN_PROGRESS`. A sweeper resolves any row older than 30 minutes using the same lookup.

**Residual risk:** SAP commits *after* our second lookup (a very slow LUW), and we create again. Mitigate with an increasing delay between the timeout and the lookup, and an SAP-side duplicate check on the external reference (enhancement / BAdI). The PO reconciliation report catches anything left.

---

## Case 2 — Inventory reservation succeeds, but ERP processing fails

**Situation:** The WMS reserved 5 pumps (RSV-88121), then SAP rejected the order (customer credit block).
**Design:** this is a **definitive business failure**, so **compensate**: `DELETE /reservations/RSV-88121` (idempotent), status REJECTED with the SAP message, response 422.
- If the compensation call fails, retry it via a queue. The **reservation TTL** (30 min) is the safety net, so stock is never locked forever.
- If SAP **timed out** instead: don't compensate. Follow Case 1-style recovery and keep the reservation, because SAP might have created the order.

**Residual risk:** during the TTL window, the reserved stock is unavailable to other orders. Keep the TTL short and explicit.

---

## Case 3 — The database write succeeds, but event publication fails

**Situation:** `order_state` is committed as CONFIRMED, and the Anypoint MQ publish fails (MQ regional issue).
**Design:** the **transactional outbox** ([07.5](../07-integration-patterns/05-transaction-patterns.md), [08.3](03-outbox-inbox-saga.md)). The event row is committed with the state, and the relay retries until MQ recovers.
**Guarantee:** no lost events (at-least-once). Possible duplicate publication, handled by consumer inbox dedupe.
**Monitoring:** age of the oldest PENDING outbox row > 5 min triggers an alert. During an MQ outage this alert fires, but no data is lost, and the runbook says "wait and watch".

---

## Case 4 — A shipment confirmation arrives before the warehouse dispatch event

**Situation:** The carrier's `PICKED_UP` webhook (via the TMS) is processed at 10:02:05. The WMS `dispatch-ready` event is delayed in its queue and processed at 10:02:40.
**Design options**
1. **Converge regardless of order (preferred):** both events **upsert** the same `shipment` record keyed by delivery number. Each event sets only the fields it owns. Status changes follow the state machine with `eventTime` comparison: `PICKED_UP` (later in the lifecycle) is not overwritten by `DISPATCH_READY`.
2. **Park and resequence:** if processing `PICKED_UP` genuinely needs dispatch data (e.g. a handling unit list for the PGI), park it in `pending_events` keyed by delivery number. Process it when dispatch arrives, or alert after 30 minutes.

**Answer to give:** "I design for convergence first and resequence only when there's a true data dependency."

---

## Case 5 — An invoice is generated twice

**Situation:** The POD event was processed twice: a carrier webhook retry plus a DLQ replay with a new eventId. Billing ran twice and finance found duplicate invoices `9000123456` and `9000123457`.
**Root cause analysis:** the inbox deduped on `eventId` only. The replay had a new ID, and billing had **no business-level idempotency key**.
**Fix**
1. **Business key = delivery number** for billing: `billing_request(delivery_number UNIQUE)`.
2. **Lookup-before-create:** check SAP for an existing billing document for the delivery (the document flow, VBFA) before calling the billing BAPI.
3. **Replays keep the original eventId** (policy change in the replay API).
4. SAP configuration: copy control that prevents billing the same delivery twice. This is the backend's own guard (defence in depth).
5. **Remediation:** cancel the duplicate invoice in SAP (cancellation document), inform the customer, and run an invoice reconciliation over 90 days.

**Lesson:** technical dedupe (eventId) protects against redelivery. **Business idempotency** protects against *every* path to a duplicate.

---

## Case 6 — ERP and WMS report different inventory quantities

**Situation:** For `VLV-BL-050` at plant 1000, SAP shows 120 and the WMS shows 112.
**Investigation sequence**
1. **Timing:** any documents in flight? Check open deliveries without PGI, goods receipts in the WMS not yet posted, and messages in queues or the DLQ for this material.
2. **Granularity / stock type:** SAP unrestricted 112 + quality inspection 8 = 120? Compare like with like.
3. **UoM:** was a receipt of 1 BOX (10 EA) posted as 1 EA somewhere?
4. **Integration failures:** grep the logs and DLQ for this material in the period since the last matching reconciliation.
5. **Manual activity:** direct adjustments in the SAP (MI07) or WMS UI without integration.

**Resolution:** fix the cause (replay the missing GR, correct the UoM mapping), then post the adjustment in the system that's **wrong**. WMS is the SoR for physical stock, but if the WMS missed a receipt, the WMS is the one corrected. Document the case in the recon report.
**Prevention:** 4-hourly recon for A-class items, alert on |diff| > threshold, UoM master-data validation in the mapping (fail loudly), and absence monitoring for expected GR events.

---

## Summary table — say this in one breath

| Case | Core technique |
|------|----------------|
| SAP commit + caller timeout | Business key + lookup-then-create + sweeper |
| Reservation ok, ERP failed | Compensate on definitive failure. TTL as safety net. Don't compensate on unknown |
| DB ok, publish failed | Transactional outbox + relay + inbox |
| Out-of-order shipment events | Converging upserts + state machine. Resequence only on real dependency |
| Duplicate invoice | Business-level idempotency (delivery number) + lookup + SAP guard |
| ERP vs WMS mismatch | Classify (timing, granularity, UoM, failures, manual) before correcting. Scheduled recon |

Next section: [09 — Testing](../09-testing/01-munit-unit-testing.md)
