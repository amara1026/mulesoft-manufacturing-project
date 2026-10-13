# 17.2 — Fifteen Core Interview Questions with Model Answers

*Model answers are technically accurate and framed around the simulated project. Replace or extend them with your real experience where you have it.*

---

**1. Explain your manufacturing integration architecture.**
> "It's API-led, in three layers. Experience APIs serve Salesforce, suppliers, the warehouse and carriers. Process APIs orchestrate order management, inventory, procurement, production and shipment. System APIs wrap SAP, Salesforce, the WMS, the MES, the supplier hub and carriers. Synchronous HTTP is used where a user waits (order submission through SAP order creation), and everything downstream is event-driven over Anypoint MQ. Integration state, meaning idempotency, order state, outbox and inbox, lives in PostgreSQL. It runs on CloudHub 2.0 in a Private Space with VPN to SAP, plus hybrid runtimes in the plants for MES." *(Then draw [02.3](../02-architecture/03-api-led-architecture.md).)*

**2. Why did you use API-led connectivity?**
> "For reuse and change isolation. The SAP System API is used by five processes, so an SAP upgrade or a move from BAPI to OData touches one app. Channels change independently through Experience APIs, and business rules live in one place. It also gives clean security zones: only System APIs reach the data centre. The cost is more apps and extra hops, so I skip the Process layer when there's no orchestration, and record that in an ADR."

**3. Why did you choose SAP System APIs?**
> "SAP integration has a lot of specialised logic that shouldn't spread: JCo connection pooling, BAPI commit on the same session, ALPHA conversion, internal versus external units of measure, and translating the BAPI RETURN table into proper errors. The System API encapsulates all of that and exposes clean resources like `/sales-orders` with standard errors. It also centralises SAP connection limits, so we never exceed what SAP Basis allows."

**4. How do you handle inventory discrepancies?**
> "First, prevention: event-driven goods movements with idempotent posting, plus a nightly snapshot reconciliation. When discrepancies appear, I classify them before fixing: timing (documents in flight at the cut-off), granularity (bin versus storage location), stock types (quality inspection, blocked), unit-of-measure errors, and real integration failures. Real failures are replayed from the source. Allow-listed small differences can be auto-adjusted. Everything else becomes a task for inventory control, and high-value items are never auto-corrected."

**5. How do you prevent duplicate purchase orders?**
> "With layers. An inbox table dedupes redelivered events by event ID. A business key, order plus material plus plant, is claimed with a unique constraint before any side effect, so concurrent duplicates see 'in progress' and back off. The key is stored in an SAP reference field, so after a timeout or crash we look up before creating. The same key goes to the supplier as an idempotency key. A daily reconciliation checks for duplicate references as the safety net."

**6. How do you handle a timeout after SAP commits a transaction?**
> "A timeout means the outcome is unknown, so we never blind-retry the create. The SAP System API catches the timeout and looks the document up by our business reference. If it's found, it returns success. If not, or if SAP is down, the order becomes PENDING_ERP with a 202, and a retry consumer does lookup-then-create. The client's idempotency key ensures that resubmissions replay the stored response. Reconciliation catches SAP documents without Mule state." *(Deep dive: [14.1](../14-interview-scenarios/01-sap-timeout-after-commit.md).)*

**7. How do you process millions of inventory records?**
> "With a Batch Job over a streamed SFTP read, so records are persisted to batch queues and memory stays bounded. Step one validates and maps. Step two uses a batch aggregator to send 1,000-record chunks to SAP, and only the deltas. A failures-only step records failed rows with reasons. maxFailedRecords stops the job if the file looks corrupt. On Complete publishes the summary, writes an error report and archives the file. Block size and concurrency are tuned by load testing with production-sized files, and the file is registered by name and checksum so it's never processed twice."

**8. How do you recover from a warehouse outage?**
> "It depends on the direction. For outbound calls to the WMS (availability, reservations), the circuit breaker opens. Order intake either fails fast with 503 or, for long-lead-time orders, accepts the order with a pending reservation, which the business has agreed. Display availability can come from a short-lived cache. For inbound WMS events, the WMS usually buffers them or we poll for missed events after recovery. After recovery we drain the queues at a controlled rate and run an inventory reconciliation to confirm nothing was missed."

**9. How do you handle out-of-order events?**
> "I aim for convergence: upserts keyed by business ID, a state machine that won't move backwards, and version or timestamp checks so older events can't overwrite newer state. Where every step matters, like supplier confirmations or MES operation confirmations, I use sequence numbers with parking and a timeout, plus FIFO queues with message groups per PO or production order to keep order in transit."

**10. How do you secure supplier integrations?**
> "Several layers. The network has a separate ingress with mTLS, where the supplier certificate is their identity. The gateway applies client ID enforcement with SLA-tier rate limits and JSON threat protection. In the application, the schema is validated and, critically, we check object ownership: supplier A can't confirm supplier B's PO, which a gateway can't check. Outbound, we use OAuth or mTLS to SupplierHub with secrets in a vault. Certificates are inventoried with expiry alerts, PII is masked in logs, and every supplier message is audited."

**11. How do you troubleshoot production incidents?**
> "With a fixed method: stabilise the business impact first, scope it (what, who, since when, what changed), gather signals per hop (rate, errors, latency, saturation, queue age), form ranked hypotheses, and test them one at a time using correlation IDs. Then I mitigate, apply the permanent fix, and remediate data. A blameless postmortem follows, and the actions usually include the alert or test that would have caught it earlier." *(Method: [13.0](../13-production-troubleshooting/00-troubleshooting-method.md).)*

**12. How do you handle API versioning?**
> "The major version goes in the URI, and minor versions are Exchange asset versions for additive changes. Before any breaking change I check whether it can be additive. If it truly breaks, v2 runs alongside v1, ideally with v1 as a thin mapping onto v2's logic. API Manager contracts show who still calls v1. We send Deprecation and Sunset headers, agree migration dates with each consumer, and retire v1 only when traffic reaches zero."

**13. How do you review code and mentor developers?**
> "I review design intent first, then details, using a checklist: timeouts set, idempotent creates, no HTTP inside transactions, the right error handler semantics, DataWeave null-safety and performance, no secrets or PII in logs, and negative-path tests. Feedback is phrased as questions and labelled blocker, suggestion or nit. For mentoring I pair on first-time topics like SAP integration, ask juniors to write a failure table before coding, and turn repeated review comments into templates or lint rules."

**14. What alternatives did you consider?**
> "Kafka versus Anypoint MQ: MQ for business events because it's simpler to operate and has DLQs and FIFO built in, with Kafka kept in mind for MES telemetry. Object Store versus a database for idempotency: the database, for atomicity and auditability. Fully async order intake versus sync with fallback: sync, because reps need the SAP number. BAPI versus OData for SAP: BAPI for create and simulate, OData for lookups. And Runtime Fabric versus CloudHub 2.0: CloudHub, because there was no data-residency or on-prem constraint, plus hybrid for the plants."

**15. What would you redesign and why?**
> "Three things. First, a CDC-based outbox relay instead of polling, to cut event latency and database polling load. Second, a proper circuit breaker component rather than an Object Store-based one, possibly at gateway or mesh level. Third, Kafka for MES telemetry if plants start streaming machine data, which would keep Anypoint MQ focused on business events. I'd also invest earlier in consumer contract tests for event schemas, because schema drift from partners is a common silent failure."

Next: [17.3 Thirty additional questions](03-additional-30-questions.md)
