# 13.2 — Troubleshooting Scenarios 6–10

---

## Scenario 6 — A DataWeave transformation causes excessive memory usage

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | `supplier-price-sync` replicas restart nightly at 01:20 with `OutOfMemoryError: Java heap space`. Price list updates are missing. **P3**, rising to P2 if prices go stale |
| **Reproduce** | Run the transform locally with the production file (180 MB, 1.2M rows) and `-Xmx1g`. It fails at the `groupBy` |
| **Diagnose** | Monitoring: heap climbs to 100% during the transform, with GC time > 50%. Heap dump: millions of DW value objects. The script uses `payload groupBy $.supplier` and `sizeOf(payload)` for logging, plus a nested `filter` lookup |
| **Root cause** | Operations that force the full input into memory (groupBy, sizeOf) on a large stream, plus O(n·m) lookups |
| **Immediate mitigation** | Temporarily give the replica more heap (a larger vCore) to get tonight's run through. Pause the sync if prices can wait a day |
| **Permanent fix** | Move to a **Batch Job** with a streaming CSV read. Remove `sizeOf`. Build the lookup index once (on a small reference set). Group per supplier downstream (the SAP Sys bulk call takes per-supplier chunks via the aggregator) |
| **Prevention & alerts** | Perf test with 2× production file size in the pipeline. Alert heap > 85% for 5 min. Code review checklist: "no groupBy/orderBy/sizeOf on unbounded inputs" |
| **Alternatives** | Ask the supplier for delta files. Pre-split the file in SFTP by supplier |
| **Interview answer** | "Production data was 1,000 times bigger than test data, and the script used operations that load everything. I'd confirm with heap metrics and a dump, then redesign rather than add memory: streaming plus Batch for bounded memory, indexed lookups, and no full-payload operations. Adding memory is only a short-term mitigation." |

---

## Scenario 7 — A Batch Job processes millions of inventory records with partial failures

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | The nightly inventory batch reports 2,013,442 total, 1,986,120 OK and **27,322 failed**. SAP inventory isn't updated for those materials, so ATP is wrong in the morning. **P2** |
| **Reproduce** | Feed a file containing materials unknown to SAP and with negative quantities (simulates a WMS data issue) |
| **Diagnose** | On Complete stats per step. The failure table grouped by reason: 26,900 × `M7 021 material not maintained in plant 3000` (SAP), 422 × validation (negative qty). All the SAP failures are for plant 3000 materials, which are new since the Stuttgart line extension |
| **Root cause** | Materials not extended to plant 3000 in SAP (master data process gap), plus WMS data quality |
| **Immediate mitigation** | Share the failure report with master data. Once the materials are extended, **re-run only the failed records** (from the failure table) via the replay flow. Delta posting is idempotent per material/plant/snapshot date |
| **Permanent fix** | Pre-validate the material/plant combination against a cached SAP material–plant list in step 1 (fail fast with a clear reason). Add a master-data readiness check in the new-plant onboarding checklist |
| **Prevention & alerts** | Alert if failed records > 0.5%. Trend dashboard of failure reasons. The `maxFailedRecords` threshold stops the job if > 5% (likely a corrupt file) |
| **Alternatives** | Event-driven inventory updates (smaller blast radius per failure) |
| **Interview answer** | "Partial failure is expected in big batches. The design question is whether the failures are visible, explainable and replayable. Failed records went to a separate step with the SAP reason, so grouping by reason pointed straight at a master-data gap for one plant. After the fix we replayed only the failed records, which is safe because the posting is keyed by material, plant and snapshot date. Then we added pre-validation so the batch reports the cause directly." |

---

