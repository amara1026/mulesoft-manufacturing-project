# 13.4 — Troubleshooting Scenarios 16–20

---

## Scenario 16 — A deployment causes production regressions

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | 30 minutes after deploying `order-mgmt-prc-api 1.5.0`, 422 errors rise from 0.5% to 18%. Orders with UoM `BOX` are rejected. **P1** |
| **Reproduce** | Submit an order with `unitOfMeasure: BOX` against 1.5.0 in QA. It fails |
| **Diagnose** | Correlate the error spike with the deploy time (deployment marker on the dashboard). Error code `AIM-ORD-4224 invalid UoM`. Diff 1.4.0 → 1.5.0: the UoM lookup moved from an inline map to `lookups/uom.json`, which **lacks BOX** |
| **Root cause** | An incomplete data migration in a refactor. No test case for BOX. The UAT dataset only used EA |
| **Immediate mitigation** | **Roll back to 1.4.0** (pre-tested rollback). Ask the affected customers to resubmit, or replay the rejected requests from the logs/idempotency store if the business agrees |
| **Permanent fix** | Add BOX to the lookup. Golden tests covering **every** UoM in the RAML enum. UAT datasets cover all enums |
| **Prevention & alerts** | Post-deploy watch: an error-rate comparison with the pre-deploy baseline auto-triggers rollback (or pages) when it rises more than 3× within 30 minutes. Canary-style rollout for high-risk changes, where supported |
| **Alternatives** | Feature flag the refactor and compare old and new outputs in shadow mode before switching |
| **Interview answer** | "Correlating with the deploy marker made the cause obvious, so roll back first and diagnose second. Then I'd ask why tests missed it. Here the test data didn't cover all valid enum values, so I'd add tests derived from the contract itself, every enum value, and an automated post-deploy comparison of error rates against the baseline." |

---

## Scenario 17 — An upstream system changes its payload schema

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | After a Salesforce release, orders arrive with `requestedDeliveryDate` as `"2026-11-20T00:00:00.000+0000"` instead of `"2026-11-20"`. APIkit rejects them with 400. The rep can't submit. **P1** |
| **Reproduce** | Post the new format to QA |
| **Diagnose** | APIkit error: `requestedDeliveryDate: invalid date-only`. Salesforce change: an admin changed the field type from Date to DateTime |
| **Root cause** | An uncoordinated change in a consumer system. The contract was correct to reject it |
| **Immediate mitigation** | Option A: the Salesforce admin reverts the field type (preferred: the contract holds). Option B, if the revert is impossible quickly: a temporary tolerant mapping at the Exp API that accepts both formats (normalise to a date) via a hot-fix, documented as technical debt |
| **Permanent fix** | Consumer contract tests in Salesforce's pipeline (sandbox → our QA mock). Change governance: field changes on integrated objects require integration sign-off |
| **Prevention & alerts** | Alert on 400-rate spikes per consumer (a schema drift indicator). The API catalogue documents which fields each consumer depends on |
| **Alternatives** | Tolerant reader in the Exp layer by design (accept the date in multiple formats). This trades strictness for robustness, so decide deliberately |
| **Interview answer** | "The API was right to reject the payload, so the question is where to absorb the change. I'd prefer the producer to honour the contract. If the business can't wait, I'd add a narrowly scoped tolerant mapping in the Experience layer, which is exactly where channel-specific adaptation belongs, so the Process layer stays clean. Then add consumer contract tests and change governance so the next schema change is caught before production." |

---

## Scenario 18 — Replaying a failed shipment event creates duplicate dispatch requests

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | An ops engineer replays 120 DLQ messages after a carrier outage. 37 shipments get **booked twice**, so two trucks arrive. **P2**, with real costs |
| **Reproduce** | The original message processed the booking but failed later (the PGI step), so it went to the DLQ. The replay re-runs the booking |
| **Diagnose** | Replayed messages had **new eventIds** (the replay tool generated new IDs), so the inbox didn't catch them. The shipment consumer had no business-key check on the delivery number. The carrier API had no idempotency key |
| **Root cause** | A non-idempotent consumer plus a replay tool that broke dedupe. The step granularity was too coarse: booking and PGI were in one unit of work |
| **Immediate mitigation** | Cancel the duplicate bookings with the carrier. Pause further replays |
| **Permanent fix** | (1) Business key = delivery number in `shipment_request` (UNIQUE) with step status (BOOKED, PGI_POSTED). (2) The replay tool preserves the original eventId. (3) Split booking and PGI into separate steps/messages so a PGI failure doesn't replay the booking. (4) Lookup the carrier booking by shipper reference before booking |
| **Prevention & alerts** | Replay requires a dry-run showing "already processed" counts. A daily duplicate-booking check |
| **Alternatives** | Saga with per-step state, so the replay resumes from the failed step |
| **Interview answer** | "Replay is only safe if consumers are idempotent at the business level and the replay preserves message identity. Here neither was true, and the message bundled two side effects. I'd make each side effect its own step with its own state and business key, so a replay resumes from the failed step and skips completed ones. The replay tool would keep the original IDs and run a dry-run first." |

