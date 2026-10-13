# 06.3 — Error Handling: Try Scopes, Error Types, Mapping and a Global Strategy

`Essential` — almost every senior interview includes an error-handling question.

## 1. The two handlers, precisely

| | `on-error-propagate` | `on-error-continue` |
|-|----------------------|---------------------|
| After the handler runs | The error is **re-thrown** to the caller (the parent flow or the source) | The flow/scope is treated as **successful**. The handler's result becomes the scope's result |
| HTTP listener response | Error response (`http:error-response`, default 500) | Normal response (`http:response`, default 200) |
| Transactions | **Rolled back** | **Committed** |
| Typical use | Return a proper error to the API client. Let the MQ message be redelivered | Fallback values, "log and skip", converting a known error into a business outcome |

> Common misconception: "on-error-continue means the flow continues after the failing processor." **Wrong.** Execution resumes *after the scope that owns the handler* (the `try` or the whole flow). The processors after the failing one inside that scope are **not** executed.

## 2. Error types and hierarchy

- Every error has a `namespace:identifier`, e.g. `HTTP:TIMEOUT`, `HTTP:CONNECTIVITY`, `DB:QUERY_EXECUTION`, `MULE:COMPOSITE_ROUTING`, `APIKIT:BAD_REQUEST`.
- Many connector errors are children of `MULE:CONNECTIVITY` or `MULE:RETRY_EXHAUSTED`, so a handler for `MULE:CONNECTIVITY` catches `HTTP:CONNECTIVITY` too.
- `ANY` catches everything. Put it **last**.
- **Custom errors**: `<raise-error type="AIM:CUSTOMER_INVALID" description="..."/>`, or **error mapping** on a connector operation:

```xml
<http:request method="POST" config-ref="HTTP_Request_SAP_Sys_Config" path="/sys/sap/v1/sales-orders"
              responseTimeout="6000" doc:name="Create SAP sales order">
    <error-mapping sourceType="HTTP:SERVICE_UNAVAILABLE" targetType="AIM:SAP_UNAVAILABLE"/>
    <error-mapping sourceType="HTTP:CONNECTIVITY"        targetType="AIM:SAP_UNAVAILABLE"/>
</http:request>
```
Error mapping turns *technical* errors into *business-meaningful* ones **at the point where context exists** ("this connectivity error came from SAP"). Downstream handlers can then react precisely.

## 3. Retryable vs non-retryable classification (AIM standard)

| Class | Error types | Sync API behaviour | Async consumer behaviour |
|-------|-------------|-------------------|--------------------------|
| **Transient** | `HTTP:CONNECTIVITY`, `HTTP:TIMEOUT` (on reads), `HTTP:SERVICE_UNAVAILABLE`, `HTTP:TOO_MANY_REQUESTS`, `DB:CONNECTIVITY`, `AIM:SAP_UNAVAILABLE` | 503/504, client retries with the same key | **nack** → redelivery with backoff → DLQ after N |
| **Unknown outcome** | `HTTP:TIMEOUT` on a **create** | Lookup, then 201 or 202 | Lookup-then-create on the next attempt |
| **Business** | `AIM:CUSTOMER_INVALID`, `AIM:SAP_BUSINESS_ERROR`, `APIKIT:BAD_REQUEST` | 400/422 | **Do not retry.** Send to the DLQ immediately or to a business error queue + notify |
| **Bug** | `MULE:EXPRESSION`, `MULE:UNKNOWN`, NPE-like | 500 | DLQ + alert developers |

## 4. Try scope patterns used on AIM

### a) Fallback value (graceful degradation)
```xml
<try doc:name="Get cached-or-live material description">
    <http:request method="GET" config-ref="HTTP_Request_SAP_Sys_Config"
                  path="/sys/sap/v1/materials/{m}" responseTimeout="1500" doc:name="Get material">
        <http:uri-params>#[{ m: vars.materialNumber }]</http:uri-params>
    </http:request>
    <error-handler>
        <on-error-continue type="HTTP:TIMEOUT, HTTP:CONNECTIVITY" logException="false">
            <logger level="WARN" message="#['Material lookup degraded for ' ++ vars.materialNumber]"/>
            <set-payload value='#[{ materialNumber: vars.materialNumber, description: "N/A" }]'/>
        </on-error-continue>
    </error-handler>
</try>
```
Use it only where a fallback is **business-acceptable** (a display description, yes; a price, never).

### b) Unknown outcome → lookup (SAP create)
```xml
<try doc:name="Create SAP order with timeout recovery">
    <http:request method="POST" config-ref="HTTP_Request_SAP_Sys_Config" path="/sys/sap/v1/sales-orders"
                  responseTimeout="6000" doc:name="Create SAP sales order"/>
    <error-handler>
        <on-error-continue type="HTTP:TIMEOUT">
            <flow-ref name="lookup-sap-order-by-reference-flow" doc:name="Lookup by external reference"/>
            <!-- sets vars.erpOutcome = CONFIRMED | UNKNOWN -->
        </on-error-continue>
        <on-error-propagate type="AIM:SAP_BUSINESS_ERROR">
            <flow-ref name="release-reservation-flow" doc:name="Compensate: release reservation"/>
        </on-error-propagate>
    </error-handler>
</try>
```

