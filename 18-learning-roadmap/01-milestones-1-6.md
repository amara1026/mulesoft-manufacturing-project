# 18.1 — Learning Roadmap: Milestones 1–6

**How to use it:** at about 1–2 hours a day, each milestone takes 3–5 days, about 8–10 weeks in total. Finish every milestone with the **practical assessment** and score yourself honestly with the **readiness score** (0–10). Don't move on below 7.

**Essential vs advanced:** items marked ⭐ are essential for job readiness. ◆ items are advanced differentiators.

---

## Milestone 1 — Business requirements & manufacturing domain fundamentals

**Study:** [01.1](../01-business-domain/01-business-scenario.md), [01.2](../01-business-domain/02-end-to-end-process.md), [01.3](../01-business-domain/03-requirements.md)

**Learning goals**
- ⭐ Explain O2C, P2P and plan-to-produce in your own words, using AIM examples
- ⭐ Name the system of record for each entity
- ⭐ Decide sync vs async for each step and justify it
- ◆ Map NFRs to design decisions

**Hands-on exercises**
1. Without notes, draw the 14-step process flow and mark the sync/async steps.
2. Write five new FRs for **returns (RMA)** in the same format as 01.3.
3. For each FR you wrote, identify the SoR and one failure point.

**Expected results:** a diagram matching 01.2's flow. Returns FRs that include a credit memo (SAP), a WMS receipt and a Salesforce case.

**Common mistakes:** calling MuleSoft a system of record. Forgetting physical irreversibility (shipped goods). Treating every step as synchronous.

**Interview questions:** "Walk me through order-to-cash." "Which system owns inventory?" "Why isn't procurement synchronous?"

**Practical assessment:** explain the AIM business problem and the end-to-end flow in 2 minutes (record yourself).

**Readiness score:** 0–3 can't explain the flow · 4–6 flow OK, SoR or sync/async weak · 7–8 clear and justified · 9–10 also links NFRs to design

---

## Milestone 2 — System context, API-led architecture, UML diagrams

**Study:** [02-architecture](../02-architecture/01-system-context.md) (all), [03-uml-diagrams](../03-uml-diagrams/01-shortage-procurement-and-mes.md) (all)

**Learning goals**
- ⭐ Draw the context, API-led and primary sequence diagrams from memory
- ⭐ Explain each API's responsibility and non-responsibility
- ⭐ Explain the anti-patterns (duplicated logic, cycles, pass-through layers)
- ◆ Deployment architecture: Private Space, VPN, hybrid plant runtimes

**Hands-on exercises**
1. Draw diagrams 1, 3 and 6 on paper in under 10 minutes total.
2. Write a Mermaid sequence diagram for **order cancellation** (saga with compensations).
3. Write an ADR deciding whether `logistics-tracking-exp-api` can skip the Process layer.

**Expected results:** the cancellation sequence includes the SAP rejection, the reservation release and the conditional PO cancellation. The ADR states context, decision, consequences and alternatives.

**Common mistakes:** diagrams with everything in one picture. Arrows without direction or meaning (sync vs async). No error paths.

**Interview questions:** "Why API-led?" "What's in your System layer?" "How do you avoid circular dependencies?"

**Practical assessment:** a whiteboard session. Draw API-led for AIM and explain the SAP timeout path (Diagram 8) in 3 minutes.

**Readiness score:** 7+ = you can draw and defend the layers and two failure sequences

---

## Milestone 3 — RAML & API design

**Study:** [04-api-design](../04-api-design/01-api-catalogue.md) (all), the mini project's [RAML](../mule-project/aim-order-integration/src/main/resources/api/order-exp-api.raml)

**Learning goals**
- ⭐ Write RAML 1.0 with types, examples, traits, security schemes
- ⭐ Standard error contract + status semantics
- ⭐ Versioning and backward compatibility rules
- ◆ Governance rulesets, fragments in Exchange

**Hands-on exercises**
1. Write RAML for `supplier-exp-api` `POST /purchase-orders/{poNumber}/confirmations` with a `SupplierConfirmation` type, examples, an idempotency trait and 409/422 responses.
2. Import it into API Designer (free Anypoint trial), enable the Mocking Service and call it from Postman.
3. List three changes to your RAML that would be breaking and three that wouldn't.

**Expected results:** the RAML validates in Designer, the mock returns your examples, and the breaking-change list matches the table in 04.3.

**Common mistakes:** examples that don't match types (the AMF parser errors). `datetime` for business dates. No error responses declared.

**Interview questions:** "How do you version APIs?" "What's in your error contract?" "Design-first or code-first, and why?"

**Practical assessment:** design an API for "WMS goods receipt webhook" in 20 minutes, including security and idempotency.

**Readiness score:** 7+ = the RAML validates and you can defend status codes and versioning

