# 04.1 — API Catalogue (All Experience, Process and System APIs)

`Essential`

This is the reference for every API on the platform. There are three **detailed cards** (one per layer) that show the depth expected in a design review. The remaining APIs have **compact cards** with the same headings.

## Platform-wide standards (apply to every API)

| Topic | Standard |
|-------|----------|
| Base path | `/{layer}/{api-name}/v{major}`, e.g. `/api/v1` (exp), `/prc/order-mgmt/v1`, `/sys/sap/v1` |
| Required headers | `x-correlation-id` (generated if absent), `Authorization` or `client_id`/`client_secret`, `Content-Type` |
| Idempotency header | `Idempotency-Key` on every non-idempotent POST that creates business objects |
| Error contract | `{ "error": { "code", "message", "correlationId", "timestamp", "details": [] } }`. See [04.3](03-error-contract-and-versioning.md) |
| Dates | ISO-8601. `date-only` for business dates, `datetime` in UTC with `Z` for events |
| Money | `{ "amount": "1234.50", "currency": "USD" }`. The amount is a string/decimal, **never float** |
| Pagination | `?offset=&limit=` (max 200) with a `Link` header |
| Logging | Entry/exit at INFO with correlationId, orderId, durationMs. Payloads only at DEBUG and masked |
| Versioning | URI major version. Additive changes are minor (no new URI) |

---

## DETAILED CARD — Experience: `customer-order-exp-api`

| Item | Detail |
|------|--------|
| **Purpose** | The single entry point for customer orders from Salesforce and the B2B portal |
| **Consumers** | Salesforce (Apex callout / Flow HTTP callout), B2B portal BFF |
| **Dependencies** | `order-mgmt-prc-api` |
| **Auth** | OAuth 2.0 client credentials. JWT validated by an API Manager policy. Scopes: `orders:write`, `orders:read` |
| **Policies** | JWT validation, rate limiting SLA-based (Salesforce: 30 req/s, portal: 10 req/s), spike control, header injection of correlation ID |
| **Timeout** | Calls Prc with 12 s. Expected client timeout ≥ 15 s |
| **Retry** | **No retries inside Exp for POST.** The client retries with the same `Idempotency-Key`. GETs may retry once on a connectivity error |
| **Idempotency** | Required `Idempotency-Key` header on POST (Salesforce Order Id). Enforced in Prc |
| **Ownership** | Sales-channel integration team. On-call: Integration L2 |

**Resources**

| Method | Path | Description | Success | Errors |
|--------|------|-------------|---------|--------|
| POST | `/api/v1/orders` | Submit an order | `201` confirmed, `202` accepted (ERP pending) | 400, 401, 403, 409, 422, 429, 502, 503, 504 |
| GET | `/api/v1/orders/{orderId}` | Order status + SAP number + tracking | `200` | 401, 404 |
| GET | `/api/v1/orders?externalOrderId=` | Find by Salesforce ID | `200` | 400 |

**Request example**
```json
{
  "externalOrderId": "SF-00012345",
  "sourceSystem": "SALESFORCE",
  "customerId": "CUST-100234",
  "customerPoNumber": "WU-PO-77812",
  "currency": "USD",
  "requestedDeliveryDate": "2026-11-20",
  "shipTo": { "name": "Riverside Water Utility", "line1": "100 River Rd", "city": "Austin", "postalCode": "73301", "country": "US" },
  "lines": [
    { "lineNumber": 10, "materialNumber": "PMP-CF-200", "quantity": 5, "unitOfMeasure": "EA" },
    { "lineNumber": 20, "materialNumber": "VLV-BL-050", "quantity": 40, "unitOfMeasure": "EA" }
  ]
}
```

**Response `201`**
```json
{
  "orderId": "AIM-20261013-7F3A9C21",
  "externalOrderId": "SF-00012345",
  "status": "BACKORDERED",
  "sapOrderNumber": "0000456789",
  "lines": [
    { "lineNumber": 10, "materialNumber": "PMP-CF-200", "reservedQty": 5, "backorderedQty": 0 },
    { "lineNumber": 20, "materialNumber": "VLV-BL-050", "reservedQty": 5, "backorderedQty": 35 }
  ],
  "links": { "self": "/api/v1/orders/AIM-20261013-7F3A9C21" }
}
```

**Response `202`** (SAP unavailable or slow): `{"orderId": "...", "status": "PENDING_ERP", "message": "Order accepted, ERP confirmation pending"}`

**DataWeave (Salesforce → canonical):** see [05.3](../05-dataweave/03-supplier-canonical-lookups.md).

