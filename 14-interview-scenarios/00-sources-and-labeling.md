# 14.0 — How These Five Scenarios Were Chosen (and How They Are Labelled)

## Honesty label
**All five scenarios are "Representative senior-level scenarios".** They come from current job-description themes and established integration architecture practice. I did **not** find verified, published interview reports that attribute these exact questions to specific companies, so none is presented as "asked by company X".

## Evidence that these themes are current (job postings reviewed October 2026)

| Theme in the scenarios | Seen in current postings |
|------------------------|--------------------------|
| Senior MuleSoft roles for **supply chain** clients, owning delivery and **reviewing junior developers' code** | [Insight Global, MuleSoft Developer (supply chain client), 2026](https://insightglobal.com/jobs/find_a_job/pennsylvania/pittsburgh/mulesoft-developer-intl-india/job-539869/) |
| Integrating **ERP, MES, CRM, PLM, WMS** across cloud and on-prem in **manufacturing** | [iHireTechnology senior MuleSoft listing](https://www.ihiretechnology.com/jobs/view/523036285) |
| **SAP ECC → S/4HANA** migration integrations, SAP S/4HANA integration design | [Deloitte, Senior Consultant MuleSoft](https://southasiacareers.deloitte.com/job/Bengaluru-Senior-Consultant-Mulesoft-Bengaluru-Engineering/52533544), [Built In, Senior Engineer MuleSoft Developer](https://builtin.com/job/senior-engineer-mulesoft-developer/7320089) |
| Mule 4, RESTful APIs, **event-driven interfaces**, 5–8 years overall with 3+ on MuleSoft | Same postings as above; also [EPAM Senior MuleSoft Developer](https://careers.epam.com/en/vacancy/senior-mulesoft-developer-blt11f01fe13f52f6ac), [EY MuleSoft Senior](https://careers.ey.com/ey/job/Noida-MuleSoft-Senior-UP-201301/1283368801) |

*Postings change often, so links may expire. The themes are what matter.*

## The five scenarios

| # | Scenario | Why seniors get asked this |
|---|----------|---------------------------|
| [1](01-sap-timeout-after-commit.md) | SAP timeout after the transaction committed | Tests whether you understand unknown outcomes, idempotency and SAP specifics |
| [2](02-high-volume-messaging-duplicates-backlog.md) | High-volume messaging, duplicate events, backlog recovery | Tests at-least-once thinking, capacity and operations |
| [3](03-reliable-order-processing.md) | Reliable order processing across SAP, DB, broker and WMS | Tests end-to-end consistency design (outbox, saga) |
| [4](04-sync-vs-async-decision.md) | Synchronous orchestration vs asynchronous event-driven processing | Tests architectural judgement and trade-offs |
| [5](05-production-performance-degradation.md) | Production performance degradation (DataWeave, pools, concurrency, scaling) | Tests systematic diagnosis under pressure |

## How to practise
1. Read the question. **Close the file.** Answer out loud in 2 minutes, recording yourself.
2. Compare your answer with the model answer and the rubric. Score yourself honestly.
3. Repeat with the 5-minute version, drawing the diagram on paper or a whiteboard.
4. Have a friend ask the follow-up questions in random order.
