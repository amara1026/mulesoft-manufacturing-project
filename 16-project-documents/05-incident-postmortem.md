# 16.5 — Incident Report and Blameless Postmortem (Document 17)

`Essential` · *A fictional incident for training. It shows the structure and the expected depth.*

## Part A — Incident report (written during the incident, kept short)

```markdown
INC-4471 | P2 | Status: Resolved
Title: Duplicate purchase orders sent to suppliers after SAP slowdown
Detected: 2026-09-30 11:42 CET by Procurement (user report)  — no automated alert fired
Impact: 37 duplicate POs (value ≈ 182k USD, assumption) sent to 9 suppliers; no goods shipped yet
Current status: Consumer paused 12:05; duplicates identified 12:40; fix deployed 16:10; queue drained 17:30
Next update: n/a (resolved)
Commander: <name>  Comms: <name>  Scribe: <name>
```

## Part B — Postmortem

### 1. Summary
On 30 Sep, SAP response times rose to 6–9 s during the month-end close. The procurement consumer's SAP PO creation timed out after 6 s, but SAP had committed the PO. The message was redelivered, and the consumer created the PO again. Between 10:58 and 12:05, 37 duplicate POs were created and transmitted. No duplicate goods were shipped, because all duplicates were cancelled with suppliers by 1 Oct 15:00.

### 2. Impact
| Dimension | Impact |
|-----------|--------|
| Business | 37 duplicate POs, 9 suppliers contacted, about 6 h of buyer effort |
| Customers | None (no order delays) |
| Financial | None realised. Risk of ~182k USD of excess inventory avoided |
| Data | SAP POs cancelled. Integration DB corrected |

### 3. Timeline (CET)
| Time | Event |
|------|-------|
| 10:30 | SAP month-end job starts. Dialog work processes heavily used |
| 10:58 | First procurement timeout (6 s). The message is nacked and redelivered. A second PO is created |
| 11:00–12:05 | 37 duplicates (one per timed-out message) |
| 11:42 | Buyer notices two POs for the same shortage and calls the service desk |
| 11:50 | L2 escalates to L3 on-call. Incident INC-4471 opened (P2) |
| 12:05 | L3 pauses the procurement consumer (shortage events queue safely) |
| 12:40 | SQL + SAP query identifies all 37 duplicates by reference text |
| 13:00–15:30 | Fix developed: business-key claim + lookup-before-create. MUnit + QA chaos test |
| 16:10 | Hotfix 1.6.1 deployed |
| 16:15 | Consumer resumed at reduced concurrency |
| 17:30 | Backlog drained. No new duplicates |
| 1 Oct 15:00 | All duplicates cancelled and suppliers confirmed |

### 4. Root cause
The consumer treated `HTTP:TIMEOUT` from the SAP System API as a failure and relied on MQ redelivery to retry. The retry performed a **blind create**. The design had no business-level idempotency key and no lookup of existing POs by reference.

### 5. Contributing factors
- SAP latency at month-end exceeded the 6 s timeout (known seasonal pattern, not reflected in the timeout budget).
- No alert on `sap_timeout_total` or on duplicate PO references, so detection relied on a human.
- The test strategy didn't cover "commit succeeded but response timed out".
- The month-end SAP job schedule wasn't shared with the integration team.

### 6. What went well
- The consumer could be paused without affecting order intake (async decoupling worked).
- The business reference text in POs made the duplicates identifiable in under an hour.
- Fast hotfix path with automated tests.

### 7. Action items
| # | Action | Type | Owner | Due | Status |
|---|--------|------|-------|-----|--------|
| A1 | Business-key table + lookup-before-create in procurement (done in 1.6.1) | Fix | Dev team | 30 Sep | ✅ |
| A2 | Same pattern for production orders and billing (audit of all create operations) | Prevent | Senior dev | 15 Oct | ⏳ |
| A3 | Alert: SAP timeout rate > 1% (5 min), duplicate PO reference count > 0 (daily recon) | Detect | Ops | 10 Oct | ⏳ |
| A4 | Chaos test "slow commit" added to the SIT suite for all SAP create flows | Prevent | QA | 20 Oct | ⏳ |
| A5 | SAP month-end calendar shared. Integration traffic moved to a dedicated logon group | Mitigate | SAP Basis | 31 Oct | ⏳ |
| A6 | Code review checklist item: "creates must be idempotent with lookup on unknown outcome" | Prevent | Integration lead | 5 Oct | ✅ |

### 8. Lessons learned
- **A timeout is an unknown outcome.** Every create needs an idempotency strategy that includes a lookup.
- **Redelivery is a retry.** Broker-level retries need the same idempotency guarantees as explicit ones.
- **Detection shouldn't depend on users.** Business-level reconciliation alerts (duplicates = 0) are cheap and effective.

### 9. Blameless note
This postmortem focuses on system and process gaps. The original design passed review by several engineers, so the gap was collective and is now addressed in standards and tests.

---

**How these documents are used:** the incident report keeps stakeholders informed *during* the incident. The postmortem is reviewed in a 45-minute meeting within 5 business days. Action items go into the backlog with owners and due dates and are tracked to completion in the weekly ops review.

Next section: [17 — Mock interviews](../17-mock-interviews/01-five-minute-project-pitch.md)
