# 06.2 — HTTP Listener/Request, Choice, For Each, Scatter-Gather, Flow Reference

`Essential` · *XML is representative and simplified. The full, runnable version is in the [mini project](../mule-project/aim-order-integration/src/main/mule/).*

## 1. HTTP Listener + APIkit (Experience layer entry point)

```xml
<http:listener-config name="HTTP_Listener_Config" doc:name="HTTPS listener">
    <http:listener-connection host="0.0.0.0" port="${https.port}" protocol="HTTPS">
        <tls:context>
            <tls:key-store type="pkcs12" path="${tls.keystore.path}"
                           keyPassword="${secure::tls.keyPassword}" password="${secure::tls.storePassword}"/>
        </tls:context>
    </http:listener-connection>
</http:listener-config>

<apikit:config name="order-exp-api-config" api="order-exp-api.raml"
               outboundHeadersMapName="outboundHeaders" httpStatusVarName="httpStatus"/>

<flow name="order-exp-api-main">
    <http:listener config-ref="HTTP_Listener_Config" path="/api/*">
        <http:response statusCode="#[vars.httpStatus default 200]">
            <http:headers>#[vars.outboundHeaders default {}]</http:headers>
        </http:response>
        <http:error-response statusCode="#[vars.httpStatus default 500]">
            <http:body>#[payload]</http:body>
            <http:headers>#[vars.outboundHeaders default {}]</http:headers>
        </http:error-response>
    </http:listener>
    <apikit:router config-ref="order-exp-api-config"/>
    <error-handler ref="aim-api-error-handler"/>
</flow>
```

- On CloudHub 2.0, apps listen on `0.0.0.0` with port `${http.port}` (8081) and the platform ingress terminates the public TLS. Use HTTPS on the listener when **last-mile security** is required.
- APIkit routes `POST /orders` to a flow named `post:\orders:application\json:order-exp-api-config`. Studio generates these names. Don't rename them.

## 2. HTTP Request with timeouts and connection pool

```xml
<http:request-config name="HTTP_Request_Order_Prc_Config" doc:name="Order Prc API">
    <http:request-connection host="${prc.order.host}" port="${prc.order.port}" protocol="HTTPS"
                             maxConnections="50" connectionIdleTimeout="30000">
        <tls:context><tls:trust-store path="${tls.truststore.path}" password="${secure::tls.trustPassword}"/></tls:context>
    </http:request-connection>
    <http:default-headers>
        <http:default-header key="client_id" value="${secure::prc.order.clientId}"/>
        <http:default-header key="client_secret" value="${secure::prc.order.clientSecret}"/>
    </http:default-headers>
</http:request-config>

<http:request method="POST" config-ref="HTTP_Request_Order_Prc_Config" path="/prc/order-mgmt/v1/orders"
              responseTimeout="${prc.order.timeoutMs}" doc:name="Call Order Process API">
    <http:headers>#[{
        'x-correlation-id': correlationId,
        'Idempotency-Key': attributes.headers.'idempotency-key'
    }]</http:headers>
    <http:response-validator>
        <http:success-status-code-validator values="200..499"/>
    </http:response-validator>
</http:request>
```

**What each setting does**
- `responseTimeout`: **always set it explicitly** and keep it below the caller's timeout (timeout budget). If you rely on the default, you don't know what you'll get.
- `maxConnections`: caps concurrent outbound connections. It works as a bulkhead, so one slow backend can't absorb unlimited threads.
- **Response validator `200..499`**: this Exp layer **passes 4xx through** (e.g. 422 from the Process API) without raising an error, and only treats 5xx as errors. It's a deliberate pass-through choice. The default validator raises `HTTP:BAD_REQUEST`, `HTTP:NOT_FOUND`, etc.
- `correlationId` is the Mule event's correlation ID. The listener populates it from the inbound `x-correlation-id` header when present.

## 3. Choice router (content-based routing)

```xml
<choice doc:name="Route by stock result">
    <when expression="#[vars.allocation.status == 'FULL']">
        <flow-ref name="reserve-all-lines-subflow" doc:name="Reserve all lines"/>
    </when>
    <when expression="#[vars.allocation.status == 'PARTIAL']">
        <flow-ref name="reserve-partial-subflow" doc:name="Reserve available quantity"/>
        <flow-ref name="register-shortage-subflow" doc:name="Register shortage"/>
    </when>
    <otherwise>
        <flow-ref name="register-shortage-subflow" doc:name="Register shortage (none available)"/>
    </otherwise>
</choice>
```

Conditions are evaluated in order, and the first match wins. Always include `<otherwise>`, even if it only raises an error, because a silent fall-through hides bugs.

## 4. Scatter-Gather (parallel validation)

