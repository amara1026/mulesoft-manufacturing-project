# 04.4 — API Dependency Matrix

`Essential`

The dependency matrix answers these questions: **"If X is down, what breaks?"**, **"Who must I notify about a change to X?"** and **"Is there a cycle?"** It's used in design reviews, impact analysis, incident triage and release planning.

## 1. Synchronous dependency matrix (caller → callee)

Legend: **S** = sync HTTP call, **E** = consumes events from, **P** = publishes events to, blank = no dependency.

| Caller ↓ / Callee → | order-prc | inventory-prc | procurement-prc | prod-fulfil-prc | shipment-prc | sap-sys | sf-sys | wms-sys | supplier-sys | logistics-sys | mes-sys | MQ | DB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| customer-order-exp | S | | | | | | | | | | | | |
| supplier-exp | | | | | | | | | | | | P | |
| warehouse-ops-exp | | S (GET inv) | | | | | | | | | | P | |
| logistics-tracking-exp | | | | | S (GET tracking) | | | | | | | P | |
| order-prc | — | S | | | | S | S | | | | | P/E | ✔ |
| inventory-prc | | — | | | | S | | S | | | | P | ✔ |
| procurement-prc | | | — | | | S | | | S | | | E/P | ✔ |
| prod-fulfil-prc | | | | — | | S | | S | | | S | E/P | ✔ |
| shipment-prc | | | | | — | S | S | | | S | | E/P | ✔ |

**Cycle check:** sync calls form a DAG: Exp → Order → Inventory → (SAP, WMS). There are **no Process → Process sync cycles**. Order ← Shipment communication (status) happens only through events.

## 2. Event dependency matrix (publisher → event → subscribers)

| Event | Publisher | Subscribers | Queue type | Ordering needed? |
|-------|-----------|-------------|------------|------------------|
| `order.confirmed` | order-prc | status-sync (SF), fulfilment, analytics | Standard (fan-out via exchange) | No |
| `order.backordered` | order-prc | status-sync, analytics | Standard | No |
| `order.erp-pending` | order-prc | erp-retry consumer | Standard, delayed redelivery | No |
| `inventory.shortage-detected` | order-prc | procurement-prc | Standard | No (idempotent key) |
| `order.mto-required` | order-prc | prod-fulfil-prc | Standard | No |
| `supplier.po-confirmation` | supplier-exp | procurement-prc | **FIFO** (group = PO number) | **Yes** |
| `mes.production-event` | plant runtime | prod-fulfil-prc | **FIFO** (group = prodOrder) | **Yes** |
| `warehouse.dispatch-ready` | warehouse-ops-exp | shipment-prc | Standard | No |
| `logistics.tracking-event` | logistics-exp | shipment-prc | Standard + eventTime check | Tolerant |
| `order.invoiced` | shipment-prc | status-sync, analytics | Standard | No |

## 3. Backend dependency and impact table

| Backend down | Directly affected APIs | Business impact | Degraded behaviour (design) |
|--------------|------------------------|-----------------|------------------------------|
| **SAP** | sap-sys → every Prc | Cannot confirm orders, POs or invoices | Orders accepted as `202 PENDING_ERP`. Events queue up. Circuit breaker stops hammering SAP |
| **WMS** | wms-sys → inventory-prc → order-prc | Cannot check or reserve stock | Option A: reject with 503. Option B (business decision): accept and price, with reservation pending. AIM chooses **A for orders < 2 days lead time, B otherwise** |
| **Salesforce** | sf-sys | Customer validation and status sync | Customer validation falls back to the SAP customer master. Status sync queues and catches up |
| **Anypoint MQ** | Outbox relay, all consumers | Async steps paused | Outbox rows accumulate safely in the DB. Relay resumes on recovery. **No data loss** |
| **PostgreSQL** | All Prc APIs | Cannot claim idempotency or persist state | **Fail closed**: order intake returns 503. We must not create SAP orders without durable state |
| **Carrier** | logistics-sys | Cannot book shipments | Retry with backoff, then manual booking via the ops desk |

## 4. Change impact (who to notify)

| If you change… | Notify / regression-test |
|----------------|--------------------------|
| `aim-common-types` fragment | Every API team. It's a platform-wide minor release |
| `sap-sys` contract | order, inventory, procurement, prod-fulfil, shipment |
| `order.confirmed` event schema | status-sync, fulfilment, analytics (data team!) |
| WMS v3 API upgrade | Only wms-sys (that's the point of the System layer) |

> **Interview tip:** When asked "what happens when SAP goes down?", walk through this table row by row. It shows you think in terms of blast radius and degraded modes, not just error handlers.

Next section: [05 — DataWeave](../05-dataweave/01-dataweave-essentials.md)
