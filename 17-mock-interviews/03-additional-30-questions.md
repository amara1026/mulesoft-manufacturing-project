# 17.3 — Thirty Additional Interview Questions (Grouped, with Model Answers)

Answers are kept concise. Expand them with examples from the project or your own work.

## A. MuleSoft fundamentals

**A1. What is a Mule event, and what does it contain?**
> A Mule event has a **message** (payload + attributes) and **variables**, plus metadata such as the correlation ID and, on failure, an `error`. Attributes are source-specific (HTTP headers, query params, file name). Variables travel with the event through flow-refs. An async scope works on a copy.

**A2. Flow vs sub-flow vs private flow?**
> A flow has a source, or no source when it's a private flow. It can have its own error handler and processing strategy. A sub-flow has no source and no error handler. It runs synchronously in the caller's context, like inlined code. Use a private flow when a step needs its own error handling, and a sub-flow for simple reuse.

**A3. How does Mule 4 handle threading?**
> The Mule 4 runtime is reactive and non-blocking. Since 4.3 it uses a unified, self-tuning thread pool by default instead of separate CPU-light, CPU-intensive and blocking I/O pools. Connectors declare their processing type, and non-blocking HTTP means threads aren't held while waiting for responses. Tuning is rarely needed. Bound concurrency with `maxConcurrency` and connection pools rather than tuning thread pools blindly.

## B. DataWeave

**B1. `map` vs `mapObject` vs `pluck`?**
> `map` iterates an array and returns an array. `mapObject` iterates an object's key-value pairs and returns an object. `pluck` iterates an object and returns an array (often used after `groupBy` to turn the grouped object back into a list).

**B2. Why does `payload.order.item` return only one item for repeated XML elements, and how do you fix it?**
> The single-value selector returns the first match. Use the multi-value selector `payload.order.*item` to get all occurrences as an array. Mixing them up causes bugs that appear only when a document has a single element versus several.

**B3. How do you write reusable DataWeave?**
> Put functions in modules under `src/main/resources/dwl/...` and import them with `import * from dwl::module::path`, or publish a shared DataWeave library or Mule plugin. Keep business-agnostic helpers (dates, padding, UoM) separate from domain mappings, and unit-test them with golden files.

## C. Integration patterns

**C1. What's the transactional outbox and when do you need it?**
> When a flow must update its database *and* publish an event, doing both directly risks one succeeding without the other. The outbox writes the event into the same local DB transaction as the state, and a relay publishes it afterwards, at-least-once. Consumers must dedupe.

**C2. Orchestration vs choreography for a saga?**
> Orchestration has a central coordinator that knows the steps and compensations. It gives visibility and fits clear business processes like order creation. Choreography has services reacting to each other's events. Coupling is looser but the flow is harder to trace. I use orchestration for the order saga and choreography for notifications and analytics.

**C3. When would you *not* use scatter-gather?**
> When the calls depend on each other, when there are many dynamic targets (use parallel-foreach with bounded concurrency), when one route has a very long tail that would dominate latency, or when partial results are acceptable but you haven't designed per-route fallbacks.

## D. API security

**D1. What do you validate in a JWT?**
> Signature against the issuer's JWKS with an allow-listed algorithm, issuer, audience, expiry/not-before with small clock skew, and the required scopes or claims. On Anypoint this is done by the JWT Validation policy. The app uses claims for fine-grained authorisation.

**D2. What's BOLA, and how does it apply to supplier APIs?**
> Broken Object Level Authorization: an authenticated client accesses objects it doesn't own, for example supplier A confirming supplier B's PO by changing the PO number. Gateway policies can't detect it. The application must check ownership of every object referenced in a request.

**D3. How do you manage secrets in Mule apps?**
> Encrypted secure properties (`${secure::key}`) with the key supplied as a protected deployment property, or better, a vault integration so rotation and auditing are central. Never commit plain secrets. Scan repositories in CI, and rotate with overlap where partners support dual credentials.

## E. SAP and supply chain integration

**E1. BAPI, IDoc or OData: how do you choose?**
> BAPI/RFC for synchronous, rich operations like order creation, pricing simulation and ATP on S/4 on-prem or ECC. IDocs for asynchronous, high-volume document exchange (orders, deliveries, invoices, master data) with tRFC guarantees. OData for reads and simpler operations, and as the main option for S/4HANA Cloud. I keep them behind one SAP System API so consumers don't care.

**E2. What's ATP, and why does it matter for integration?**
> Available-to-Promise is SAP's check of how much stock can be promised by when, considering stock, receipts and existing commitments. Integrations must decide whether the promise comes from SAP ATP, WMS physical availability, or both. Mixing them without rules causes overselling or false backorders.

