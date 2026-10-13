# 15.2 — Code Reviews, Mentoring and Technical Debt

`Essential`

## 1. MuleSoft code review checklist (AIM)

**Structure & readability**
- [ ] Flows are small and named by business action. Global configs live in `global.xml`
- [ ] `doc:name`s are unique and meaningful (MUnit mocks rely on them)
- [ ] No duplicated logic. Shared DW lives in modules. Common error handler used
- [ ] No hard-coded hosts, ports, credentials or IDs. Everything is in properties

**Correctness & reliability**
- [ ] Every outbound call has an explicit `responseTimeout`
- [ ] Retries only on transient errors and idempotent operations. Bounded, with backoff
- [ ] Creates are idempotent (key / business reference / lookup)
- [ ] No outbound HTTP inside DB transactions
- [ ] Error handlers: specific types first, `ANY` last. Correct propagate vs continue
- [ ] Consumers: ack/nack on every path. DLQ for non-retryable errors
- [ ] For Each vs Parallel For Each choice justified. Concurrency bounded

**DataWeave**
- [ ] Null-safe (`default`, `?`). Explicit coercions with formats
- [ ] No O(n²) lookups on large inputs. No full-load operations on streams
- [ ] Money as decimal strings. Dates with explicit formats and zones
- [ ] Mapping matches the signed-off mapping spec (defaults documented)

**Security**
- [ ] No secrets in code or config files (secure properties / vault)
- [ ] No PII or tokens in logs at INFO. Masking applied
- [ ] Parameterised SQL. No string-built queries
- [ ] TLS without `insecure="true"`

**Operability**
- [ ] Structured logs with correlationId and business IDs at key points
- [ ] Metrics/alerts and runbook updated for new failure modes
- [ ] Health endpoint unaffected or extended

**Tests**
- [ ] MUnit covers the happy path **and** the negative paths (timeouts, business errors, duplicates)
- [ ] Assertions check business values, not just "not null"
- [ ] Golden-file tests for mappings

## 2. Giving review feedback well

| Instead of | Say |
|------------|-----|
| "This is wrong." | "If SAP times out here, `until-successful` will retry the create. Could that duplicate the order? What do you think about a lookup by reference instead?" |
| "Use a scatter-gather." | "These two calls are independent. Running them in parallel could save about 600 ms. Want to try it and measure?" |
| 40 nitpicks | Label them: **[blocker]**, **[suggestion]**, **[nit]**. Automate formatting and lint rules |

Review the **design intent** first (does it solve the right problem safely?), then the code details.

## 3. Mentoring junior developers (practical approach)

| Practice | Example |
|----------|---------|
| Pairing on the first story in a new area | Pair on the first SAP BAPI integration: commit/LUW, ALPHA conversion, RETURN table |
| "Failure-first" design exercises | Before coding, the junior writes a failure table: what if SAP times out, WMS is down, the message is duplicated? |
| Reusable templates | Project template with global config, error handler, logging, MUnit skeleton |
| Brown-bag sessions | 30-minute sessions: "Idempotency in Mule", "Reading thread dumps", "DW performance" |
| Gradual ownership | Junior → owns a System API → co-owns a Process API → runs an incident review |
| Feedback loops | Weekly 1:1 code walkthroughs. Celebrate good tests |

## 4. Technical debt management

**Make debt visible:** a debt register in the backlog. Each item has impact, risk, effort and an owner.

| Debt item (AIM example) | Impact | Risk | Plan |
|-------------------------|--------|------|------|
| Tolerant date mapping hot-fix in order-exp-api (scenario 17) | Low | Masks schema drift | Remove after Salesforce field revert. Sprint 14 |
| Supplier-sys-api on mule-maven-plugin 3.x | Medium | Can't use new deploy features | Upgrade with the parent POM. Sprint 15 |
| Object Store dedupe in tracking consumer | Low | Restarts can cause duplicate status events | Accepted (natural idempotency). Documented |
| No contract tests for MES events | High | Silent plant data issues | Next PI |

**Negotiating time:** tie debt to business risk ("the 4.6 LTS standard support ended Aug 2026, so we risk unpatched vulnerabilities"). Reserve ~15–20% of capacity, and pay down debt **in the area you're already changing** (the boy-scout rule).

## Interview angle
**Q: "A junior's PR works, but it uses until-successful around an SAP create. How do you handle it?"**
> "I'd treat it as a teaching moment, not just a rejection. I'd mark it as a blocker in the review with a question about what happens when SAP commits but the response times out, then pair with them for 20 minutes to walk through the duplicate-order scenario and the lookup-by-reference pattern. Then I'd check whether our project template or guidelines could have prevented it, for example a lint rule or a documented 'creates are never retried' standard, so the next developer doesn't make the same mistake."

Next: [15.3 Difficult project situations](03-difficult-situations.md)
