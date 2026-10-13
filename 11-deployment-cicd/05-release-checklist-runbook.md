# 11.5 — Release Management, Release Checklist and Deployment Troubleshooting Runbook

`Essential`

## 1. Release management on AIM
- **Release train:** every 2 weeks for API changes. SAP-dependent changes align with SAP transport windows (often monthly in manufacturing).
- **Freeze periods:** quarter-end close (last 5 business days) and plant shutdown cut-overs. Only emergency fixes.
- **Change management:** a CAB-approved change ticket for PROD with the risk assessment, rollback plan, test evidence and communication plan.
- **Feature flags** decouple deploy from release (e.g. `order.asyncFallback.enabled`).

## 2. Release checklist (PROD)

**Before (T-2 days)**
- [ ] Release notes: version, Jira scope, API changes (minor/major), event schema changes
- [ ] MUnit + coverage gates green. SIT regression green. UAT sign-off attached
- [ ] Performance test results reviewed (if the change touches hot paths)
- [ ] Security: secrets scan, dependency scan, new endpoints have policies
- [ ] Config: new properties present in PROD (incl. secure ones), and the API instance ID is correct
- [ ] Dependencies: SAP transports imported? Partner notified? Firewall rules in place?
- [ ] DB migrations are backward compatible (expand phase only)
- [ ] Runbook and alert updates merged
- [ ] Rollback artifact version identified and **tested in QA**
- [ ] Support team briefed (what changed, what to watch)

**During**
- [ ] Announce the start in the ops channel
- [ ] Deploy (rolling). Watch replica readiness
- [ ] Smoke tests (see [09.3](../09-testing/03-performance-and-smoke-testing.md))
- [ ] Watch dashboards for 15–30 min: error rate, latency, DLQ, 202 ratio

**After**
- [ ] Confirm business KPIs (orders flowing, Salesforce statuses updating)
- [ ] Close the change ticket with evidence
- [ ] Hypercare window (e.g. 3 days) for major releases, with named on-call

## 3. Deployment troubleshooting runbook

| Symptom | Likely causes | Checks | Fix |
|---------|---------------|--------|-----|
| App stuck in "Deploying" / restart loop | Startup error: missing property, bad secure key, DB unreachable at init, port conflict | Runtime Manager logs: first `ERROR` at startup | Add the property, correct the `secure.key`, fix connectivity. Avoid connection tests that block startup |
| Deployed but all requests 503 | Autodiscovery can't fetch policies (wrong `api.id`, credentials), or the API is still "unregistered" | Logs for "autodiscovery"/"gateway". API Manager status | Correct the `api.id` / platform credentials |
| 401 for everyone after deploy | JWT policy misconfigured (issuer/audience mismatch for the environment) | Decode a token, compare `iss`/`aud` with the policy | Fix the policy configuration |
| `Connection refused` / `UnknownHost` to SAP/WMS | Firewall/VPN/DNS for a new endpoint | Network diagnostic. Check the VPN tunnel status | Network change request. DNS forwarding |
| `PKIX path building failed` | Missing CA in the truststore (new backend cert) | Inspect the backend's cert chain | Add the CA to the truststore and redeploy |
| Works on 1 replica, fails on another | Replica-local state (in-memory OS, local files) | Compare logs per replica | Use persistent OS/DB. Make the app stateless |
| Performance drop after release | New DW logic, missing index, changed concurrency | Compare dashboards before and after. Per-hop timings | Rollback if SLA breached. Fix forward otherwise |
| MUnit passes, runtime fails on Java 17 | A connector/module isn't Java 17 compatible | Startup logs: class/module errors | Upgrade the connector. Check the compatibility matrix |

## 4. Rollback decision rule
> **Roll back first, diagnose second**, when a PROD release breaches an SLA or creates incorrect business data and the cause isn't obvious within 15 minutes. Have the rollback pre-approved in the change ticket, so nobody needs to wake the CAB at 2 a.m.

## Interview angle
**Q: "Your release went out, smoke tests passed, and 2 hours later supplier POs show wrong quantities. What do you do?"**
> "Stop the bleeding first. Smoke tests don't cover data correctness, so I'd pause the affected consumer, or roll back, to stop more bad POs reaching suppliers. Then assess the scope through the audit logs: which POs were created by the new version, using the version field and correlation IDs. Inform the business and procurement so they can contact suppliers. Fix the root cause with a test that reproduces it, and remediate the data through SAP PO changes with supplier communication. In the postmortem I'd ask why tests didn't catch it, probably a missing UoM test case, and add data-correctness checks to the post-deploy verification."

Next section: [12 — Performance](../12-performance/01-timeouts-retries-pools.md)
