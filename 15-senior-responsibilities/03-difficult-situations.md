# 15.3 — Difficult Project Situations: Technical Response and Communication

`Essential` — behavioural questions ("Tell me about a time…") are best answered with **STAR** (Situation, Task, Action, Result). For a simulated project, frame them as *"In this situation I would…"* and don't invent past results.

---

## Situation 1 — The SAP team can't provide a searchable reference field before go-live

**Technical response:** propose alternatives in order of preference: (1) an existing field (`BSTKD` customer PO) with an agreed format, (2) a header text plus an OData filter if performance is acceptable, (3) a Mule-side mapping table + time-window matching with manual review. Quantify the risk: the expected timeout rate (0.3% of orders) × volume ≈ 45 orders/day in the "unknown" state.

**Communication**
| Audience | Message |
|----------|---------|
| Architect | "Without a searchable reference, timeout recovery degrades from automatic to manual review. Options A/B/C with trade-offs in the attached ADR draft." |
| SAP lead | "We need one field we can filter by, at about 50 lookups/day. Can we use BSTKD with a prefix? Here's the expected load." |
| Business (sales ops) | "In rare cases (~45 orders/day), confirmation may be delayed and need a quick manual check. Here's the work queue process." |
| Tech lead / PM | "Risk logged. The decision is needed by the 15th to keep the go-live date." |

---

## Situation 2 — Scope change two weeks before UAT: "Add EDI suppliers too"

**Technical response:** assess the impact: EDI (X12 850/855/856) needs a B2B/EDI capability (partner manager or an EDI module), mappings, AS2/VAN connectivity and partner testing. Estimate: 6–8 weeks.

**Communication:** don't say "no". Present options:
1. Keep the go-live with REST/SFTP suppliers. EDI follows in phase 2 (recommended).
2. Delay the go-live by 6–8 weeks.
3. Interim: EDI suppliers receive POs as email/PDF from SAP output (the current process) until phase 2.

Escalate the decision to the product owner with the impact on dates, cost and risk. **The senior's job is to make the trade-off explicit, not to absorb it silently.**

---

## Situation 3 — Production incident at quarter-end and the business wants a quick fix

**Situation:** duplicate POs are being created (scenario 2). Procurement wants "just switch the integration off".

**Technical response:** pause *only* the procurement consumer (shortage events accumulate safely in the queue). Order intake keeps running. Deploy the lookup-before-create fix within hours via the hotfix path, with targeted tests. Drain the queue with monitoring.

**Communication:** incident updates every 30 minutes: impact (12 duplicate POs, all identified), containment (consumer paused, nothing lost), next steps and ETA. Afterwards, a blameless postmortem with actions.

---

## Situation 4 — Disagreement with an architect about adding a Process API

**Situation:** the architect insists every Experience API must call a Process API, even for the simple "get tracking" call (Exp → Prc → Sys), which would be a pass-through Process API.

**Response:** bring data and principles, not opinions: the extra hop's latency, deployment cost (vCores) and ownership overhead, versus the benefit (there's no orchestration today). Propose a **decision rule** recorded in an ADR: "Skip the Process layer when there is no orchestration or business rule. Introduce it when one appears." Accept the architect's final call gracefully if they still disagree, and document the trade-off.

---

## Situation 5 — A junior's code passed review but caused a production issue

**Response:** own it as a team ("we approved it"). Fix it, then improve the system: add the missing test type and update the review checklist. Mentor privately. **Never** blame in public channels or postmortems.

---

## Situation 6 — Partner (WMS vendor) misses deadlines for their webhook implementation

**Technical response:** decouple with an interim **polling** integration (`GET /events?since=`, Pattern 21) behind the same Warehouse Exp API contract. Switch to webhooks later without affecting consumers.

**Communication:** escalate the dependency risk early in the RAID log, with dates. Present the interim solution's cost (a polling app, slightly higher latency) to the PM.

---

## Situation 7 — Testers report "random failures" in SIT

**Response:** turn "random" into data: collect correlation IDs, times and environments, then look for patterns (time of day → the SAP QA client is refreshed nightly at 02:00; specific materials → missing master data). Often SIT instability comes from **environment and test data**, not code. Fix the environment process: a refresh calendar, test data scripts.

---

## Communication cheat-sheet by audience

| Audience | Cares about | Format |
|----------|-------------|--------|
| Business stakeholders | Impact on orders/customers/money, dates, workarounds | Plain language, no jargon, options with impact |
| Architects | Principles, consistency, long-term impact, alternatives | ADRs, diagrams, trade-off tables |
| Tech lead / PM | Scope, estimates, risks, dependencies | RAID log, estimates with assumptions |
| Developers | How, standards, examples | Code, templates, pairing |
| Testers | What to test, data, expected results, environments | Test scenarios, acceptance criteria |
| Support/ops | Symptoms, runbooks, alerts, escalation paths | Runbooks, dashboards, handover sessions |

## Interview angle
**Q: "Tell me about a time you pushed back on a requirement."** *(For simulated experience, answer hypothetically or map to your real projects.)*
> "When a request would compromise reliability or the timeline, I don't just say no. I clarify the underlying need, quantify the impact and offer options. For example, if a late request added EDI suppliers before UAT, I'd estimate it, then present three choices: keep the date and do EDI in phase two, delay the go-live, or use an interim manual process. The product owner then makes an informed decision, and I record it."
