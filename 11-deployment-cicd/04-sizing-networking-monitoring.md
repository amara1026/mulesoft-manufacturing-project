# 11.4 — Runtime Sizing, Scaling, Concurrency, Networking and Observability

`Essential` (concepts) · `Advanced` (tuning)

## 1. Sizing and scaling

**Start from the workload, not from habit**

| Workload type | Bottleneck | Sizing lever |
|---------------|------------|--------------|
| I/O-bound API (Exp/Sys) | Waiting on backends | More replicas. Small vCores (0.5). Connection pools |
| Orchestration with DW (Prc) | CPU for DataWeave, heap for payloads | 1 vCore, 2+ replicas |
| SAP Sys with JCo | Heap (JCo buffers, XML), SAP-side limits | 1 vCore. Pool size agreed with SAP Basis |
| Batch | Heap + threads during load/process | 2 vCores, single replica, scheduled off-peak |
| MQ consumers | Downstream throughput | Replicas × `maxConcurrency` ≤ downstream capacity |

**Capacity math example (assumption):** peak 10 orders/s with SAP p95 1.5 s. By Little's Law, in-flight SAP calls ≈ 10 × 1.5 = 15. With 2 replicas, each needs ≥ 8 SAP connections plus headroom, so pool size 10 per replica, total 20 SAP connections. **Confirm that SAP can serve 20 concurrent RFC sessions** (dialog/RFC work processes). If it can't, use load levelling (Pattern 12).

**Vertical vs horizontal:** horizontal scaling (replicas) improves availability and throughput for stateless apps. Vertical scaling (bigger vCore) helps heavy DataWeave or memory-heavy batches. *Autoscaling for CloudHub 2.0 replicas may be available depending on your subscription and features. Check the current docs before promising it.*

## 2. Concurrency controls cheat-sheet

| Control | Where | Effect |
|---------|-------|--------|
| `maxConcurrency` on a flow | Flow attribute | Caps simultaneous events in that flow (a bulkhead) |
| HTTP requester `maxConnections` | Request config | Caps outbound connections to that backend |
| DB `maxPoolSize` + `maxWait` | DB config | Caps DB connections. Fail-fast wait |
| MQ subscriber concurrency/prefetch | Flow + subscriber | Parallel message processing |
| `parallel-foreach maxConcurrency` | Scope | Bounded fan-out |
| Batch `maxConcurrency`, `blockSize` | Batch job | Parallel blocks |
| Runtime thread pools | Runtime (UBER pool by default in Mule 4.x) | Usually leave the defaults. Tune only with evidence |

## 3. Networking checklist (CloudHub 2.0 → AIM data centre)

| Item | Detail |
|------|--------|
| **CIDR planning** | The Private Space CIDR must not overlap on-prem or other cloud ranges. Decide it early, because it's hard to change |
| **Connectivity** | Anypoint VPN (IPsec, redundant tunnels) or Transit Gateway attachment (AWS) |
| **Routing** | On-prem routes back to the Private Space CIDR. Test both directions |
| **Firewall** | Allow Private Space CIDR → SAP gateway ports (e.g. `33<sysnr>`, `48<sysnr>` for SNC), message server, WMS HTTPS, SFTP 22, DB 5432. Deny the rest |
| **DNS** | Private DNS forwarding so apps resolve `sap-qa.aim.local`. Public DNS CNAME `api.aim-example.com` → Private Space ingress |
| **Certificates** | Ingress certificate for custom domains. Truststores for internal CAs (SAP, WMS). Partner certs for mTLS |
| **Egress allow-list** | Partner endpoints (SupplierHub, carriers, Salesforce) |
| **Testing tools** | Use a network-diagnostic flow (temporary, internal) to test TCP connectivity and DNS from inside the Private Space. Remove it after use |

**Classic issue:** "works locally, fails on CloudHub." The cause is usually DNS (internal names not resolvable), the firewall (the Private Space CIDR isn't allowed), or a missing CA in the truststore. See [13 scenario 19](../13-production-troubleshooting/04-scenarios-16-20.md).

## 4. Observability: logs, metrics, traces, alerts

### Logging standard
```json
{
  "timestamp": "2026-10-13T08:02:02.512Z", "level": "INFO",
  "app": "order-mgmt-prc-api", "env": "prod", "version": "1.4.0",
  "flow": "prc-create-order-flow", "event": "SAP_ORDER_CREATED",
  "correlationId": "c0a8012e-...", "orderId": "AIM-20261013-7F3A9C21",
  "sapOrderNumber": "0000456789", "durationMs": 1432
}
```
- Log **business events** (`ORDER_RECEIVED`, `SAP_ORDER_CREATED`, `SAP_TIMEOUT_RECOVERED`) and **outbound call timings**, not every processor.
- Use a JSON layout in Log4j2, or the community **JSON Logger** module, consistently across apps.
- Forward logs to the enterprise platform (Splunk/ELK/Datadog). Retention and features in Anypoint Monitoring depend on subscription.

### Metrics and dashboards (per API)
- Golden signals: **rate, errors, duration (p95/p99), saturation** (CPU, heap, pools).
- Business metrics: orders/hour, 202 ratio, PENDING_ERP count, BACKORDERED ratio, recovered SAP timeouts.
- Messaging: depth, oldest age, DLQ depth per queue.
- Batch: last run status, duration, failed records.

### Tracing
- **Correlation ID** propagation is the minimum (HTTP header + MQ property + DB columns).
- **Distributed tracing** (OpenTelemetry-based in recent Mule versions and Anypoint Monitoring, subject to subscription) shows spans per hop. Use it to find the slow hop.

### Alerting rules (AIM)
| Alert | Condition | Severity |
|-------|-----------|----------|
| API error rate | 5xx > 2% for 5 min | P2 |
| Latency | p95 > 4 s for 10 min | P3 |
| SAP degradation | 202 ratio > 10% for 10 min | P2 |
| DLQ | depth > 0 on order/procurement/invoice queues | P2 |
| Queue age | oldest > 10 min | P2 |
| Outbox | oldest PENDING > 5 min | P2 |
| Replica health | restarts > 2 in 30 min | P2 |
| Cert expiry | < 30 days | P3 (P1 at < 7 days) |
| Batch | not completed by 03:00 | P2 |
| Missing file | supplier file not received by its window | P3 |

**Every alert links to a runbook section.** An alert without a runbook is just noise at 3 a.m.

Next: [11.5 Release checklist & runbook](05-release-checklist-runbook.md)