```xml
<scatter-gather timeout="3000" maxConcurrency="2" doc:name="Validate customer and availability in parallel">
    <route>
        <http:request method="GET" config-ref="HTTP_Request_SF_Sys_Config"
                      path="/sys/crm/v1/accounts/{id}" responseTimeout="2500" doc:name="Get customer">
            <http:uri-params>#[{ id: payload.customerId }]</http:uri-params>
        </http:request>
    </route>
    <route>
        <http:request method="POST" config-ref="HTTP_Request_Inventory_Prc_Config"
                      path="/prc/inventory/v1/availability-checks" responseTimeout="2500" doc:name="Check availability">
            <http:body>#[{ lines: payload.lines map { materialNumber: $.materialNumber, quantity: $.quantity } }]</http:body>
        </http:request>
    </route>
</scatter-gather>
<ee:transform doc:name="Merge results">
    <ee:variables>
        <ee:set-variable variableName="validation"><![CDATA[%dw 2.0
output application/java
---
{ customer: payload."0".payload, availability: payload."1".payload }]]></ee:set-variable>
    </ee:variables>
</ee:transform>
```

**How it behaves**
- Each route receives a **copy** of the event and runs concurrently. The result is an object keyed `"0"`, `"1"`, …, where each entry is a Mule message (`.payload`, `.attributes`).
- If **any** route fails, the whole scatter-gather raises `MULE:COMPOSITE_ROUTING`. The error contains both the successful results and the failures. If a partial result is acceptable, wrap each route in a `try` with `on-error-continue` that returns a fallback.
- `timeout` bounds the total wait. **Route-level** `responseTimeout` values should be lower so you get a meaningful error type instead of a generic timeout.
- Latency ≈ the slowest route, not the sum. Watch out for unpredictable latency when one backend has a long tail (scenario 10 in [13.2](../13-production-troubleshooting/02-scenarios-06-10.md)).

## 5. For Each vs Parallel For Each

```xml
<!-- Sequential: order of processing matters (e.g. SAP posting per line) -->
<foreach collection="#[payload.lines]" doc:name="For each order line">
    <logger level="DEBUG" message="#['Line ' ++ (payload.lineNumber as String)]"/>
</foreach>

<!-- Parallel: independent calls; bounded concurrency to protect the backend -->
<parallel-foreach collection="#[vars.shortageLines]" maxConcurrency="4" timeout="10000"
                  doc:name="Raise procurement request per shortage line">
    <flow-ref name="raise-procurement-request-flow"/>
</parallel-foreach>
```

| | For Each | Parallel For Each |
|-|----------|-------------------|
| Execution | Sequential | Concurrent (bounded by `maxConcurrency`) |
| Payload after scope | **Original** payload is restored | **Array of results** (Mule messages) |
| Variables set inside | Visible after the scope | Not propagated back |
| Error | Stops at the first failing element | Collects errors into `MULE:COMPOSITE_ROUTING` |
| Use for | Ordered processing, small collections | Independent I/O calls |

## 6. Flow Reference, sub-flows and private flows

```xml
<flow name="create-order-flow">
    <flow-ref name="claim-idempotency-subflow" doc:name="Claim idempotency key"/>
    <flow-ref name="validate-order-flow" doc:name="Validate order"/>
    <flow-ref name="create-sap-order-flow" doc:name="Create SAP order"/>
    <flow-ref name="persist-state-and-outbox-subflow" doc:name="Persist state and outbox"/>
</flow>

<sub-flow name="claim-idempotency-subflow">  <!-- no error handler; shares caller's -->
    ...
</sub-flow>

<flow name="create-sap-order-flow">           <!-- private flow: has its own error handler -->
    ...
    <error-handler>
        <on-error-continue type="AIM:SAP_STATUS_UNKNOWN">...</on-error-continue>
    </error-handler>
</flow>
```

- A **sub-flow** runs synchronously in the caller's context. It's cheap, but it has no error handler or processing strategy of its own.
- A **private flow** (no source) can have its own error handler. Use it when a step needs special error semantics.
- Use a **dynamic flow-ref** (`name="#[vars.handlerFlow]"`) sparingly. It defeats static analysis and makes MUnit verification harder.

## 7. Other scopes worth knowing

| Scope | Use in AIM | Caution |
|-------|------------|---------|
| `until-successful maxRetries="2" millisBetweenRetries="500"` | Idempotent GETs (availability, material lookup) | **Never** around non-idempotent creates (SAP order, PO) |
| `async` | Fire-and-forget audit logging | No back-pressure, so it's lost on crash. Prefer MQ for anything important |
| `try` | Local error handling and transaction boundaries | See [06.3](03-error-handling.md) |
| `cache` (EE) | Material master lookups | Needs a key and an invalidation strategy (pattern 28) |

Next: [06.3 Error handling](03-error-handling.md)