### c) Transaction boundary
```xml
<try transactionalAction="ALWAYS_BEGIN" doc:name="TX: state + outbox">
    <db:insert config-ref="DB_Config" doc:name="Insert order state">...</db:insert>
    <db:insert config-ref="DB_Config" doc:name="Insert outbox event">...</db:insert>
    <!-- any error here -> on-error-propagate (default) -> ROLLBACK of both inserts -->
</try>
```

## 5. Global error handler → standard contract

```xml
<configuration defaultErrorHandler-ref="aim-api-error-handler" doc:name="Default error handler"/>

<error-handler name="aim-api-error-handler">
    <on-error-propagate type="APIKIT:BAD_REQUEST">
        <set-variable variableName="httpStatus" value="400"/>
        <set-variable variableName="errorCode" value="AIM-ORD-4001"/>
        <flow-ref name="build-error-response-subflow"/>
    </on-error-propagate>
    <on-error-propagate type="APIKIT:NOT_FOUND, APIKIT:METHOD_NOT_ALLOWED, APIKIT:NOT_ACCEPTABLE, APIKIT:UNSUPPORTED_MEDIA_TYPE">
        <set-variable variableName="httpStatus" value="#[
            error.errorType.identifier match {
              case 'NOT_FOUND' -> 404 case 'METHOD_NOT_ALLOWED' -> 405
              case 'NOT_ACCEPTABLE' -> 406 else -> 415 }]"/>
        <set-variable variableName="errorCode" value="AIM-GEN-4000"/>
        <flow-ref name="build-error-response-subflow"/>
    </on-error-propagate>
    <on-error-propagate type="AIM:CUSTOMER_INVALID">
        <set-variable variableName="httpStatus" value="422"/>
        <set-variable variableName="errorCode" value="AIM-ORD-4223"/>
        <flow-ref name="build-error-response-subflow"/>
    </on-error-propagate>
    <on-error-propagate type="AIM:SAP_UNAVAILABLE, HTTP:CONNECTIVITY, HTTP:SERVICE_UNAVAILABLE">
        <set-variable variableName="httpStatus" value="503"/>
        <set-variable variableName="errorCode" value="AIM-DEP-5031"/>
        <flow-ref name="build-error-response-subflow"/>
    </on-error-propagate>
    <on-error-propagate type="ANY">
        <set-variable variableName="httpStatus" value="500"/>
        <set-variable variableName="errorCode" value="AIM-GEN-5001"/>
        <flow-ref name="build-error-response-subflow"/>
    </on-error-propagate>
</error-handler>

<sub-flow name="build-error-response-subflow">
    <logger level="ERROR" category="aim.errors"
            message="#[output application/json --- { correlationId: correlationId, code: vars.errorCode, type: error.errorType.namespace ++ ':' ++ error.errorType.identifier, description: error.description }]"/>
    <ee:transform doc:name="Standard error body">
        <ee:message><ee:set-payload><![CDATA[%dw 2.0
output application/json
---
{ error: {
    code: vars.errorCode,
    message: if ((vars.httpStatus as Number) >= 500) "An internal error occurred" else error.description,
    correlationId: correlationId,
    timestamp: now()
} }]]></ee:set-payload></ee:message>
    </ee:transform>
</sub-flow>
```

**Design notes**
- **Hide internals on 5xx.** The client sees a generic message plus the correlation ID, and the details go to the logs.
- **Order matters:** the first matching `on-error-*` wins, so specific types go first and `ANY` goes last.
- A flow's own `<error-handler>` overrides the default. The default applies only to flows without one.
- `when` expressions allow conditional handlers, e.g. `<on-error-propagate when="#[error.errorMessage.attributes.statusCode == 409]">`.

## 6. Error handling in message consumers
- **Retryable:** let the error propagate. With Anypoint MQ `MANUAL` ack, call `nack` (or let the ack timeout expire) so the broker redelivers. After `maxDeliveries` the message goes to the DLQ.
- **Non-retryable:** `on-error-continue` → publish to the DLQ/business-error queue with error metadata → `ack` the original. Retrying a 400 forever is a classic poison-message loop.
- **Always log** the message ID, delivery count and correlation ID. Without them, DLQ triage is guesswork.

## Interview angle
**Q: "A Salesforce callout to your API timed out, but the order was created. The rep clicked Submit again. What happens?"**
> "The second request carries the same Idempotency-Key, the Salesforce Order Id. The Process API's idempotency claim finds the key COMPLETED with the same request hash, so it returns the stored 201 response with the same SAP order number. No second SAP call is made. If the first request were still running, the second would get a 409 telling the client to retry later. And if the key were reused with a different payload, a 422. That's three outcomes, all deterministic."

Next: [06.4 Database & Object Store](04-database-and-object-store.md)
