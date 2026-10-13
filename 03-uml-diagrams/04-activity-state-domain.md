# 03.4 — Activity Diagram, Order State Machine, Domain Model (Diagrams 13, 14, 15)

`Essential`

## Diagram 13 — Activity: order validation and fulfilment decision

```mermaid
flowchart TD
    S((Start)) --> V1[Validate schema<br/>APIkit]
    V1 -->|invalid| R400[/400 Bad Request/]
    V1 --> IK{Idempotency key<br/>seen before?}
    IK -->|completed, same hash| REPLAY[/Replay stored response/]
    IK -->|completed, different hash| R422K[/422 key reused/]
    IK -->|in progress| R409[/409 Conflict/]
    IK -->|new| PAR[Parallel: customer check + availability]
    PAR --> C1{Customer active<br/>and not credit-blocked?}
    C1 -->|no| REJ[Status REJECTED] --> R422[/422 Unprocessable/]
    C1 -->|yes| C2{All materials valid?}
    C2 -->|no| REJ
    C2 -->|yes| C3{Stock for all lines?}
    C3 -->|yes| RES[Reserve all lines]
    C3 -->|partial| RESP[Reserve available qty]
    RESP --> MB{Line type?}
    MB -->|buy| EVB[Emit shortage event]
    MB -->|make| EVM[Emit MTO event]
    C3 -->|none| MB
    RES --> SAPC[Create SAP sales order]
    EVB --> SAPC
    EVM --> SAPC
    SAPC --> SO{SAP result}
    SO -->|created| CONF[CONFIRMED or BACKORDERED]
    SO -->|business error| COMP[Release reservation] --> REJ
    SO -->|timeout, unknown| PEND[PENDING_ERP + retry event]
    CONF --> PERSIST[Persist state + outbox in one TX]
    PEND --> PERSIST
    PERSIST --> RESP2[/201 or 202/]
```

**Decision points explained**
- **Idempotency check comes first**, before any side effect. A repeated request must never reach SAP again.
- **Customer and material validity are hard stops** (422). These are *business* errors, so they are not retried.
- **Partial stock** doesn't reject the order. It splits into reserved and backordered quantities. Whether partial delivery is allowed is a customer master setting in SAP, so read it, don't assume it.
- **Make vs buy** comes from the material's procurement type in SAP (`E` = in-house, `F` = external). Cache it from the material master.
- **Three SAP outcomes**: success, definitive failure (compensate) and unknown (forward recovery). Interviewers love candidates who separate these.

## Diagram 14 — Order lifecycle state machine

```mermaid
stateDiagram-v2
    [*] --> RECEIVED
    RECEIVED --> REJECTED: validation failed
    RECEIVED --> PENDING_ERP: SAP outcome unknown
    RECEIVED --> CONFIRMED: SAP order created, fully reserved
    RECEIVED --> BACKORDERED: SAP order created, shortage
    PENDING_ERP --> CONFIRMED: retry or lookup succeeded
    PENDING_ERP --> BACKORDERED: retry succeeded with shortage
    PENDING_ERP --> FAILED_NEEDS_ATTENTION: retries exhausted
    BACKORDERED --> CONFIRMED: supply received / production done
    CONFIRMED --> RELEASED_TO_WAREHOUSE: outbound delivery created
    RELEASED_TO_WAREHOUSE --> SHIPPED: dispatch + carrier booked
    SHIPPED --> DELIVERED: POD received
    DELIVERED --> INVOICED: billing doc created
    INVOICED --> CLOSED: payment cleared (SAP FI)
    CONFIRMED --> CANCELLED: customer cancel
    BACKORDERED --> CANCELLED: customer cancel
    FAILED_NEEDS_ATTENTION --> CONFIRMED: ops replay
    FAILED_NEEDS_ATTENTION --> CANCELLED: ops decision
    REJECTED --> [*]
    CANCELLED --> [*]
    CLOSED --> [*]
```

**How the state machine is enforced in Mule**
- `order_state.status` holds the current state, plus a `version` column for **optimistic locking**:
  `UPDATE order_state SET status=:new, version=version+1 WHERE order_id=:id AND version=:v AND status IN (:allowedFrom)`.
  When 0 rows are updated, the transition is invalid or there was a concurrent update. Log it, re-read, and decide.
- **Out-of-order events can't move state backwards.** A late `SHIPPED` event after `DELIVERED` is ignored for state, but it is recorded in history.
- Every transition writes an **audit row** (who, when, from, to, correlationId).

## Diagram 15 — Domain model

```mermaid
classDiagram
    class Customer {
      +customerId : String
      +name : String
      +status : String
      +creditLimit : Money
      +partialDeliveryAllowed : Boolean
    }
    class Order {
      +orderId : String
      +externalOrderId : String
      +sapOrderNumber : String
      +status : OrderStatus
      +currency : String
      +requestedDeliveryDate : Date
    }
    class OrderLine {
      +lineNumber : Int
      +quantity : Decimal
      +unitOfMeasure : String
      +reservedQty : Decimal
      +backorderedQty : Decimal
    }
    class Material {
      +materialNumber : String
      +description : String
      +baseUoM : String
      +procurementType : String
    }
    class Inventory {
      +materialNumber : String
      +location : String
      +onHand : Decimal
      +reserved : Decimal
      +available() Decimal
    }
    class PurchaseOrder {
      +poNumber : String
      +supplierId : String
      +status : String
      +confirmedDate : Date
    }
    class ProductionOrder {
      +prodOrderNumber : String
      +plant : String
      +status : String
      +lastSequenceNo : Int
    }
    class Shipment {
      +deliveryNumber : String
      +trackingNumber : String
      +carrier : String
      +status : String
    }
    class Invoice {
      +invoiceNumber : String
      +amount : Money
      +deliveryNumber : String
    }
    Customer "1" --> "0..*" Order : places
    Order "1" *-- "1..*" OrderLine : contains
    OrderLine "*" --> "1" Material : refers to
    Material "1" --> "0..*" Inventory : stocked at
    OrderLine "0..*" --> "0..1" PurchaseOrder : supplied by
    OrderLine "0..*" --> "0..1" ProductionOrder : produced by
    Order "1" --> "0..*" Shipment : fulfilled by
    Shipment "1" --> "0..1" Invoice : billed by
```

**Explanation**
- **Order ↔ OrderLine is composition**: lines don't exist without their order.
- **Shortages are linked per line**, not per order. One order can have one line from stock, one from a PO and one from production.
- **Invoice links to Shipment (delivery)**, not to Order. That is how SAP bills (per delivery). It's also why delivery number is the invoice idempotency key.
- `Inventory.available() = onHand - reserved`. WMS and SAP compute this differently (bin vs storage location), and that is a root cause of inventory discrepancies ([13 scenario 11](../13-production-troubleshooting/03-scenarios-11-15.md)).

This model is the **canonical model**. Each System API maps SAP/WMS/Salesforce fields to and from it. See [05.3](../05-dataweave/03-supplier-canonical-lookups.md).

Next: [03.5 Batch & DLQ/replay](05-batch-dlq-replay.md)
