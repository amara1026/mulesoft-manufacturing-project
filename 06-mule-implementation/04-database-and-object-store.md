# 06.4 — Database Connector & Object Store

`Essential`

## 1. Integration database schema (PostgreSQL)

```sql
CREATE TABLE idempotency_record (
  idempotency_key  VARCHAR(64)  PRIMARY KEY,
  request_hash     VARCHAR(64)  NOT NULL,
  status           VARCHAR(20)  NOT NULL,          -- IN_PROGRESS | COMPLETED
  http_status      INT,
  response_body    TEXT,
  created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_state (
  order_id          VARCHAR(40) PRIMARY KEY,
  external_order_id VARCHAR(40) NOT NULL UNIQUE,
  customer_id       VARCHAR(20) NOT NULL,
  status            VARCHAR(30) NOT NULL,
  sap_order_number  VARCHAR(20),
  reservation_id    VARCHAR(40),
  version           INT         NOT NULL DEFAULT 0,  -- optimistic locking
  payload_json      TEXT,
  created_at        TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE outbox_event (
  event_id      VARCHAR(64) PRIMARY KEY,
  aggregate_id  VARCHAR(40) NOT NULL,
  event_type    VARCHAR(60) NOT NULL,
  payload       TEXT        NOT NULL,
  status        VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING | PUBLISHED | FAILED
  attempts      INT         NOT NULL DEFAULT 0,
  created_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_at  TIMESTAMP
);
CREATE INDEX ix_outbox_pending ON outbox_event (status, created_at);

CREATE TABLE inbox_event (
  event_id     VARCHAR(64) NOT NULL,
  consumer     VARCHAR(60) NOT NULL,
  processed_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id, consumer)
);
```

## 2. Configuration with a sized pool

```xml
<db:config name="DB_Config" doc:name="Integration DB">
    <db:generic-connection url="${db.url}" driverClassName="org.postgresql.Driver"
                           user="${db.user}" password="${secure::db.password}">
        <db:pooling-profile maxPoolSize="${db.maxPool}" minPoolSize="2"
                            maxWait="${db.maxWaitMs}" maxWaitUnit="MILLISECONDS"/>
    </db:generic-connection>
</db:config>
```
(The DB connector has dedicated connection providers for MySQL, Oracle, SQL Server and Derby. PostgreSQL uses `generic-connection`. Add the JDBC driver as a Maven dependency **and** as a `sharedLibrary` in the mule-maven-plugin config.)

**Pool sizing:** `replicas × maxPoolSize` must stay below the database's `max_connections`, after subtracting what other apps use. 4 replicas × 20 = 80 connections. Agree the number with the DBA. Set `maxWait` so that pool exhaustion **fails fast** (e.g. 3 s) instead of hanging threads until the HTTP timeout.

## 3. Operations with parameter binding (never string concatenation)

```xml
<!-- Insert (claim idempotency key) -->
<db:insert config-ref="DB_Config" doc:name="Claim idempotency key">
    <db:sql><![CDATA[INSERT INTO idempotency_record (idempotency_key, request_hash, status)
                     VALUES (:key, :hash, 'IN_PROGRESS')]]></db:sql>
    <db:input-parameters><![CDATA[#[{ key: vars.idempotencyKey, hash: vars.requestHash }]]]></db:input-parameters>
</db:insert>

<!-- Select -->
<db:select config-ref="DB_Config" doc:name="Get order state">
    <db:sql><![CDATA[SELECT order_id, status, sap_order_number FROM order_state WHERE order_id = :id]]></db:sql>
    <db:input-parameters><![CDATA[#[{ id: attributes.uriParams.orderId }]]]></db:input-parameters>
</db:select>

<!-- Conditional update (state machine + optimistic lock) -->
<db:update config-ref="DB_Config" doc:name="Transition order status">
    <db:sql><![CDATA[UPDATE order_state
       SET status = :newStatus, version = version + 1, updated_at = CURRENT_TIMESTAMP
     WHERE order_id = :id AND version = :expectedVersion AND status IN ('CONFIRMED','BACKORDERED')]]></db:sql>
    <db:input-parameters><![CDATA[#[{ id: vars.orderId, newStatus: 'RELEASED_TO_WAREHOUSE', expectedVersion: vars.version }]]]></db:input-parameters>
</db:update>
<choice>
    <when expression="#[payload.affectedRows == 0]">
        <raise-error type="AIM:CONCURRENT_UPDATE" description="Order changed concurrently or invalid transition"/>
    </when>
</choice>

<!-- Bulk insert (reconciliation results) -->
<db:bulk-insert config-ref="DB_Config" doc:name="Bulk insert recon rows">
    <db:sql><![CDATA[INSERT INTO recon_result (run_id, material, wms_qty, sap_qty, diff)
                     VALUES (:runId, :material, :wmsQty, :sapQty, :diff)]]></db:sql>
</db:bulk-insert>
```

