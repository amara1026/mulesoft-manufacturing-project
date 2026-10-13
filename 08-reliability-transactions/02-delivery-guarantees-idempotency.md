# 08.2 — Delivery Guarantees, ACID vs Eventual Consistency, and Idempotency

`Essential`

## 1. The three delivery semantics

| Semantics | Meaning | How it happens | Acceptable for |
|-----------|---------|----------------|----------------|
| **At-most-once** | 0 or 1 deliveries. May lose | Ack before processing (`IMMEDIATE`), fire-and-forget `async` | Metrics, debug telemetry |
| **At-least-once** | ≥ 1 delivery. May duplicate | Ack after processing. Retries | **Default for business events** (+ idempotency) |
| **Exactly-once** | Exactly 1 *delivery* | Requires all participants to share one transactional protocol | Rarely achievable across heterogeneous systems |

**What AIM actually guarantees:** **at-least-once delivery + idempotent processing = exactly-once effect** on business state, *within the documented failure model*. Be precise in interviews: "exactly-once processing" claims across SAP + HTTP + Anypoint MQ are not true.

### Guarantees by technology (as used on AIM)

| Technology | Guarantee | Notes |
|------------|-----------|-------|
| HTTP request/response | None by itself | The client must retry. The server must be idempotent |
| Anypoint MQ | At-least-once | Persistent. Redelivery after ack timeout or nack. FIFO for ordering per group |
| VM queues (persistent) | At-least-once within the app/cluster | Not cross-app |
| PostgreSQL local transactions | ACID | Within the one database |
| SAP BAPI + commit | ACID within the SAP LUW | Not shared with Mule |
| SAP IDoc (tRFC) | Exactly-once *per TID*, if the TID is tracked correctly | The TID store must be durable |
| Salesforce upsert by external ID | Idempotent write | Natural dedupe |
| Kafka (alternative) | At-least-once by default. Exactly-once **within Kafka** (transactions + idempotent producer) | Not end to end once you call SAP |

## 2. ACID vs BASE (eventual consistency)

| | ACID (local transaction) | Eventual consistency (saga + events) |
|-|--------------------------|--------------------------------------|
| Scope | One database / resource manager | Many systems |
| Isolation | Strong | None between steps. Intermediate states visible |
| Failure handling | Rollback | Compensation, retry, reconciliation |
| AIM uses it for | state + outbox, inbox + business state | Order → SAP → WMS → Salesforce |

**Visible intermediate states are a business decision.** For example, Salesforce shows "Pending ERP" for a few minutes. Agree these states with the business and show them in the UI. Don't hide them.

## 3. XA transactions: when they're appropriate

XA (two-phase commit) coordinates several XA-capable resources, for example **JMS (ActiveMQ/IBM MQ) + a relational DB** on an on-prem Mule runtime.
- ✔ It can be appropriate for **on-prem hybrid** setups with an XA broker and DB where you need atomic consume-and-write. Example: a plant runtime consuming from IBM MQ and writing to a local DB.
- ✘ It's not applicable to HTTP, SAP RFC, Salesforce or Anypoint MQ.
- ✘ The costs are latency, lock duration, in-doubt transaction recovery, and the need for a transaction manager with a durable log.
- **AIM decision:** no XA in the cloud; outbox/inbox instead.

## 4. Idempotency design checklist

| # | Question | AIM answer |
|---|----------|------------|
| 1 | What is the **key**? | Client key for API requests. `eventId` for technical dedupe. **Business key** for intent |
| 2 | **Where** is it enforced? | DB unique constraint in the owning Process API |
| 3 | What happens on **duplicate while in progress**? | 409 (API) / nack with delay (consumer) |
| 4 | What happens on **duplicate after completion**? | Replay the stored response / ack + skip |
| 5 | **Same key, different payload**? | 422 (hash mismatch) |
| 6 | How do we recover from a crash **between the side effect and recording completion**? | Lookup-by-reference in the target system before redoing |
| 7 | **Retention**? | Longer than the maximum retry/replay window (7–30 days) |
| 8 | Do downstream calls **propagate** idempotency? | Forward `Idempotency-Key` to partners that support it. Use external references in SAP |
| 9 | Are **compensations** idempotent? | Yes. Release reservation by ID twice = no-op |
| 10 | Is idempotency **tested**? | MUnit duplicate tests + chaos tests (kill a replica mid-flow) |

## 5. Natural vs artificial idempotency

- **Natural:** "set status to SHIPPED", "upsert by external ID" and "inventory is 40" are idempotent by design. **Prefer them.**
- **Artificial:** "create PO", "post goods issue" and "add +5 to stock" need keys, dedupe and lookups.
- **Design tip:** convert operations to natural idempotency where possible. Send *absolute* inventory snapshots instead of deltas, and use upserts instead of inserts.

## Interview angle
**Q: "What's the difference between idempotency and deduplication?"**
> "Deduplication drops messages it has seen before, by ID. Idempotency is the broader property that repeating an operation has the same effect as doing it once. Dedupe is one way to achieve it. The others are natural idempotency, like upserts and absolute values, and lookup-before-create. Dedupe alone fails when two *different* messages express the same intent, which is why I use business keys as well."

Next: [08.3 Outbox, inbox and saga implementation](03-outbox-inbox-saga.md)