**Monitoring:** dashboard tiles for request rate, 4xx/5xx split, p95 latency and the 202-ratio. A rising 202 ratio is an **early SAP health signal**.

**Testing:** MUnit for mapping and error mapping. Postman contract tests against RAML examples. Performance test at 10 req/s.

---

## DETAILED CARD — Process: `order-mgmt-prc-api`

| Item | Detail |
|------|--------|
| **Purpose** | Orchestrates the order saga: idempotency → validate → reserve → SAP order → state + events |
| **Consumers** | `customer-order-exp-api`. Internal ops tools (status) |
| **Dependencies** | `salesforce-sys-api`, `inventory-availability-prc-api`, `sap-erp-sys-api`, PostgreSQL, Anypoint MQ |
| **Auth** | Client ID enforcement (internal). Only the Exp API's client app is allowed |
| **Timeouts** | Scatter-Gather 3 s, reservation 2 s, SAP 6 s |
| **Retries** | GET availability: up to 2 retries on connectivity errors. SAP create: **none**, lookup instead. Reservation: none (the next attempt uses the same order id, so WMS dedupes) |
| **Idempotency** | DB table `idempotency_record (key PK, request_hash, status, response, http_status)` |
| **Owns data** | `order_state`, `outbox_event`, `idempotency_record`, `audit_log` |
| **Events published** | `order.confirmed`, `order.backordered`, `order.erp-pending`, `inventory.shortage-detected`, `order.mto-required` |

| Method | Path | Notes |
|--------|------|-------|
| POST | `/prc/order-mgmt/v1/orders` | Canonical order in. 201/202/409/422 |
| GET | `/prc/order-mgmt/v1/orders/{orderId}` | From `order_state` |
| POST | `/prc/order-mgmt/v1/orders/{orderId}/cancellation` | Starts the cancellation saga |

**Error mapping it produces:** `AIM-ORD-4001` validation, `AIM-ORD-4091` in progress, `AIM-ORD-4221` key reused with a different body, `AIM-ORD-4223` customer blocked, `AIM-ORD-4224` invalid material, `AIM-SAP-4225` SAP business rejection, `AIM-DEP-5021` downstream failure.

---

## DETAILED CARD — System: `sap-erp-sys-api`

| Item | Detail |
|------|--------|
| **Purpose** | Safe, reusable access to SAP S/4HANA. It hides BAPI/IDoc/OData details |
| **Consumers** | Order, Inventory, Procurement, Production, Shipment Prc APIs |
| **Connectivity** | SAP Connector (JCo) via VPN → SAP gateway. OData via HTTPS for read APIs |
| **Auth (inbound)** | Client ID enforcement + IP allow-list of the Private Space |
| **Auth (to SAP)** | Technical RFC user with SNC. Pooled connections (max 20 per replica, assumption, agreed with SAP Basis) |
| **Timeouts** | Create 6 s, reads 3 s, bulk 30 s |
| **Retries** | Reads: 2 retries with backoff. Creates: **no retry**. Timeout → lookup by external ref |
| **Error translation** | A BAPI `RETURN` table with `TYPE E/A` becomes `422 AIM-SAP-4225` with SAP message details. Comm failure becomes `503 AIM-SAP-5031`. Timeout with unknown outcome becomes `504 AIM-SAP-5041` |

| Method | Path | SAP mapping |
|--------|------|-------------|
| POST | `/sys/sap/v1/sales-orders` | `BAPI_SALESORDER_CREATEFROMDAT2` + `BAPI_TRANSACTION_COMMIT` |
| GET | `/sys/sap/v1/sales-orders?externalRef=` | OData `API_SALES_ORDER_SRV` `$filter=PurchaseOrderByCustomer eq '...'` |
| POST | `/sys/sap/v1/sales-orders/simulations` | `BAPI_SALESORDER_SIMULATE` (pricing) |
| GET | `/sys/sap/v1/materials/{materialNumber}` | `BAPI_MATERIAL_GET_DETAIL` (cached 1 h) |
| POST | `/sys/sap/v1/availability` | `BAPI_MATERIAL_AVAILABILITY` |
| POST | `/sys/sap/v1/purchase-orders` | `BAPI_PO_CREATE1` |
| POST | `/sys/sap/v1/production-orders` | `BAPI_PRODORD_CREATE` |
| POST | `/sys/sap/v1/goods-movements` | `BAPI_GOODSMVT_CREATE` (GR, GI) |
| POST | `/sys/sap/v1/billing-documents` | `BAPI_BILLINGDOC_CREATEMULTIPLE` |

