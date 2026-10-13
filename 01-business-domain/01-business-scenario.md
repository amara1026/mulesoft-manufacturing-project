# 01.1 — Business Scenario: Apex Industrial Manufacturing (AIM)

`Essential` · *Simulated company. All figures are assumptions.*

## 1. Who is AIM?

AIM is a fictional global manufacturer of **industrial centrifugal pumps, ball valves and spare parts**. It sells B2B to oil & gas, water utilities and chemical plants.

| Dimension | Value (assumption) |
|-----------|--------------------|
| Plants | Houston, US (plant `1000`), Pune, India (`2000`), Stuttgart, Germany (`3000`) |
| Distribution centres | `DC-US-01`, `DC-IN-01`, `DC-EU-01` |
| Customers | ~4,000 active B2B accounts |
| Suppliers | ~600 (motors, castings, seals, electronics) |
| Orders | ~15,000 sales orders/day, rising to ~45,000 at quarter-end |
| Order size | 1–200 lines, averaging 8 |
| Products | Finished goods (FG), e.g. `PMP-CF-200` (centrifugal pump); components (RM), e.g. `MTR-7.5KW` (motor), `CSG-SS-200` (casing), `SEAL-MECH-40` |

**Make-to-stock vs make-to-order.** Popular pumps are kept in stock. Large or custom pumps are produced when ordered. That is why one customer order can trigger **production** (MES) and **procurement** (suppliers).

## 2. The business problem (why the integration program exists)

Today AIM runs on point-to-point scripts, nightly CSV dumps and manual re-keying. That causes these problems:

| Pain point | Real-world effect |
|------------|-------------------|
| Sales reps enter orders twice, once in Salesforce and once in SAP | Typing errors, an order lead time of 4–6 hours, and wrong prices |
| Inventory in the WMS and SAP is synced only overnight | Sales promise stock that was shipped hours ago, so orders are oversold |
| Shortages are emailed to buyers manually | Purchase orders are created late or **twice**, so cash gets stuck in excess stock |
| Supplier confirmations arrive by email or PDF | No visibility of inbound supply |
| Carrier tracking is checked on carrier websites | Customer service cannot answer "where is my pump?" |
| No end-to-end ID | An incident takes days to trace across 6 systems |

**Program goal:** a reusable integration platform on MuleSoft. Orders should flow from capture to cash with no re-keying, inventory should be visible in near real time, procurement should be automated and duplicate-safe, and the whole flow should be auditable.

## 3. Systems in scope

| # | System | Role | Integration style | Simulated in the project as |
|---|--------|------|-------------------|-----------------------------|
| 1 | **SAP S/4HANA** | ERP: sales orders, purchase orders, material master, ATP, production orders, invoices | SAP Connector (BAPI/RFC, IDoc) or OData APIs | Mock HTTP endpoints that return BAPI-shaped XML |
| 2 | **Salesforce Sales Cloud** | Accounts, opportunities, customer orders, order status shown to reps | Salesforce Connector (REST/Bulk/Streaming, Platform Events) | Mock CRM endpoints |
| 3 | **WMS** ("StockPoint WMS") | Stock by bin, reservations, picking, packing, dispatch | REST + webhooks | Mock endpoints |
| 4 | **Supplier Management** ("SupplierHub") | Supplier onboarding, PO transmission, confirmations, ASNs | REST for large suppliers, SFTP CSV for small ones | Mock endpoint + sample CSV |
| 5 | **TMS / carriers** ("FreightLink") | Shipment booking, labels, tracking, proof of delivery | REST + webhook callbacks | Documented design |
| 6 | **PostgreSQL** (integration DB) | Idempotency keys, order integration state, outbox/inbox, audit, reconciliation | Database Connector | **H2 in PostgreSQL mode** (embedded) |
| 7 | **Anypoint MQ** | Asynchronous events, decoupling, load levelling, DLQs | Anypoint MQ Connector | **VM Connector** (local stand-in) |
| 8 | **SFTP** | Nightly bulk inventory snapshots, small-supplier files | SFTP Connector + Batch Job | Documented design |
| 9 | **MES** ("ShopFloor MES") | Production order execution, material consumption, completion events | MQ events + REST | Documented design |
| 10 | **Analytics platform** (e.g. a cloud data warehouse) | Operational dashboards, OTIF, inventory visibility, reconciliation reports | Event subscription + batch extracts | Documented design |

