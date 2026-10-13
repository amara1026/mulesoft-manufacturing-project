# 09.3 — Load/Performance Testing and Deployment Smoke Tests

`Essential` (smoke) · `Advanced` (performance engineering)

## 1. Performance test plan (summary — full template in [16.3](../16-project-documents/03-test-documents.md))

| Item | Value (assumptions) |
|------|---------------------|
| Objective | Validate NFR-P1/P2 (10 orders/s peak, p95 ≤ 4 s) and NFR-P5 (2M-row batch ≤ 60 min) |
| Tool | Apache JMeter (or k6/Gatling) + Anypoint Monitoring + DB/MQ metrics |
| Environment | PERF: same replica sizes as prod. SAP **stubbed with a latency distribution** (p50 900 ms, p95 1.5 s, p99 3 s) |
| Data | 5,000 synthetic customers, 2,000 materials, unique idempotency keys per request |
| Workload | Ramp 0 → 10 req/s over 5 min, hold 30 min, spike to 25 req/s for 5 min, soak 4 h at 3 req/s |

### Test types
| Type | Question it answers |
|------|---------------------|
| **Load** | Does it meet SLAs at expected peak? |
| **Stress** | Where does it break, and *how*? (graceful 202/503, or meltdown?) |
| **Spike** | Do rate limits, spike control and queue levelling behave? |
| **Soak / endurance** | Memory leaks, connection leaks, growing queues over hours? |
| **Volume** | Batch with 1×, 2× and 3× production file sizes |

### What to measure

| Layer | Metrics |
|-------|---------|
| API | Throughput, p50/p95/p99 latency, error rate by code, 202 ratio |
| Mule runtime | CPU, heap, GC pause time, thread pool usage |
| Outbound | Per-dependency latency, `HTTP:TIMEOUT` counts, connection pool waits |
| DB | Active connections vs pool size, slow queries, lock waits |
| MQ | Queue depth, oldest message age, publish/consume rates, DLQ |
| Batch | Records/s, step durations, failed record count, heap during load phase |

### Reading results like a senior
- **Latency rises while throughput is flat** → saturation somewhere. Look for pool waits (DB, HTTP `maxConnections`) and thread starvation.
- **Errors appear only above N req/s** → a hard limit (SAP connections, DB `max_connections`, partner rate limit).
- **Heap saw-tooth climbing over a soak** → a leak (unbounded cache, in-memory Object Store growth, large vars held).
- Always compare with a **baseline** from the previous release.

### JMeter essentials for this API
- **HTTP Header Manager:** `Authorization`, `x-correlation-id = ${__UUID()}`, `Idempotency-Key = PERF-${__UUID()}`.
- **CSV Data Set Config:** customers and materials.
- **Assertions:** response code 201/202, JSON path `$.orderId` exists.
- **Backend Listener** → time-series DB/Grafana, or export the JTL for reports.

## 2. Deployment smoke tests (every environment, every deploy)

**Goal:** prove in about 2 minutes that the deployment is alive, wired correctly and safe, *without* creating business side effects in production.

| # | Check | How | Prod-safe? |
|---|-------|-----|-----------|
| S1 | App status RUNNING, all replicas ready | Runtime Manager API / CLI | ✔ |
| S2 | Health endpoint | `GET /api/health` → 200 with dependency checks (DB ping, MQ reachability, SAP Sys health) | ✔ |
| S3 | Policies applied | Call without a token → 401. With a valid token → 200 | ✔ |
| S4 | Read path | `GET /api/v1/orders/{known-test-order}` → 200 | ✔ |
| S5 | Synthetic write | Order for **test customer `CUST-SMOKE-01`** (excluded from fulfilment/billing by an SAP config agreement) | ⚠ Only if agreed with the business |
| S6 | Correlation ID | Response header echoes the sent ID. Logs searchable by it | ✔ |
| S7 | Error contract | Invalid payload → 400 with the AIM error schema | ✔ |
| S8 | Version | `GET /api/health` returns `appVersion=1.4.0`, matching the release | ✔ |

### Example health response (implemented by a `/health` flow)
```json
{
  "status": "UP",
  "appVersion": "1.4.0",
  "checks": { "database": "UP", "messaging": "UP", "sapSysApi": "UP" },
  "timestamp": "2026-10-13T09:00:00Z"
}
```
**Design note:** keep a **liveness** check (the app is up) separate from a **readiness/deep** check (dependencies are up). Don't let a SAP outage make the platform restart your replicas. That's why the deep check is not used as a liveness probe.

## 3. Interview angle
**Q: "Performance testing shows p95 at 9 s at 10 orders/s. How do you find the bottleneck?"**
> "First I break the latency down per hop using the logs' durationMs per outbound call and the correlation ID. Usually one dependency dominates. Then I look for queueing rather than slowness: HTTP requester pool waits, DB pool waits, thread pool saturation in the runtime. If SAP's own latency is fine but our calls queue, it's our pool size or concurrency. If SAP itself slows down under load, it's SAP capacity, and the answers are load levelling, reducing calls (cache master data, simulate less), or agreeing more SAP work processes. I change one variable at a time and rerun."

Next section: [10 — Security & governance](../10-security-governance/01-security-architecture.md)
