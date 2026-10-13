# 10.3 — API Manager Policies, Rate Limiting, Spike Control and API Governance

`Essential`

## 1. How policies attach to a Mule app (API autodiscovery)

```xml
<api-gateway:autodiscovery apiId="${api.id}" ignoreBasePath="true" flowRef="order-exp-api-main"
                           doc:name="API Autodiscovery"/>
```
- `api.id` is the **API instance ID** from API Manager. It differs per environment and is passed as a property.
- The runtime needs **platform credentials** (environment client ID/secret, `anypoint.platform.client_id` / `client_secret`) to download policies. On CloudHub these are injected automatically. On hybrid/RTF you configure them.
- **If autodiscovery fails** (wrong ID, bad credentials), the API can **block requests** until policies are fetched (the gateway's "track policies" behaviour). Unexpected 503s right after a deploy often have this cause.
- **Automated policies** apply to every API in an environment (e.g. a baseline header-removal or logging policy).
- **Flex Gateway** applies the same policies to **non-Mule** APIs (e.g. a WMS vendor's REST API you expose through AIM's gateway).

## 2. Policy stack per API (AIM standard)

| API | Policies (order matters: cheapest rejection first) |
|-----|---------------------------------------------------|
| customer-order-exp-api | IP allow-list (Salesforce ranges, optional) → JWT validation (scopes) → Rate limiting SLA-based → Spike control → JSON threat protection → Header injection (`x-correlation-id` if absent) |
| supplier-exp-api | mTLS (ingress) → Client ID enforcement → Rate limiting SLA-based (per supplier tier) → JSON/XML threat protection |
| logistics-tracking-exp-api | IP allow-list per carrier → Client ID (or HMAC in app) → Rate limiting → Spike control |
| Process / System APIs | Client ID enforcement (only approved internal client apps) → Rate limiting (generous, protects against bugs) |

**Custom policies** (built with the policy development kit) are justified for org-wide cross-cutting needs, e.g. HMAC verification for webhook senders or standard correlation-ID injection. Keep them few: each one is a product to maintain.

## 3. Rate limiting and spike control in practice

| Policy | Configuration example | Behaviour |
|--------|----------------------|-----------|
| Rate Limiting | 600 requests / 60 s per client | 429 once exceeded. `X-RateLimit-*` response headers |
| Rate Limiting SLA-based | Tier **Gold** 50 req/s (Salesforce), **Silver** 10 req/s (portal), **Bronze** 2 req/s (small partners) | Limits per client app via its contract tier. Tiers can require approval |
| Spike Control | 20 requests per 1 s, delay up to 500 ms, 2 delayed attempts | Smooths bursts. Rejects when the queue can't absorb them |

**Choosing values:** start from capacity (what SAP and the Process API can handle) and work backwards to per-client shares. Leave headroom for retries. Review monthly against analytics.

**Distributed behaviour:** with multiple replicas, configure clustered/distributed rate limiting where available, or divide the limits per replica. Otherwise four replicas each allow the full quota, giving 4× the intended rate.

## 4. Payload validation and input security

| Threat | Control |
|--------|---------|
| Huge or deeply nested JSON (DoS) | JSON threat protection policy: max depth, string length, array size, entries |
| XML bombs / XXE | XML threat protection policy. DataWeave XML reader with external entities disabled (the default in recent versions; verify) |
| Injection (SQL) | Parameterised DB queries only |
| Injection (SOQL) | Use connector parameters, never string-concatenate user input into SOQL |
| Mass assignment | Explicit mapping in DataWeave (never forward the raw payload to SAP) |
| Over-posting (extra fields) | RAML `additionalProperties: false` where strictness is appropriate (Exp layer for partners) |
| Path traversal in file names (SFTP outputs) | Sanitise names built from input |

## 5. API governance (Anypoint API Governance + process)

```mermaid
flowchart LR
  D[Design RAML/OAS] --> L[Governance ruleset check<br/>in Designer and CI]
  L -->|violations| D
  L --> R[Design review<br/>architect + consumer]
  R --> P[Publish to Exchange]
  P --> C[Conformance dashboard<br/>per business group]
```

**AIM ruleset (examples):**
- Every operation declares 4xx/5xx responses using `ErrorResponse`.
- `baseUri` uses HTTPS. No `http://`.
- Versions follow `v{major}` in the URI.
- Every API has a security scheme and is `securedBy`.
- Exp APIs must declare `x-correlation-id`. POSTs that create resources must declare `Idempotency-Key`.
- Field naming is camelCase. Dates use `date-only`/`datetime` (no strings for dates).

**Process governance:** design review before build, Exchange documentation (purpose, consumers, SLA, contact), deprecation policy, and a quarterly API portfolio review to retire unused APIs (API Manager analytics show zero-traffic APIs).

## 6. Versioning governance (summary)

Full detail: [04.3](../04-api-design/03-error-contract-and-versioning.md). Governance additions:
- A breaking change requires a **design review + consumer sign-off + migration plan**.
- Each **major version is a separate API instance** in API Manager, with its own contracts. You can see exactly who is still on v1.
- Deprecated versions return `Deprecation` and `Sunset` headers (header injection policy).

## Interview angle
**Q: "Where do you implement rate limiting: policy or code?"**
> "Inbound rate limiting belongs in API Manager policies. They're consistent, need no code, can be changed at runtime, and support SLA tiers per client through contracts. In code I implement only *outbound* throttling, where AIM must respect a partner's limits. That's about our consumer concurrency and honouring Retry-After, which a gateway policy on our side can't control."

Next: [10.4 Secrets, PII, audit](04-secrets-pii-audit.md)
