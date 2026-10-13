# 03.1 — Inventory Shortage, Procurement & MES Sequences (Diagrams 7 and 12)

`Essential`

## Diagram 7 — Inventory shortage and procurement

**Scenario:** An order needs 40 × `VLV-BL-050`, but only 5 are available. Valves are a **buy** item, so a PO goes to supplier `SUP-0042`.

```mermaid
sequenceDiagram
    autonumber
    participant ORD as Order Mgmt Prc
    participant DB as Integration DB
    participant MQ as Anypoint MQ
    participant PROC as Procurement Prc
    participant SAP as SAP Sys API
    participant SUP as Supplier Sys API
    participant HUB as SupplierHub

    ORD->>ORD: availability shows line 20 short by 35
    ORD->>DB: TX - order_state BACKORDERED + outbox inventory.shortage-detected
    ORD-->>ORD: respond 201 (partially reserved)
    DB-->>MQ: outbox relay publishes shortage event
    MQ->>PROC: deliver (procurement-requests queue)
    PROC->>DB: INSERT inbox (eventId) - dedupe
    PROC->>PROC: decide source of supply (info record / quota)
    PROC->>DB: INSERT procurement_request key ORD-123:VLV-BL-050:1000 (UNIQUE)
    PROC->>SAP: POST /purchase-orders (Idempotency ref = key)
    SAP-->>PROC: PO 4500012345
    PROC->>SUP: POST /purchase-orders/4500012345 (Idempotency-Key)
    SUP->>HUB: transmit PO
    HUB-->>SUP: 202 received
    PROC->>DB: TX - request SENT_TO_SUPPLIER + outbox procurement.po-created
    PROC->>MQ: ack message
```

**Explanation**
1–3. The order is **not blocked** by the shortage. It is confirmed with a partial reservation and a backorder flag, because the customer gets a promise date rather than an error.
4–6. The shortage event is delivered at least once, so an **inbox insert** (unique `eventId`) drops exact redeliveries.
7. **Source determination** (which supplier, price, lead time) comes from SAP info records and quota arrangements. It is not hard-coded in Mule.
8. **The business idempotency key** `{orderId}:{material}:{plant}` protects against *different* events about the same shortage. For example, an order is updated and two shortage events fire, so the inbox alone would not catch it.
9–10. The SAP PO is created with the key stored in a PO header text/reference field, so a timeout can be resolved by lookup.
11–13. The PO goes to the supplier with the same idempotency key, which SupplierHub honours.
14–15. State + next event are committed together, *then* the MQ message is acked. If Mule crashes before the ack, the message is redelivered, and steps 6 and 8 make the reprocessing harmless.

**Decision points:** Should shortages be aggregated per material across orders (MRP style) or raised per order? AIM raises per order for MTO/critical items and **lets SAP MRP aggregate** standard items. Mule only creates PRs and SAP converts them to POs. That's a good trade-off to discuss: *don't rebuild MRP in Mule.*

## Diagram 12 — Production planning and MES integration

**Scenario:** The order includes the make-to-order pump `PMP-CF-400-CUSTOM`. A production order must be created and executed on the shop floor.

```mermaid
sequenceDiagram
    autonumber
    participant MQ as Anypoint MQ
    participant PF as Production & Fulfilment Prc
    participant SAP as SAP Sys API
    participant MESS as MES Sys API
    participant MES as ShopFloor MES
    participant HYB as Plant hybrid runtime
    participant WMS as WMS Sys API

    MQ->>PF: order.mto-required (orderId, material, qty, due date)
    PF->>SAP: create production order (BAPI_PRODORD_CREATE)
    SAP-->>PF: prodOrder 1000234
    PF->>SAP: release production order
    PF->>MESS: POST /production-orders (BOM, routing, qty)
    MESS->>MES: download order to the shop floor
    Note over MES,HYB: Hours or days of execution
    MES->>HYB: event operation-confirmed (op 0010, yield 1)
    HYB->>MQ: publish mes.operation-confirmed (buffered if WAN down)
    MES->>HYB: event material-consumed (MTR-7.5KW x1)
    HYB->>MQ: publish mes.material-consumed
    MES->>HYB: event production-completed (qty 1, batch B-7781)
    HYB->>MQ: publish mes.production-completed
    MQ->>PF: deliver completed event
    PF->>PF: dedupe by MES eventId, check sequence per prodOrder
    PF->>SAP: production confirmation + goods receipt FG
    PF->>WMS: create put-away / inbound for FG
    PF->>MQ: publish inventory.fg-available (orderId)
```

**Explanation**
- **Hybrid runtime in the plant (steps 7–12):** MES events are produced locally. If the WAN to the cloud fails, the plant runtime buffers events in a persistent local queue, so production never stops for an IT outage. This is a deliberate decision in [02.5](../02-architecture/05-deployment-architecture.md).
- **Ordering:** The SAP confirmation for operation 0010 should be posted before goods receipt. Events carry `prodOrder` + `sequenceNo`. Consumers process per `prodOrder` in order, using a **FIFO queue with message group = prodOrder**. An event that arrives early is *parked* until the gap fills ([03.2 Diagram 10](02-failure-recovery-sequences.md)).
- **Duplicates (step 15):** MES devices often resend on reconnect, so the consumer dedupes by `eventId` *and* treats goods receipt as idempotent per `(prodOrder, batch)`.
- **Backflushing:** Material consumption can be posted per event or backflushed at completion. That's a business choice which changes the volume (many small events vs one). Ask about it in requirements.

**Failure handling:** If SAP is down, completion events stay in the queue with retry and backoff and the DLQ after N tries. Production continues. SAP catches up later, and inventory reconciliation verifies that no goods receipt was missed.

Next: [03.2 Failure & recovery sequences](02-failure-recovery-sequences.md)
