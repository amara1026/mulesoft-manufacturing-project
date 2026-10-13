# 15.1 — The Senior MuleSoft Developer's Role: Requirements, Design, ADRs, Estimation and Delivery

`Essential` — interviews for senior roles test this as much as technical depth.

## 1. What changes at senior level

| Mid-level developer | Senior developer |
|--------------------|------------------|
| Implements the story as written | Questions the story until the requirement is clear, testable and feasible |
| Asks "how do I build this?" | Asks "should we build this, and what happens when it fails?" |
| Owns their flows | Owns the integration's quality, operability and design consistency across the team |
| Fixes bugs | Fixes classes of bugs (standards, templates, tests, alerts) |
| Reports status | Surfaces risks early, with options |

## 2. Requirement clarification (example)

**Story as written:** *"As a buyer, I want POs sent to suppliers automatically."*

**Questions a senior asks:**
| Area | Question |
|------|----------|
| Trigger | On PO creation, on release (approval), or on change too? |
| Scope | All suppliers, or only those onboarded to SupplierHub? What about the others (email/SFTP)? |
| Content | Which PO fields? Attachments (drawings)? Text items? |
| Changes and cancellations | Do PO changes and cancellations also go? How does the supplier acknowledge? |
| Volume | POs/day, lines/PO, peak periods? |
| Errors | If the supplier rejects the PO, who is told, and how? |
| SLA | Must the supplier receive it within minutes, or is the same day fine? |
| Security | Supplier auth model? Data classification? |
| Acceptance | How will the business confirm it works? (Test suppliers in UAT?) |

**Output:** refined acceptance criteria + NFRs + open questions logged with owners and dates.

## 3. Design reviews

**Review the design *before* code, using a checklist:**
- [ ] API-led placement justified (which layer, why, reuse)
- [ ] Contract: RAML published, error contract, versioning
- [ ] Idempotency: keys, storage, retention
- [ ] Failure modes table: timeout, unavailable, business error, duplicate, out-of-order
- [ ] Transaction boundaries and the consistency model stated
- [ ] Security: auth in/out, PII, secrets
- [ ] Observability: logs, metrics, alerts, runbook entries
- [ ] Capacity: volume, peak, downstream limits
- [ ] Testability: what can be mocked, test data needs
- [ ] Operational ownership: who supports it at 3 a.m.

## 4. Architecture Decision Records (ADRs)

**Template + AIM example**
```markdown
# ADR-007: Use a transactional outbox for order events

Status: Accepted (2026-09-02)  ·  Deciders: integration lead, architect, senior devs
## Context
Order Prc API must update integration DB and publish events to Anypoint MQ. Publishing after
commit risks lost events on crash/MQ outage; publishing before commit risks phantom events.
## Decision
Write events to an outbox table in the same local DB transaction as the order state.
A relay (scheduler, 3 s) publishes PENDING rows and marks them PUBLISHED.
Consumers deduplicate via inbox (event_id).
## Consequences
+ No lost events; MQ outages don't block order intake.
- 2–5 s publication latency; extra table + cleanup job; at-least-once (duplicates) → consumers must be idempotent.
## Alternatives considered
1. Publish after commit with retry — rejected: crash window loses events.
2. XA (DB + MQ) — not supported for Anypoint MQ.
3. CDC (Debezium) relay — deferred: more infrastructure; revisit if latency matters.
```
ADRs live in the repo (`/docs/adr`). They stop decisions being re-argued every quarter, and they onboard new team members quickly.

## 5. Estimation and sprint planning

**Break integrations into estimable tasks (example: "Supplier PO transmission")**

| Task | Estimate (ideal days) | Notes / risks |
|------|----------------------|---------------|
| RAML + review + Exchange publish (supplier-sys-api) | 1.5 | Depends on the SupplierHub API docs |
| SupplierHub OAuth + connectivity in DEV | 1 | **Risk:** firewall/VPN lead time, so start early |
| DataWeave mapping PO → SupplierHub + golden tests | 2 | Mapping spec sign-off needed |
| Procurement consumer: inbox, business key, retries, DLQ | 3 | |
| 429 handling + throttling | 1 | |
| MUnit (≥ 80%) + negative tests | 2 | |
| SIT with 3 test suppliers | 2 | Test data from the SAP MM team |
| Runbook, alerts, dashboards | 1 | |
| **Total** | **13.5** + 20% contingency | |

**Senior estimation habits**
- Estimate **dependencies separately** (firewall rules, SAP authorisations, partner sandbox access), because they dominate the calendar time, not the effort.
- State assumptions explicitly ("assumes the SupplierHub sandbox is available by sprint 2").
- Use ranges for unknowns. Re-estimate after spikes.
- Include non-coding work: reviews, testing, documentation, deployment, hypercare.

## 6. Cross-team dependencies and coordination

| Team | What you need from them | How to make it smooth |
|------|------------------------|-----------------------|
| SAP functional (SD/MM/PP) | BAPI choice, field semantics, test data, reference field | A mapping workshop. A signed-off mapping spec |
| SAP Basis/security | RFC user, authorisations, SNC, gateway registration | Raise requests in sprint 0. They have long lead times |
| WMS vendor | API docs, sandbox, webhook config, change notices | Contract + change-notification agreement |
| MES/plant IT | Event formats, plant network, hybrid runtime hosts | Site visits / plant calls. Respect production windows |
| Suppliers/carriers | Credentials, certificates, test endpoints | An onboarding checklist per partner |
| Network/infra | VPN, firewall, DNS | Clear request templates with ports/CIDRs |
| DevOps | Pipelines, environments, secrets | Pipeline templates shared across apps |
| QA | Test plans, data, environments | Involve them in story refinement |

**Dependency tracking:** a RAID log (risks, assumptions, issues, dependencies) reviewed weekly with the integration lead.

Next: [15.2 Code reviews & mentoring](02-code-review-and-mentoring.md)
