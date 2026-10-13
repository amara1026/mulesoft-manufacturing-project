# 13.3 — Troubleshooting Scenarios 11–15

---

## Scenario 11 — Warehouse and ERP inventory balances disagree

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | Nightly recon: 1,240 material/location differences, against a normal level of ~30. Sales promise stock that doesn't physically exist, so backorders are discovered at picking. **P2** |
| **Reproduce** | Drop goods-receipt events (simulate a consumer failure) for a day, then run the recon |
| **Diagnose** | Classify the differences: (a) timing: in-flight documents at the cut-off, (b) stock type, (c) UoM, (d) missing postings. Here ~1,150 diffs are positive in the WMS and missing in SAP, all for goods receipts at DC-EU-01 since Tuesday 14:00. DLQ for `gr-events`: 0 messages. Consumer logs: messages acked but **filtered out**. A WMS release on Tuesday renamed `movementType` → `mvtType`, so the consumer's filter dropped every message silently |
| **Root cause** | An upstream schema change plus a filter without validation or metrics |
| **Immediate mitigation** | Hot-fix the mapping to accept both field names. Replay Tuesday–Thursday GR events from the WMS's export/replay API. Re-run the recon |
| **Permanent fix** | Schema validation on consumer input (unknown or missing fields → DLQ, not dropped). Metrics on filtered counts. A contract with the WMS vendor including change notification |
| **Prevention & alerts** | Alert when filtered messages > 5% of the input. Recon diff count > 2× baseline. Absence alert: "no GR posted for DC-EU-01 in 2 h during working hours" |
| **Alternatives** | Event schemas registered and validated at the Exp API boundary (reject non-conforming webhooks with 400, so the WMS sees the error) |
| **Interview answer** | "I'd classify the differences before correcting anything: timing, stock types, units, or missing postings. Here they all clustered on one site and one day, which pointed to an integration failure, not physical loss. The cause was a silent filter after a WMS field rename. Fix the mapping, replay the missed events, re-reconcile. Then make it impossible to be silent again: validate the schema, count filtered messages, and alert on absent events." |

---

## Scenario 12 — Supplier confirmations arrive late or out of order

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | SAP POs show the wrong confirmed dates. A v2 date change (Oct 22 → Oct 29) was overwritten by a delayed v1 (Oct 22). Planners expedite the wrong orders. **P3** |
| **Reproduce** | Send confirmation v2, then v1, to a standard queue with 2 consumers |
| **Diagnose** | Supplier message log: v1 sent 09:00, v2 sent 09:05, v1 *retried* by the supplier at 09:20 (their own timeout). Our processing: v2 applied 09:06, v1 applied 09:21. There's no version check |
| **Root cause** | Last-arrival-wins processing without version/timestamp comparison. The partner's retries reorder messages |
| **Immediate mitigation** | Correct the affected POs in SAP from the supplier's latest confirmation (query the supplier portal) |
| **Permanent fix** | Store `lastAppliedVersion` per PO line. Apply only if `version > lastApplied`. Otherwise ignore and log. Where full sequence semantics matter, use the resequencer (park + timeout). FIFO queue with message group = PO for in-transit order |
| **Prevention & alerts** | Metric for "stale confirmation ignored" (expected to be non-zero). Alert if parked messages are older than 4 h |
| **Alternatives** | Ask suppliers to send the full current state (state transfer) instead of incremental changes, which makes the operation naturally order-tolerant |
| **Interview answer** | "Partner retries reorder messages, so ordering must be enforced by data, not by arrival. I'd add a version or source timestamp per PO line and apply only newer versions. For flows where each step matters, I'd resequence with parking and a timeout, plus FIFO with message groups to keep order in transit." |

---