> **Senior note on BAPIs:** BAPIs **don't throw exceptions for business errors**. They return a `RETURN` table. You must inspect `TYPE` (S, I, W, E, A) and call `BAPI_TRANSACTION_COMMIT` (or rollback) explicitly. Forgetting the commit gives "success" responses with no document in SAP, a classic production bug.

---

## Compact cards — other APIs

| API | Purpose | Key resources | Consumers | Auth | Idempotency | Timeout / retry |
|-----|---------|---------------|-----------|------|-------------|-----------------|
| **supplier-exp-api** | Supplier confirmations and ASNs | `POST /purchase-orders/{po}/confirmations`, `POST /advance-shipping-notices`, `GET /purchase-orders?status=OPEN` | Supplier systems | **mTLS** + client-id per supplier, rate limit 5 req/s per supplier | Supplier message ID header | Ack after enqueue (≤ 500 ms). No sync backend calls |
| **warehouse-ops-exp-api** | WMS webhooks + handheld queries | `POST /events/dispatch-ready`, `POST /events/goods-receipt`, `GET /inventory/{material}` | WMS, handheld app | HMAC signature + client-id | WMS event ID | Ack fast, queue |
| **logistics-tracking-exp-api** | Carrier webhooks + tracking query | `POST /webhooks/{carrier}`, `GET /shipments/{deliveryNo}/tracking` | Carriers, portal | HMAC / API key per carrier, IP allow-list | Carrier event ID | Ack fast |
| **inventory-availability-prc-api** | Availability across DCs, reservation lifecycle, recon | `POST /availability-checks`, `POST /reservations`, `DELETE /reservations/{id}`, `POST /reconciliations` | Order Prc, Warehouse Exp | client-id | Reservation keyed by orderId+line | WMS 2 s, 1 retry on GET |
| **procurement-prc-api** | Shortage → PR/PO, confirmations | `POST /procurement-requests`, `POST /confirmations` (internal), events | MQ consumers, Supplier Exp | client-id | `{orderId}:{material}:{plant}` | SAP 6 s, supplier 10 s with backoff on 429 |
| **production-fulfilment-prc-api** | MTO production + outbound fulfilment | `POST /production-requests`, `POST /fulfilments` | MQ consumers | client-id | prodOrder + MES eventId | SAP 6 s |
| **shipment-delivery-prc-api** | Booking, tracking, POD → invoice | `POST /shipments`, `POST /deliveries/{no}/pod` | MQ consumers, Logistics Exp | client-id | deliveryNumber | Carrier 10 s, backoff |
| **salesforce-sys-api** | Accounts, order status upsert | `GET /accounts/{id}`, `PATCH /orders/{externalId}/status` | Order, Shipment Prc | client-id. Salesforce OAuth JWT bearer flow to SF | Upsert by external ID | 5 s. Retry on `UNABLE_TO_LOCK_ROW` |
| **wms-sys-api** | WMS REST wrapper | `POST /availability`, `POST /reservations`, `DELETE /reservations/{id}`, `POST /outbound-orders` | Inventory, Fulfilment Prc | client-id. API key to WMS | Reservation reference | 2 s |
| **supplier-sys-api** | Send POs to SupplierHub | `POST /purchase-orders` | Procurement Prc | client-id. OAuth to SupplierHub | Idempotency-Key forwarded | Respects `Retry-After` |
| **logistics-sys-api** | Carrier/TMS booking and tracking | `POST /shipments`, `GET /shipments/{id}` | Shipment Prc | client-id. Carrier OAuth / API key | Shipper reference | 10 s |
| **mes-sys-api** | Production orders to MES | `POST /production-orders`, `GET /production-orders/{id}` | Production Prc | client-id + mTLS to the plant | prodOrder | 5 s |
| **integration-db-sys-api** | Read model for ops and analytics | `GET /orders/{id}/timeline`, `GET /reconciliation-results` | Ops dashboard, analytics | client-id + OAuth (ops role) | n/a (read-only) | 3 s |

## Operational ownership model

| Layer | Build owner | Run owner (L2) | Escalation (L3) |
|-------|-------------|----------------|-----------------|
| Experience | Channel squads | Integration support | Channel squad |
| Process | Domain integration squads | Integration support | Domain squad |
| System | Platform / backend-aligned squad | Integration support | Platform squad + backend team (SAP Basis, WMS vendor) |

Next: [04.2 RAML specifications](02-raml-specifications.md)