> **Interview tip:** Say clearly which parts you built against real connectors and which you mocked. Interviewers respect "I mocked SAP with BAPI-shaped XML because I had no SAP sandbox, but this is exactly how the SAP connector payload is structured." They do not respect vague claims.

## 4. Key business entities and their system of record (SoR)

The **system of record** is the system that *owns the truth* for an entity. MuleSoft never becomes the SoR. It moves and coordinates data, and it owns only *integration state* such as idempotency keys and outbox rows.

| Entity | System of record | Others hold copies | Notes |
|--------|------------------|--------------------|-------|
| Customer (account) | **SAP** (sold-to/ship-to, credit) | Salesforce (sales view) | Salesforce owns the *sales relationship*. SAP owns billing and credit data |
| Customer order (sales order) | **SAP** after creation | Salesforce (status), integration DB (integration state) | Salesforce owns it *before* submission |
| Material / product | **SAP** material master | WMS, MES, Salesforce product catalogue | Replicated by event or nightly sync |
| Price | **SAP** pricing conditions | Salesforce (indicative only) | Final price always comes from SAP simulation |
| Physical inventory (bin level) | **WMS** | SAP (plant/storage-location level) | Expect differences, so reconciliation is required |
| Financial inventory | **SAP** | — | Valued stock |
| Reservation | **WMS** (soft reservation) | SAP (schedule line confirmation) | |
| Purchase order | **SAP** | SupplierHub (copy sent to supplier) | |
| Supplier confirmation / ASN | **SupplierHub** → posted into SAP | | |
| Production order | **SAP** (planning) | MES (execution status) | MES owns *shop-floor progress* |
| Shipment | **TMS** | SAP (delivery), WMS (dispatch) | |
| Invoice | **SAP** | Salesforce (view) | Legally binding. 7-year retention assumed |
| Integration state, idempotency, outbox, audit | **Integration DB** | | Owned by the Mule apps |

## 5. A day in the life (real-time storytelling)

> **08:02** A sales rep at a water utility's account clicks **Submit Order** in Salesforce. The order is for 5 × `PMP-CF-200` and 40 × `VLV-BL-050`.
>
> **08:02:01** Salesforce calls the **Customer Order Experience API**. MuleSoft validates the payload, checks that the customer is active and the materials exist, and asks the WMS for availability. In parallel it asks SAP to simulate pricing.
>
> **08:02:02** The pumps are in stock at `DC-US-01`, but only 5 of the 40 valves are available. MuleSoft soft-reserves the pumps and 5 valves, creates SAP sales order `0000456789` and returns `201 Created` to Salesforce.
>
> **08:02:03** An `inventory.shortage-detected` event is published. The **Procurement Process API** creates a purchase requisition, and the SAP purchase order `4500012345` for 35 valves goes to the supplier through SupplierHub. If the same event is delivered twice, the idempotency key `ORD-…:VLV-BL-050` stops a second PO.
>
> **Day 3** The supplier confirms by REST callback. The ASN arrives on Day 9. The WMS posts the goods receipt on Day 10, and the order becomes fully reserved.
>
> **Day 11** The WMS picks, packs and dispatches. The **Shipment Process API** books FreightLink. Tracking events arrive by webhook, and proof of delivery triggers SAP billing. The invoice is generated and Salesforce shows **Delivered → Invoiced**.
>
> **Every step** carries correlation ID `c0a8-…`, so support can trace the order across all ten systems in one search.

Next: [02 — End-to-end process](02-end-to-end-process.md)
