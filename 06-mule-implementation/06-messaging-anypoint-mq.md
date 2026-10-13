# 06.6 — Messaging: Anypoint MQ, VM Queues and Kafka

`Essential`

## 1. Anypoint MQ concepts in one table

| Concept | Meaning | AIM usage |
|---------|---------|-----------|
| **Queue** | Point-to-point. Each message is consumed by one consumer | `prod-procurement-requests-q` |
| **Message exchange** | Pub/sub. A message published to an exchange is copied to every **bound** queue | `prod-order-events-x` → status-sync, fulfilment, analytics queues |
| **Standard queue** | High throughput, best-effort ordering, at-least-once | Most events |
| **FIFO queue** | Strict ordering. **Message groups** allow parallelism across groups (up to 10 in-flight messages per group) | Supplier confirmations per PO, MES events per production order |
| **DLQ** | A queue receiving messages that exceeded **max deliveries** | One DLQ per business queue |
| **Ack timeout / lock** | An in-flight message is invisible to other consumers until acked or the timeout expires | Set it higher than the p99 processing time |
| **TTL** | A message expires if not consumed | 7 days (assumption) for most queues |
| **Max message size** | 10 MB | Send references (IDs, URLs) for large documents, not the documents |
| **Delivery delay** | A message becomes visible after a delay | Simple retry backoff for `order.erp-pending` |

## 2. Configuration, publish and subscribe (representative XML)

```xml
<anypoint-mq:config name="MQ_Config" doc:name="Anypoint MQ">
    <anypoint-mq:connection url="${mq.url}" clientId="${secure::mq.clientId}" clientSecret="${secure::mq.clientSecret}"/>
</anypoint-mq:config>

<!-- Publish (from the outbox relay) -->
<anypoint-mq:publish config-ref="MQ_Config" destination="${mq.x.orderEvents}"
                     messageId="#[vars.event.event_id]" doc:name="Publish order event">
    <anypoint-mq:body>#[vars.event.payload]</anypoint-mq:body>
    <anypoint-mq:properties>#[{
        eventType: vars.event.event_type,
        correlationId: vars.event.correlation_id,
        schemaVersion: "1.0"
    }]</anypoint-mq:properties>
</anypoint-mq:publish>

<!-- Subscribe with MANUAL acknowledgement -->
<flow name="status-sync-consumer-flow" maxConcurrency="4">
    <anypoint-mq:subscriber config-ref="MQ_Config" destination="${mq.q.statusSync}"
                            acknowledgementMode="MANUAL" doc:name="Order status sync queue"/>
    <flow-ref name="inbox-dedupe-subflow" doc:name="Skip if already processed"/>
    <flow-ref name="upsert-salesforce-status-flow" doc:name="Upsert status in Salesforce"/>
    <anypoint-mq:ack ackToken="#[attributes.ackToken]" doc:name="Ack"/>
    <error-handler>
        <on-error-continue type="AIM:NON_RETRYABLE, APIKIT:BAD_REQUEST, MULE:EXPRESSION">
            <flow-ref name="publish-to-dlq-with-metadata-subflow"/>
            <anypoint-mq:ack ackToken="#[attributes.ackToken]"/>
        </on-error-continue>
        <on-error-continue type="ANY">
            <!-- retryable: return to queue; broker counts deliveries and moves to DLQ after max -->
            <anypoint-mq:nack ackToken="#[attributes.ackToken]"/>
        </on-error-continue>
    </error-handler>
</flow>
```

### Acknowledgement modes
| Mode | Behaviour | Risk |
|------|-----------|------|
| `IMMEDIATE` | Acked on receipt | **Message lost** if processing fails. Avoid for business events |
| `AUTO` | Acked when the flow completes successfully, nacked on error | Simple and good for most flows |
| `MANUAL` | You call `ack`/`nack` | Most control (e.g. ack after the DB commit). You must handle every path, or the message is redelivered only after the ack timeout |

**Concurrency:** `maxConcurrency` on the flow (and the subscriber's prefetch settings) control how many messages are processed in parallel. Higher concurrency means higher throughput, but more load on SAP. Size it against the downstream capacity, not the CPU.

**Ordering trap:** with concurrency > 1 on a *standard* queue, messages are processed out of order. If order matters, use a FIFO queue with message groups, or design consumers to be order-tolerant (version checks).

## 3. VM connector: in-app (or cluster) queues

```xml
<vm:config name="VM_Config">
    <vm:queues>
        <vm:queue queueName="order-events" queueType="PERSISTENT"/>
    </vm:queues>
</vm:config>
<vm:publish config-ref="VM_Config" queueName="order-events" doc:name="Hand off internally"/>
<vm:listener config-ref="VM_Config" queueName="order-events" numberOfConsumers="4"/>
```
- **Use VM for** decoupling flows *within one application*, and for local development stand-ins (the mini project uses VM in place of Anypoint MQ).
- **Not for** cross-application integration or durable business events in CloudHub 2.0. Replicas don't share VM queues unless clustering is enabled, and messages are tied to the app's lifecycle.

## 4. Anypoint MQ vs Kafka (a common senior question)

| Criterion | Anypoint MQ | Apache Kafka (Confluent / MSK) |
|-----------|-------------|--------------------------------|
| Model | Queues + exchanges. Messages are deleted after ack | Partitioned **log**. Consumers track offsets. Messages are retained by time/size |
| Replay | Only via DLQ / re-publish | **Native**: reset the consumer offset |
| Ordering | FIFO queues / message groups | Per partition (key = orderId) |
| Throughput | Moderate (good for business events) | Very high (100k+ msg/s) |
| Operations | Fully managed in Anypoint, simple | Managed services exist, but more concepts (partitions, rebalancing, schemas) |
| Mule support | Anypoint MQ connector | Apache Kafka connector (consumer/producer, message listener, commit control) |
| Best fit for AIM | Order/procurement/shipment events | High-volume IoT/MES telemetry, an analytics event stream, CDC |

**AIM's answer:** Anypoint MQ for transactional business events. If the plants later stream machine telemetry (thousands of msgs/s) or analytics needs replayable history, **add Kafka for that domain**. Don't force one broker onto every use case.

## 5. Message design rules
- **An event is a fact in the past tense:** `order.confirmed`, not `confirmOrder`.
- **Envelope** with `eventId` (UUID), `eventType`, `occurredAt`, `correlationId`, `schemaVersion`, `source`, and `data`.
- **Thin vs fat events:** thin (IDs only) means consumers call back to get data, which is more coupling and load. Fat (full state) means bigger messages and a schema to version. AIM sends **enough data for the common consumers**, with IDs for the rest.
- **Schema evolution:** additive changes only within a major version. Consumers ignore unknown fields.

```json
{
  "eventId": "6f1c2a5e-0d7b-4b7e-9a51-2f8f1f3c9b10",
  "eventType": "order.confirmed",
  "schemaVersion": "1.0",
  "occurredAt": "2026-10-13T08:02:02.512Z",
  "source": "order-mgmt-prc-api",
  "correlationId": "c0a8012e-7f3a-4b1e-9e55-1c2d3e4f5a6b",
  "data": { "orderId": "AIM-20261013-7F3A9C21", "externalOrderId": "SF-00012345", "sapOrderNumber": "0000456789", "status": "CONFIRMED" }
}
```

Next: [06.7 Scheduler, Batch Job & SFTP](07-scheduler-batch-sftp.md)
