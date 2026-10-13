# 17.1 — The Five-Minute Project Explanation

`Essential` — practise until you can deliver it in 4:30–5:00 without notes, then draw the API-led diagram while you talk.

> **Framing rule:** say it's a reference project you designed and built to practise enterprise patterns, or map its patterns to your real projects. **Don't present simulated numbers as production results.** Use phrases like "designed for", "assumed", and "tested in my setup".

---

## Script (with timing)

**0:00 — Business problem (40 s)**
> "The project is an integration platform for a manufacturer of industrial pumps and valves. I modelled it on a typical setup: Salesforce for sales, SAP S/4HANA as the ERP, a warehouse management system, a shop-floor MES, suppliers and carriers. The business problem was manual re-keying of orders into SAP, overnight inventory syncs that caused overselling, and shortages handled by email, which produced late or even duplicate purchase orders. The goal was order-to-cash and procure-to-pay flows that are automated, reliable and auditable."

**0:40 — Architecture (60 s)**
> "I used API-led connectivity. Experience APIs serve each channel: a Customer Order API for Salesforce and the portal, a Supplier API for partner callbacks with mTLS, and warehouse and logistics APIs for webhooks. Process APIs hold the business orchestration: order management, inventory, procurement, production and shipment. System APIs wrap each backend. The SAP System API hides BAPIs, commit handling and SAP error translation, so five processes reuse it. Anypoint MQ is the event backbone, and a PostgreSQL integration database holds integration state: idempotency keys, order state, an outbox and an inbox. Everything runs on CloudHub 2.0 in a Private Space with VPN to the data centre, plus a hybrid runtime at the plants for MES so production keeps working during WAN outages."

**1:40 — Main flow and patterns (70 s)**
> "Order submission is synchronous, because the sales rep needs the SAP order number. The Process API first claims an idempotency key in the database. Then it validates the customer and availability in parallel with a scatter-gather, soft-reserves stock in the WMS with a TTL, and creates the SAP order with our reference in it. Finally it commits the order state and the outbound events in one local transaction, the transactional outbox, before responding. Everything after that is event-driven: Salesforce status sync, procurement for shortages, production for make-to-order items, carrier booking and invoicing. Consumers are idempotent receivers with an inbox and business keys, because MQ is at-least-once. Supplier confirmations and production events need ordering, so they use FIFO queues grouped by PO or production order, with version checks."

**2:50 — Reliability: the hard part (60 s)**
> "The design question I spent most time on was the SAP timeout: SAP commits the order but our call times out. A blind retry would duplicate the order, so on a timeout we look the order up in SAP by our reference. If it's found, we continue. If not, we mark the order PENDING_ERP, return 202, and a retry consumer later does lookup-then-create. The saga compensates only on definitive failures, for example releasing the reservation on a credit block. Reconciliation jobs compare our state with SAP and the WMS, and failed messages go to DLQs with a controlled, audited replay API."

**3:50 — DataWeave, security, testing, deployment (50 s)**
> "DataWeave handles the SAP BAPI mappings, including ALPHA conversion, units of measure and the BAPI RETURN table, supplier CSVs and a small canonical model. Shared functions live in modules. On security, Salesforce uses OAuth with JWT validation policies, suppliers use mTLS with object-level authorisation checks, PII is masked in logs, and secrets are encrypted or held in a vault. MUnit covers happy and negative paths, including duplicates and SAP timeouts, with an 80% coverage gate. A Jenkins or Azure DevOps pipeline builds once and promotes the same artifact through the environments with smoke tests and a tested rollback."

**4:40 — Decisions and trade-offs (20 s)**
> "Key trade-offs: synchronous intake with an async fallback instead of fully async, Anypoint MQ over Kafka for business events, and a database rather than Object Store for idempotency. If I redesigned it, I'd consider Kafka for high-volume MES telemetry and a CDC-based outbox relay for lower latency."

---

## Delivery tips
- **Lead with the business**, then the architecture, then the hard problem. Interviewers remember the hard problem.
- **Have the diagram ready:** draw the three layers in 20 seconds while talking.
- **Pause after the SAP timeout section.** It invites the deep-dive questions you're best prepared for.
- **Adapt the depth:** for a hiring manager, spend more time on the business and decisions. For a technical panel, spend more on patterns and failure handling.
- **Bridge to your real experience:** "In my actual projects I've used X. This project let me go deeper on Y."

## Self-assessment checklist
- [ ] Under 5 minutes
- [ ] Mentioned all three layers with a concrete example each
- [ ] Explained sync vs async with a reason
- [ ] Explained the SAP timeout handling precisely
- [ ] Mentioned idempotency, outbox, DLQ/replay, reconciliation
- [ ] One security point and one testing/CI point
- [ ] At least one trade-off and one thing I'd redesign
- [ ] No unverifiable claims ("reduced costs by 40%")

Next: [17.2 Core interview questions](02-core-questions.md)
