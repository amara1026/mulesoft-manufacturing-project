# 18.2 — Learning Roadmap: Milestones 7–12

---

## Milestone 7 — Integration patterns & asynchronous processing

**Study:** [07-integration-patterns](../07-integration-patterns/01-api-and-routing-patterns.md) (all 7 files)

**Learning goals**
- ⭐ Explain all 35 patterns with an AIM use case and a "don't use when"
- ⭐ Pub-sub vs point-to-point, load levelling, async request-reply, webhooks
- ◆ Backpressure, fan-in, resequencing

**Hands-on exercises**
1. Make flash cards: pattern name → (problem, Mule component, failure handling, trade-off). Drill daily.
2. In the mini project, add a second consumer (analytics logger) to the order events, implementing **pub-sub** with a second VM queue fed by the relay.
3. Implement **version-based ordering** for a `supplier-confirmation` consumer (ignore stale versions).

**Expected results:** both consumers receive each event. Stale confirmations are logged as ignored.

**Common mistakes:** describing patterns abstractly with no Mule specifics. Never mentioning when *not* to use them.

**Interview questions:** "Explain queue-based load levelling with a real case." "How do webhooks fail?" "Fan-out vs scatter-gather?"

**Practical assessment:** pick 5 random patterns and explain each in 60 seconds, including its trade-off.

**Readiness score:** 7+ = 30 of 35 patterns explained fluently with use cases

---

## Milestone 8 — Error handling, transactions, idempotency & recovery

**Study:** [06.3](../06-mule-implementation/03-error-handling.md), [08-reliability-transactions](../08-reliability-transactions/01-end-to-end-order-flow.md) (all)

**Learning goals**
- ⭐ Unknown outcome vs failure. Lookup-then-create
- ⭐ Idempotency layers (client key, inbox, business key, SAP reference)
- ⭐ Outbox/inbox, saga compensation vs forward recovery
- ⭐ Delivery guarantees, stated honestly
- ◆ Reconciliation and replay design

**Hands-on exercises**
1. In the mini project, run the `TIMEOUT-` scenario and trace it: timeout → lookup → recovered.
2. Kill Studio (stop the app) right after the SAP mock commits. Restart and resubmit with the same key, then observe the behaviour and explain it.
3. Write the SQL for an "orders PENDING_ERP > 15 min" recon and a "duplicate SAP reference" check.

**Expected results:** no duplicate SAP order in the mock store, and you can explain each table row's state.

**Common mistakes:** "exactly-once" claims. Compensating on timeouts. Object Store for financial dedupe.

**Interview questions:** the six cases in [08.5](../08-reliability-transactions/05-distributed-transaction-examples.md).

**Practical assessment:** answer [14.1](../14-interview-scenarios/01-sap-timeout-after-commit.md) and [14.3](../14-interview-scenarios/03-reliable-order-processing.md) and score yourself with their rubrics.

**Readiness score:** 7+ = ≥ 12/15 on 14.1 and ≥ 14/18 on 14.3

---

## Milestone 9 — MUnit, integration tests, contract tests, performance testing

**Study:** [09-testing](../09-testing/01-munit-unit-testing.md) (all), [16.3](../16-project-documents/03-test-documents.md)

**Learning goals**
- ⭐ MUnit structure, mocks by doc:name, error mocks, spies, verify-call, expectedErrorType
- ⭐ Negative-path coverage and coverage gates
- ⭐ SIT scenario design. Newman contract tests
- ◆ JMeter load profiles. Reading bottlenecks

**Hands-on exercises**
1. Run `mvn clean test` on the mini project (or run the suites in Studio). Then add a test: **WMS down** → expect an error, with no SAP call.
2. Add a golden-file test for the canonical → SAP XML mapping.
3. Run the Postman collection with Newman from the command line.
4. Optional ◆: a JMeter test at 5 req/s against the local app. Observe the latency when the SAP mock delay is increased.

**Expected results:** new tests pass. Coverage report generated. Newman report shows 100% passed.

**Common mistakes:** assertions on "not null". Shared state between tests. Unmocked connectors.

**Interview questions:** "How do you test error handlers?" "What's your coverage policy?" "How do you test async flows?"

**Practical assessment:** write an MUnit test from scratch in 20 minutes for "SAP business error → reservation released".

**Readiness score:** 7+ = you can write and debug MUnit tests without copying

---

## Milestone 10 — Security, API governance & CI/CD

**Study:** [10-security-governance](../10-security-governance/01-security-architecture.md) (all), [11.2–11.3](../11-deployment-cicd/02-maven-git-workflow.md)

**Learning goals**
- ⭐ OAuth2 client credentials, JWT validation, client ID enforcement, mTLS
- ⭐ Policy stack, rate limiting vs spike control, threat protection
- ⭐ Secure properties, PII masking, least privilege
- ⭐ Maven lifecycle, build once deploy many, pipelines with gates
- ◆ Vault integration, governance rulesets, BOLA

