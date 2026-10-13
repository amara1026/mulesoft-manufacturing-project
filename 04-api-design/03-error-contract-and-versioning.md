# 04.3 — Standard Error Contract, Error Catalogue & API Versioning

`Essential`

## 1. One error contract for every API

```json
{
  "error": {
    "code": "AIM-SAP-4225",
    "message": "SAP rejected the sales order",
    "correlationId": "c0a8012e-7f3a-4b1e-9e55-1c2d3e4f5a6b",
    "timestamp": "2026-10-13T08:02:02.341Z",
    "details": [
      { "field": "customerId", "issue": "V1 154: Customer CUST-100234 blocked for sales (credit)" }
    ]
  }
}
```

**Rules**
- `code` is **stable and documented**. Consumers branch on the code, never on the message text.
- `message` is human readable, contains **no stack traces, SQL or internal hostnames**, and no PII.
- `correlationId` is always present, so support can find the logs in one search.
- Downstream errors are **translated**, never passed through raw. A raw SAP message can leak internals, and consumers shouldn't depend on SAP wording.

## 2. HTTP status semantics (how consumers should react)

| Status | Meaning on AIM | Should the client retry? |
|--------|----------------|--------------------------|
| 400 | Malformed request / schema violation | No, fix the request |
| 401 / 403 | Auth failure / missing scope | No, fix the credentials |
| 404 | Resource not found | No |
| 409 | Same idempotency key still in progress | **Yes, after a delay, with the same key** |
| 422 | Valid request, business rule failed | No, a business fix is needed |
| 429 | Rate limited | **Yes**, honour `Retry-After` |
| 500 | Unexpected bug | Maybe once. Raise an incident |
| 502 | A downstream system returned an error | Yes with backoff (same key) |
| 503 | Dependency unavailable / circuit open | Yes with backoff (same key) |
| 504 | Timeout, **outcome unknown** | Yes, **only with the same Idempotency-Key** |

## 3. Error-code catalogue (excerpt)

Format: `AIM-{DOMAIN}-{HTTP}{seq}`

| Code | HTTP | Domain | Meaning | Mule error type source | Retryable | Ops action |
|------|------|--------|---------|------------------------|-----------|------------|
| AIM-ORD-4001 | 400 | Order | Request schema invalid | `APIKIT:BAD_REQUEST` | No | None |
| AIM-ORD-4091 | 409 | Order | Duplicate request in progress | `AIM:DUPLICATE_IN_PROGRESS` | Yes (delay) | None |
| AIM-ORD-4221 | 422 | Order | Idempotency key reused with a different payload | `AIM:IDEMPOTENCY_KEY_REUSED` | No | Inform the consumer team |
| AIM-ORD-4223 | 422 | Order | Customer blocked / inactive | `AIM:CUSTOMER_INVALID` | No | Business (credit team) |
| AIM-ORD-4224 | 422 | Order | Unknown material / UoM | `AIM:MATERIAL_INVALID` | No | Master data team |
| AIM-SAP-4225 | 422 | SAP | BAPI returned TYPE E/A | `AIM:SAP_BUSINESS_ERROR` | No | Depends on the SAP message |
| AIM-SAP-5031 | 503 | SAP | SAP unreachable (RFC comm failure) | `SAP:CONNECTIVITY`, `HTTP:CONNECTIVITY` | Yes | Check VPN/SAP gateway |
| AIM-SAP-5041 | 504 | SAP | Timeout, outcome unknown after lookup | `HTTP:TIMEOUT` + lookup miss | Yes (same key) | Monitor PENDING_ERP count |
| AIM-INV-5031 | 503 | Inventory | WMS unavailable | `HTTP:CONNECTIVITY`, `HTTP:SERVICE_UNAVAILABLE` | Yes | WMS vendor |
| AIM-SUP-4291 | 429 | Supplier | Supplier API rate limit | `HTTP:TOO_MANY_REQUESTS` | Yes (Retry-After) | Tune throttling |
| AIM-DEP-5021 | 502 | Generic | Unexpected downstream error | `HTTP:*` other | Yes | Investigate |
| AIM-GEN-5001 | 500 | Generic | Unhandled error | `ANY` | Maybe | Incident |

The full catalogue lives in [16.2](../16-project-documents/02-api-and-data-specs.md). The mini project implements this mapping in `common-error-handler.xml`.

## 4. API versioning and backward compatibility

### What counts as breaking?

| Change | Breaking? | Version impact |
|--------|-----------|----------------|
| Add an optional request field | No | Minor (1.1.0) |
| Add a response field | No* | Minor. *Consumers must be tolerant readers |
| Add a new enum value in a **response** | **Potentially** | Treat as breaking unless consumers are known to tolerate it |
| Make an optional field required | Yes | Major (v2) |
| Rename or remove a field | Yes | Major |
| Change type or format (string → number, date format) | Yes | Major |
| Change error codes or semantics | Yes | Major |
| Tighten validation (maxLength 80 → 40) | Yes | Major |

### Strategy on AIM
1. **URI major version** (`/api/v1`, `/api/v2`). It's visible, cache-friendly and easy to route at the gateway.
2. **Minor/patch versions** live only in Exchange (asset versions). They don't appear in the URI.
3. **Parallel run:** when v2 ships, v1 stays live for a **deprecation window** (e.g. 6 months), and v1 responses get a `Deprecation` / `Sunset` header.
4. **v1 is implemented as an adapter over v2** where possible: one implementation and a thin mapping layer, which avoids duplicated logic.
5. **Track consumers** through API Manager contracts (client apps). Before retiring v1, check that traffic per client is zero.
6. **Tolerant reader** rule for our own consumers: ignore unknown fields and don't fail on new optional data.

### Real scenario
> SAP's upgrade changes `sapOrderNumber` from 10 digits with leading zeros to a 12-character alphanumeric. **Only the SAP System API changes:** it keeps returning a string with the same field name. Consumers are unaffected because the canonical contract said `string`, not `pattern: ^[0-9]{10}$`. *That is the payoff of API-led.*

## Interview angle

**Q: "How do you introduce a breaking change to an API with 5 consumers?"**
> "First I check whether it really has to break, because most changes can be additive. If it does, I publish v2 in Exchange with a migration guide and deploy it alongside v1. Where possible I implement v1 as a mapping onto v2's logic so there's one code path. I announce the deprecation with a Sunset date, and API Manager analytics show me who is still on v1. I work with each consumer team on a migration slot, and I retire v1 only when its traffic is zero. That's agreed with the consumers, not imposed."

Next: [04.4 API dependency matrix](04-api-dependency-matrix.md)