## Scenario 8 — Supplier APIs introduce rate limiting

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | SupplierHub starts returning **429** with `Retry-After: 30` after a platform change. PO transmissions fail and land in the DLQ. Suppliers don't receive POs. **P2** |
| **Reproduce** | Supplier stub returns 429 above 5 req/s |
| **Diagnose** | Error type `HTTP:TOO_MANY_REQUESTS`. The rate of outbound calls (concurrency 8 × 2 replicas) exceeds the new limit. Check the partner's announcements: a new limit of 5 req/s per client |
| **Root cause** | Partner-side policy change. Our consumer treated 429 as a generic failure (immediate redelivery → amplification → DLQ) |
| **Immediate mitigation** | Reduce consumer concurrency (property change → restart) to ~2 per replica. Replay the DLQ at a throttled rate |
| **Permanent fix** | Handle 429 explicitly: read `Retry-After` and re-publish with that delay (no retry count penalty). Client-side throttling sized to the partner limit across replicas. Ask the partner for a bulk PO endpoint |
| **Prevention & alerts** | Alert on the 429 rate. Partner change-notification process (subscribe to their developer updates). Contract tests against the partner sandbox |
| **Alternatives** | Queue per supplier with a single consumer (natural throttle). Batching POs per supplier per 15 min |
| **Interview answer** | "429 is a signal to slow down, not a failure. I'd immediately lower concurrency so our throughput fits their limit, replay the DLQ slowly, and change the consumer to honour Retry-After through a delayed re-publish. Long term, throttle on our side to the partner's published limit, counted across all replicas." |

---

## Scenario 9 — Database connection pools become exhausted

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | Order API latency spikes and errors show `DB:CONNECTIVITY ... Timeout waiting for idle object`. All Process APIs on the integration DB are affected. **P1** |
| **Reproduce** | In PERF: put an HTTP call inside the DB transaction scope, add 5 s of latency to that HTTP backend, and load at 10 req/s with `maxPoolSize=10` |
| **Diagnose** | Pool metrics: active = max, waiters > 0. DB side: many connections "idle in transaction" (PostgreSQL `pg_stat_activity`). Code review of the recent change: a WMS reservation call was moved **inside** `try transactionalAction="ALWAYS_BEGIN"` |
| **Root cause** | Long transactions holding connections while waiting on a slow HTTP call |
| **Immediate mitigation** | Roll back to the previous version. If that's impossible, temporarily raise the pool (within DB limits) and lower the WMS timeout |
| **Permanent fix** | Move HTTP calls out of transactions. Keep transactions short (DB-only). Set `maxWait` to fail fast (2–3 s). PostgreSQL `idle_in_transaction_session_timeout` as a safety net |
| **Prevention & alerts** | Alert on pool utilisation > 80%, waiters > 0. A review checklist item: "no outbound I/O inside transactional scopes" |
| **Alternatives** | Separate pools per use case (bulkheads: the order flow's pool vs the recon job's pool) |
| **Interview answer** | "Pool exhaustion is usually a symptom of connections being held too long rather than too few connections. The DB showed sessions idle in transaction, and the recent change had put an HTTP call inside a transaction, so every slow WMS call held a DB connection. Roll back first, then move the call out of the transaction and add fail-fast settings and alerts. Raising the pool would only have delayed the outage." |

---

## Scenario 10 — Scatter-gather produces unpredictable latency

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | Order API p50 is fine (900 ms) but p99 is 7 s, and occasionally `MULE:COMPOSITE_ROUTING` errors appear. Salesforce users complain about random slowness. **P3** |
| **Reproduce** | One route with a long-tail latency (the Salesforce Sys customer lookup occasionally takes 6 s due to Salesforce query plans) |
| **Diagnose** | Per-route timings: the availability route is stable at 400–600 ms, while the customer route's p99 is 6.5 s. The scatter-gather has **no `timeout`**, and the route `responseTimeout` is 10 s. Distributed traces confirm the customer lookup span dominates |
| **Root cause** | The slowest route defines the scatter-gather latency. A non-selective SOQL query (no index on `SAP_Customer_Id__c`) and missing timeouts |
| **Immediate mitigation** | Set the route timeout to 2.5 s and the scatter-gather timeout to 3 s. Fall back to the SAP customer master on timeout (an alternative source) |
| **Permanent fix** | Mark `SAP_Customer_Id__c` as an External ID (indexed) in Salesforce. Cache customer status for 5 min with CDC invalidation on credit-block changes |
| **Prevention & alerts** | p99 alerting per outbound dependency, not only overall p95 |
| **Alternatives** | Sequential calls with early exit (if the customer is invalid, skip availability). That's sometimes better when one check usually fails fast |
| **Interview answer** | "Scatter-gather latency equals its slowest route, so the tail of one dependency becomes my API's tail. I'd measure per-route latency, give each route a timeout that fits the budget, decide a fallback per route, and then fix the slow dependency itself, here a non-indexed query. I'd also alert on per-dependency p99, because averages hide this." |

Next: [Scenarios 11–15](03-scenarios-11-15.md)