---

## Scenario 19 — An application works in development but fails in production

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | `wms-sys-api` deploys fine to PROD, but every call fails with `HTTP:CONNECTIVITY: UnknownHostException wms.aim.local`. Works in DEV/QA. **P1** at go-live |
| **Reproduce** | Not reproducible in QA, which is itself a clue: an environment difference |
| **Diagnose** | Compare environments: QA Private Space has DNS forwarding to the on-prem DNS. **PROD Private Space doesn't**. Other usual suspects to check: firewall rules (PROD CIDR not allowed), truststore (PROD backend uses a different CA), properties (PROD file missing a key or wrong host), sizing (OOM only at PROD volume), policies (PROD API instance has different policies) |
| **Root cause** | Missing PROD network configuration (DNS forwarding) |
| **Immediate mitigation** | Use the IP temporarily? **No.** It's brittle and breaks TLS hostname verification. Fix DNS forwarding via an urgent change |
| **Permanent fix** | Infrastructure as code for Private Space settings (DNS, firewall, TLS) so all environments are identical by construction. A **pre-go-live connectivity checklist** executed in PROD before cut-over (DNS resolve, TCP connect, TLS handshake for every backend) |
| **Prevention & alerts** | An environment parity review in the release checklist. Synthetic connectivity checks |
| **Alternatives** | — |
| **Interview answer** | "'Works in dev, fails in prod' means an environment difference. I'd check the usual suspects systematically: DNS, firewall, certificates, properties, policies, sizing and data volume. Here it was DNS forwarding in the production Private Space. The lasting fix is environment parity through infrastructure as code and a production connectivity check before go-live, not just fixing this one setting." |

---

## Scenario 20 — A downstream outage causes cascading failures across the API chain

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | The WMS becomes slow (20 s responses). Within 10 minutes the order API, the warehouse Exp API, *and* the unrelated supplier confirmation flow all degrade. **P1** |
| **Reproduce** | Inject 20 s latency in the WMS stub under normal load |
| **Diagnose** | Thread and connection analysis: `inventory-availability-prc-api` threads are blocked waiting on the WMS (timeout 30 s, too long). The **shared HTTP requester config** (one pool for WMS + SAP) is exhausted, so SAP calls are blocked too. The supplier flow runs in the same app and shares the pool |
| **Root cause** | No bulkheads (shared pools), timeouts too long, no circuit breaker. The failure propagated through shared resources |
| **Immediate mitigation** | Lower the WMS timeout via a property (2 s) and restart. Open the "WMS degraded" feature flag: availability is served from a 5-min cache for display, and order intake uses `202 accepted, reservation pending` for long-lead-time orders |
| **Permanent fix** | **Bulkheads:** separate requester configs and pools per backend, `maxConcurrency` on flows. **Timeout budget** respected. A **circuit breaker** for the WMS. Separate apps for unrelated domains (supplier confirmations shouldn't share runtime resources with inventory) |
| **Prevention & alerts** | Per-dependency latency alerts. Pool saturation alerts. A chaos test in QA quarterly (inject latency into each dependency) |
| **Alternatives** | Service mesh / gateway-level timeouts and outlier detection between APIs |
| **Interview answer** | "Cascades happen when a slow dependency holds shared resources: threads, connections, pools. I'd contain the immediate problem with shorter timeouts and a degraded mode, then fix the design with bulkheads per dependency, strict timeout budgets, circuit breakers, and separating unrelated workloads. Slow is worse than down, because a down dependency fails fast and a slow one quietly consumes everything." |

Back to: [Troubleshooting method](00-troubleshooting-method.md) · Next section: [14 — Interview scenarios](../14-interview-scenarios/01-sap-timeout-after-commit.md)