## Scenario 13 — An MES event is delivered more than once

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | SAP shows double goods receipts for finished goods (2 pumps instead of 1) for production order 1000234. Inventory is overstated and financial postings are wrong. **P2** |
| **Reproduce** | The plant runtime reconnects after a WAN blip and re-sends its local buffer (events already published before the disconnect) |
| **Diagnose** | Two `mes.production-completed` events with the **same MES eventId** published 3 minutes apart. The consumer deduped with an in-memory Object Store, and the replica restarted in between, so the second event wasn't detected |
| **Root cause** | Non-persistent dedupe store plus a non-idempotent SAP posting (GR) |
| **Immediate mitigation** | Reverse the duplicate GR in SAP (movement type reversal) with the production controller. Check other orders in the window |
| **Permanent fix** | DB inbox keyed by MES eventId. A business key for GR: `(prodOrder, batch, confirmationCounter)`. Lookup of existing confirmations in SAP before posting. The plant runtime tracks published offsets durably |
| **Prevention & alerts** | Recon: production order confirmed qty vs GR qty. Alert on mismatches |
| **Alternatives** | Post GR through SAP's confirmation BAPI with automatic GR, so SAP's confirmation counter prevents double posting |
| **Interview answer** | "MES and IoT sources resend on reconnect by design, so duplicates are certain. Dedupe has to be durable, which rules out in-memory stores on restartable replicas, and the posting itself should be idempotent on a business key like production order plus batch. I'd reverse the duplicate postings with the business and add a reconciliation check between confirmed and received quantities." |

---

## Scenario 14 — A certificate expires and breaks an integration

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | 00:00 UTC: all calls to FreightLink fail with `PKIX path validation failed` / `certificate expired`. Shipments can't be booked and trucks are waiting at the docks. **P1** |
| **Reproduce** | Use an expired client certificate in a QA keystore |
| **Diagnose** | Error type `HTTP:SECURITY` / TLS handshake failure. `openssl s_client -connect` from a diagnostic environment shows which cert is expired: **our client certificate** for mTLS to the carrier, expiring 2026-10-13 |
| **Root cause** | No certificate inventory or expiry alerting. The owner had left the company |
| **Immediate mitigation** | Emergency renewal (CA issues a new cert). Update the keystore (secure property / vault). Redeploy. Exchange the new cert with the carrier if they pin it. Meanwhile, the logistics desk books manually on the carrier portal, and events queue (no data lost) |
| **Permanent fix** | Certificate inventory (owner, expiry, partner contact). Automated expiry checks with 60/30/14/7-day alerts. Renewal runbook. Prefer certificates managed by a platform with automatic rotation where possible |
| **Prevention & alerts** | Monthly cert report to the integration lead. Synthetic mTLS check daily |
| **Alternatives** | OAuth client credentials instead of mTLS, if the partner supports it (secret rotation still needs managing, but it's easier) |
| **Interview answer** | "This is a process failure more than a technical one. Immediate: renew and redeploy, and keep the business running with a manual workaround while events queue safely. Permanent: a certificate inventory with owners and automated expiry alerts well in advance, plus a tested renewal runbook. In the postmortem I'd ask why no alert existed, not who forgot." |

---

## Scenario 15 — Authentication tokens expire during processing

| Aspect | Detail |
|--------|--------|
| **Symptoms & impact** | The nightly supplier price batch fails after ~60 minutes with 401s from SupplierHub on the remaining blocks. Half the prices aren't updated. **P3** |
| **Reproduce** | Token TTL 60 min, batch duration 90 min. The token was fetched once at job start and stored in a variable |
| **Diagnose** | 401 responses start at 01:16, exactly 60 min after the token fetch. Code: the token was cached in `vars.token` at batch start and reused by every block |
| **Root cause** | Manual token handling without refresh. The token outlived its validity |
| **Immediate mitigation** | Re-run the failed records (failure table) |
| **Permanent fix** | Use the HTTP connector's **OAuth client-credentials** configuration (automatic caching + refresh), with `refreshTokenWhen` on 401. Or a token cache in Object Store with TTL = `expires_in` − 5 min, checked per call |
| **Prevention & alerts** | Test long-running jobs with short-lived tokens in QA (e.g. a 5-min TTL). Alert on 401 spikes |
| **Alternatives** | Ask for a longer token TTL for batch clients (a security trade-off). Split the job |
| **Interview answer** | "Tokens must be treated as expiring resources, not constants. I'd let the HTTP connector's OAuth support manage caching and refresh, with a refresh-on-401 rule as a safety net, and test long jobs with artificially short token lifetimes so the problem shows up in QA." |

Next: [Scenarios 16–20](04-scenarios-16-20.md)