**Hands-on exercises**
1. Anypoint trial: create an API instance for the mini project's Exp API, add autodiscovery, apply client ID enforcement + rate limiting, and test the 401 and 429 responses.
2. Encrypt a property with the Secure Properties Tool and use it in the app.
3. Write a GitHub Actions or Azure DevOps YAML that runs `mvn verify` with a coverage gate.

**Expected results:** the policies are enforced (429 after the limit). The secure property resolves at runtime. The pipeline fails when a test fails.

**Common mistakes:** secrets in YAML. Rate limits per replica without accounting for replica count. No fine-grained authorisation.

**Interview questions:** "How do you secure supplier APIs?" "Where does rate limiting belong?" "How do you make rollback safe?"

**Practical assessment:** present the security architecture (Diagram 18) and the CI/CD sequence (Diagram 19) in 5 minutes.

**Readiness score:** 7+ = you can apply policies and explain the control placement matrix

---

## Milestone 11 — Deployment, monitoring & production troubleshooting

**Study:** [11.1, 11.4, 11.5](../11-deployment-cicd/01-deployment-options.md), [12-performance](../12-performance/01-timeouts-retries-pools.md), [13-production-troubleshooting](../13-production-troubleshooting/00-troubleshooting-method.md)

**Learning goals**
- ⭐ CloudHub 2.0 concepts (Private Space, replicas, ingress), vs CH1/RTF/hybrid
- ⭐ Timeout budgets, pools, retry storms, capacity with Little's Law
- ⭐ The 7-step troubleshooting method. Explain all 20 scenarios
- ◆ DR strategy, distributed tracing

**Hands-on exercises**
1. Deploy the mini project to CloudHub 2.0 (trial shared space). Check the logs and the default dashboards.
2. Pick 10 of the 20 scenarios and explain each out loud in 90 seconds using the template.
3. Do the capacity maths for 20 orders/s with SAP p95 = 2 s across 3 replicas.

**Expected results:** the app runs in the cloud. Explanations follow the method (stabilise → scope → signals → hypotheses → test → fix → learn).

**Common mistakes:** "add retries" / "add replicas" as the first answer. No data remediation. No prevention step.

**Interview questions:** the scenarios in 13.1–13.4. "How do you size for quarter-end?"

**Practical assessment:** a friend picks 3 random scenarios. You answer each in 3 minutes.

**Readiness score:** 7+ = all answers follow the method and include prevention

---

## Milestone 12 — Five challenging interview scenarios & mock interviews

**Study:** [14-interview-scenarios](../14-interview-scenarios/00-sources-and-labeling.md) (all), [17-mock-interviews](../17-mock-interviews/01-five-minute-project-pitch.md) (all), [15-senior-responsibilities](../15-senior-responsibilities/01-role-and-delivery.md)

**Learning goals**
- ⭐ A five-minute pitch, delivered smoothly
- ⭐ 2-minute and 5-minute answers for the five deep scenarios
- ⭐ The 15 core questions + 30 additional questions
- ⭐ Behavioural answers (STAR) about reviews, mentoring, disagreements, incidents

**Hands-on exercises**
1. Record your pitch three times. Score it with the checklist in 17.1.
2. Two mock interviews (60 min each) with a peer: 10 min pitch + Q&A, 30 min deep scenario, 20 min mixed questions.
3. Prepare 3 STAR stories from your **real** experience mapped to: an incident, a design disagreement, mentoring.

**Expected results:** each deep scenario scores ≥ 80% on its rubric. The pitch is under 5 minutes and covers every checklist item.

**Common mistakes:** memorised answers that collapse under follow-ups. Presenting simulated results as real. Not asking clarifying questions.

**Practical assessment (final):** a full 90-minute mock interview. Pass criteria: ≥ 12/15 on two deep scenarios, a confident pitch, and no factual errors on MuleSoft behaviour.

**Readiness score (overall):**
| Score | Meaning |
|-------|---------|
| 9–10 | Ready for senior/lead interviews. Focus on company-specific research |
| 7–8 | Ready for senior developer roles. Polish weak scenarios |
| 5–6 | Repeat milestones 8, 11 and 12 |
| < 5 | Rebuild the foundations (milestones 4–6) with more hands-on practice |

---

## Weekly plan template

| Day | Activity (1–2 h) |
|-----|------------------|
| Mon–Wed | Study the milestone files + hands-on exercises |
| Thu | Interview questions for the milestone (out loud) |
| Fri | Practical assessment + readiness score |
| Sat | Review weak areas, flash cards for patterns |
| Sun | Rest, or a mock interview with a peer |