---

## Milestone 4 — DataWeave 2.0

**Study:** [05-dataweave](../05-dataweave/01-dataweave-essentials.md) (all six files)

**Learning goals**
- ⭐ map/filter/reduce/groupBy/pluck/mapObject, selectors (incl. `*` for XML)
- ⭐ JSON↔XML, CSV input, SAP BAPI shapes, null handling, dates and timezones
- ⭐ Reusable modules and functions
- ◆ Streaming, performance, indexed lookups

**Hands-on exercises** (use the DataWeave Playground or Studio's preview)
1. Reproduce every example in 05.2–05.5 and confirm the outputs.
2. Write `bapiReturnToAimError(payload, correlationId)` → AIM error contract.
3. Given 10,000 order lines and 50,000 materials, write an **indexed** enrichment and explain its complexity.
4. Convert the supplier CSV into one canonical message per PO with UoM conversion.

**Expected results:** outputs identical to the documented ones. Your enrichment uses `groupBy` (or a `var` index) once.

**Common mistakes:** forgetting `*` on repeated XML. Floats for money. `as Number` on null. Multiple payload passes.

**Interview questions:** "default vs skipNullOn?" "How do you handle large payloads?" "map vs pluck?"

**Practical assessment:** a 30-minute timed challenge mapping an ASN XML (nested HUs/items) to canonical JSON with totals by material.

**Readiness score:** 7+ = you can solve the timed challenge without looking up the syntax for core functions

---

## Milestone 5 — Experience, Process and System API implementation

**Study:** [06.1–06.4](../06-mule-implementation/01-dev-setup-and-repo.md), the mini project ([README](../mule-project/aim-order-integration/README.md))

**Learning goals**
- ⭐ HTTP listener/request with timeouts, APIkit, Choice, For Each, Scatter-Gather, flow-ref
- ⭐ Error handling (propagate vs continue, types, mapping, global handler)
- ⭐ Database connector with transactions, Object Store
- ◆ Bulkheads via request configs and maxConcurrency

**Hands-on exercises**
1. Import and run the mini project. Execute every Postman request and observe the logs.
2. Add a new endpoint `POST /api/v1/orders/{orderId}/cancellation` that sets status CANCELLED and releases the reservation via the WMS mock.
3. Break something on purpose (remove a timeout, use on-error-continue wrongly) and observe the behaviour.

**Expected results:** the cancellation endpoint returns 200, a `order.cancelled` outbox event is published, and the reservation is released (visible in the mock logs).

**Common mistakes:** sub-flows where a private flow with its own error handler is needed. Missing `otherwise`. HTTP calls inside DB transactions.

**Interview questions:** "on-error-propagate vs continue?" "How does scatter-gather handle failures?" "Sub-flow vs flow?"

**Practical assessment:** explain each flow in `prc-order-management.xml` line by line to a friend (or record it).

**Readiness score:** 7+ = you can modify the project confidently and explain every error handler

---

## Milestone 6 — SAP, Salesforce, WMS, MES, DB, HTTP, SFTP and messaging connectors

**Study:** [06.5–06.7](../06-mule-implementation/05-sap-salesforce-connectors.md)

**Learning goals**
- ⭐ SAP: BAPI vs IDoc vs OData, commit/LUW, ALPHA, RETURN table, JCo prerequisites
- ⭐ Salesforce: JWT auth, upsert by external ID, limits, CDC/Platform Events
- ⭐ Anypoint MQ: exchanges/queues, ack modes, DLQ, FIFO groups
- ⭐ SFTP + Batch: safe reads, duplicate files, aggregator
- ◆ Hybrid MES integration, VM vs MQ vs Kafka

**Hands-on exercises**
1. Free Salesforce Developer Edition: create a connected app (JWT) and upsert an `Order` by an external ID from Studio.
2. Anypoint MQ (trial): create an exchange + 2 queues + a DLQ (max deliveries 3). Publish, consume with MANUAL ack, and force a failure to see the message reach the DLQ.
3. Local SFTP (e.g. a Docker SFTP image): build a listener + Batch Job over a 100k-row CSV and measure the time and memory.

**Expected results:** the Salesforce record is upserted without duplicates when run twice. The message reaches the DLQ after 3 deliveries. The batch completes with stable heap.

**Common mistakes:** IMMEDIATE ack. Reading a still-growing file. Not knowing that the BAPI commit must run on the same session.

**Interview questions:** "How do you receive IDocs?" "What happens to an MQ message if your flow crashes?" "Batch vs For Each?"

**Practical assessment:** explain the SAP sales order creation path including commit, errors and timeout lookup, in 3 minutes.

**Readiness score:** 7+ = you can explain each connector's failure semantics, not just its configuration

Next: [Milestones 7–12](02-milestones-7-12.md)