**Parameterised queries** prevent SQL injection and let the DB reuse execution plans. A dynamic `#["SELECT ... WHERE id = '" ++ vars.id ++ "'"]` should never pass code review.

**Large result sets:** `db:select` streams results by default (a repeatable iterable). Set `fetchSize` and `maxRows` for big reconciliation queries so 1M rows aren't loaded at once.

## 4. Transactions

```xml
<try transactionalAction="ALWAYS_BEGIN" transactionType="LOCAL" doc:name="TX: order state + outbox">
    <db:insert config-ref="DB_Config" doc:name="Insert order state">...</db:insert>
    <db:insert config-ref="DB_Config" doc:name="Insert outbox event">...</db:insert>
    <db:update config-ref="DB_Config" doc:name="Complete idempotency record">...</db:update>
</try>
```

- **Local transaction:** all operations on the **same** `DB_Config` join automatically (`transactionalAction` defaults to `JOIN_IF_POSSIBLE`).
- An HTTP call inside the try is **not** part of the transaction. If it succeeds and the DB later rolls back, the HTTP side effect remains. That's why HTTP calls happen *before* the transaction and the event goes in the outbox.
- **XA** (`transactionType="XA"`) can span JMS + DB (or VM + DB) with XA-capable drivers, but it's slow, operationally heavy and **not available for HTTP, SAP RFC or Anypoint MQ**. AIM uses the outbox instead (see [08.3](../08-reliability-transactions/03-outbox-inbox-saga.md)).

## 5. Object Store — when (and when not) to use it

```xml
<os:object-store name="Token_Cache_OS" persistent="true" entryTtl="55" entryTtlUnit="MINUTES"
                 maxEntries="1000" doc:name="OAuth token cache"/>

<os:retrieve key="supplierhub-token" objectStore="Token_Cache_OS" target="cachedToken" doc:name="Get cached token">
    <os:default-value>#[null]</os:default-value>
</os:retrieve>
<choice>
    <when expression="#[vars.cachedToken == null]">
        <flow-ref name="fetch-supplierhub-token-flow"/>
        <os:store key="supplierhub-token" objectStore="Token_Cache_OS" doc:name="Cache token">
            <os:value>#[payload.access_token]</os:value>
        </os:store>
    </when>
</choice>
```

| Use Object Store for | Use the DB for |
|----------------------|----------------|
| OAuth token caching | Idempotency of orders, POs and invoices |
| Small lookup caches with TTL | Integration state, outbox/inbox |
| Watermarks for simple pollers (last sync timestamp) | Anything needing audit, queries, joins, retention |
| The built-in **Idempotent Message Validator** for low-stakes dedupe | Anything that must be atomic with other state |

**Object Store v2 on CloudHub** is a shared, persistent, region-scoped key-value store. Entries have a TTL (OSv2 has a default max TTL, check current limits) and there are API rate limits. It's not designed as a high-throughput database. **On CloudHub 2.0 replicas**, use a persistent OS so all replicas share it. An in-memory OS is per replica.

## 6. Idempotent Message Validator (quick dedupe)

```xml
<idempotent-message-validator idExpression="#[attributes.properties.messageId default payload.eventId]"
                              objectStore="Dedupe_OS" doc:name="Drop duplicate tracking events"/>
```
It raises `MULE:DUPLICATE_MESSAGE` for repeated IDs. It's good for **low-stakes** streams such as carrier tracking events. It's not enough for PO creation, because the check and the side effect aren't atomic: a crash between them leaves the ID stored but the work undone.

Next: [06.5 SAP & Salesforce connectors](05-sap-salesforce-connectors.md)