**E3. What is ALPHA conversion?**
> SAP's conversion between external and internal formats for numeric-like keys. A customer `100234` is stored as `0000100234`. Integrations must pad on the way in and usually strip on the way out. It's a frequent cause of "not found" errors.

## F. Production troubleshooting

**F1. An API is slow but CPU is low. Where do you look?**
> At waiting rather than computing: outbound latency per dependency, connection pool waits (HTTP `maxConnections`, DB pool), `maxConcurrency` queues, GC pauses, and locks in the database. Per-hop timings by correlation ID usually reveal the culprit.

**F2. Messages are going to the DLQ. What's your process?**
> Look at the error metadata to classify: transient (the dependency was down) or non-retryable (bad data or a bug). Check whether it's isolated or widespread and what changed. Fix the root cause first, then dry-run a replay to see what's still relevant, replay at a throttled rate with the original event IDs, verify the DLQ is empty, and reconcile.

**F3. How do you investigate a single customer's missing order?**
> Search the logs by externalOrderId to get the correlation ID. Check the idempotency and order_state records, the outbox status, queue/DLQ entries, and SAP by reference. The timeline shows where it stopped (rejected, pending ERP, event stuck, consumer failure), and that tells you the fix: replay, retry or a business action.

## G. Architecture

**G1. How do you avoid a "distributed monolith" with API-led?**
> Avoid deep synchronous chains and Process-to-Process sync cycles. Use events for long-running hand-offs. Keep APIs cohesive with clear ownership. Version contracts. Make sure each app can be deployed independently. If every change requires deploying five apps together, the boundaries are wrong.

**G2. When would you use Kafka instead of Anypoint MQ?**
> For very high throughput, replayable event logs with retention, stream processing, many consumer groups reading history, or an existing enterprise Kafka platform. Anypoint MQ suits business events and command queues with simpler operations, DLQs and FIFO.

**G3. What belongs in a canonical model, and what doesn't?**
> Only the fields that processes need, with business-neutral names and types, scoped per domain (order, procurement, logistics). System-specific technical fields stay in System API mappings. An enterprise-wide "everything" model becomes a bottleneck.

## H. Testing

**H1. What makes a good MUnit test?**
> It mocks external connectors by unique `doc:name`, sets a realistic input event, and asserts business outcomes (status, codes, number of calls, outgoing payloads via spies). It covers the negative paths: timeouts, business errors, duplicates. Tests are independent, using unique data and no shared state.

**H2. How do you test asynchronous flows end to end?**
> In SIT, publish or trigger the event, then poll the observable outcome (status API, DB state, target system) until an expected state or timeout. Assert on correlation-ID-based logs and check queue and DLQ state. Unit-test consumers in MUnit by calling the flow with a crafted message.

**H3. What's contract testing in a MuleSoft context?**
> Verifying that implementations and consumers agree on the API contract: APIkit validation, response schema tests (Newman) against RAML types, consumer-provided examples replayed in CI, and breaking-change detection between spec versions. For events, JSON Schemas per type and version.

## I. CI/CD

**I1. What does "build once, deploy many" mean, and why does it matter?**
> The same immutable artifact is promoted from DEV to PROD, and only configuration changes. It guarantees that what was tested is what runs in production, and it simplifies rollback and audit.

**I2. How do you handle environment-specific configuration?**
> Per-environment property files in the artifact for non-secrets, selected by an `env` property. Secrets come through secure properties or a vault, injected at deploy. Environment-specific IDs (API instance ID) are deployment properties. Never rebuild per environment.

**I3. How do you make rollback safe?**
> Keep the previous artifact available and deployable by a pre-approved pipeline job. Make DB changes expand/contract only, keep API and event changes backward compatible, and test the rollback in QA. Remember that rollback doesn't fix bad data, which needs a remediation plan.

## J. Senior developer responsibilities

**J1. How do you estimate an integration story?**
> Break it into design, mapping, flows, error handling, tests, connectivity, SIT and ops tasks. Estimate dependencies separately (firewall, SAP authorisations, partner sandboxes), because they dominate the calendar. State assumptions, use ranges for unknowns, and add contingency. Re-estimate after spikes.

**J2. How do you handle a disagreement on design with an architect?**
> Bring data and principles (latency, cost, reuse, risk), propose a decision rule, and write an ADR with the alternatives. Accept the decision-maker's call and record the trade-off. The aim is a good decision, not winning.

**J3. What do you do in the first 30 days on a new MuleSoft team?**
> Learn the business flows and systems of record. Read the ADRs, API catalogue and runbooks. Shadow on-call. Review recent incidents. Fix one small production issue end to end. Then identify the top reliability or productivity gaps (templates, tests, alerts) and propose improvements with the lead.
