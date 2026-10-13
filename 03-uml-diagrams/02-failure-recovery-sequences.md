# 03.2 — Failure & Recovery Sequences (Diagrams 8, 9, 10)

`Essential` (8, 9) · `Advanced` (10)

These three diagrams are the backbone of senior interviews. Each one shows a **failure case** and how the design handles it *without* blind retries.

## Diagram 8 — SAP timeout and recovery ("committed but caller timed out")

```mermaid
sequenceDiagram
    autonumber
    participant PRC as Order Mgmt Prc
    participant SYS as SAP Sys API
    participant SAP as SAP S/4HANA
    participant DB as Integration DB
    participant MQ as Anypoint MQ
    participant RET as ERP Retry Consumer

    PRC->>SYS: POST /sales-orders (externalRef ORD-123)
    SYS->>SAP: BAPI create + commit
    SAP-->>SAP: order 0000456789 committed
    Note over SYS,SAP: SAP response is slow - 6 s timeout fires
    SYS-->>SYS: HTTP:TIMEOUT - outcome UNKNOWN
    SYS->>SAP: lookup by externalRef ORD-123
    alt Found
        SAP-->>SYS: 0000456789
        SYS-->>PRC: 201 (recoveredAfterTimeout = true)
        PRC->>DB: TX - CONFIRMED + outbox
    else Not found or SAP unreachable
        SYS-->>PRC: 504 AIM-SAP-5041 status unknown
        PRC->>DB: TX - PENDING_ERP + outbox order.erp-pending
        PRC-->>PRC: respond 202 Accepted
        DB-->>MQ: relay publishes erp-pending
        MQ->>RET: deliver (delay / backoff)
        RET->>SYS: lookup by externalRef first
        alt Exists now
            RET->>DB: CONFIRMED (no second create)
        else Still missing
            RET->>SYS: create sales order (same externalRef)
            RET->>DB: CONFIRMED
        end
    end
```

**Key points**
- A timeout means **"I don't know"**, not "it failed". Retrying the create blindly can produce **two SAP orders**, which means two shipments and two invoices.
- The design needs a **unique, searchable business reference** in SAP, e.g. the customer PO field `BSTKD` or, better, a dedicated custom field. If SAP can't search by it, raise that dependency *early*. It's a design requirement for the SAP team.
- The lookup itself can fail (SAP fully down). The order then goes to `PENDING_ERP` and the retry consumer handles it, **always lookup-then-create**.
- **Race:** the lookup might run before SAP has finished committing (a long LUW). Mitigate with a small delay before the lookup, and keep lookup-first on every retry.

## Diagram 9 — Duplicate purchase-order prevention

```mermaid
sequenceDiagram
    autonumber
    participant MQ as Anypoint MQ
    participant C1 as Procurement consumer (replica 1)
    participant C2 as Procurement consumer (replica 2)
    participant DB as Integration DB
    participant SAP as SAP Sys API

    MQ->>C1: shortage event E-77 (delivery 1)
    C1->>DB: INSERT procurement_request key ORD-123:VLV-BL-050:1000
    DB-->>C1: OK (claimed)
    Note over C1: processing is slow - MQ ack timeout expires
    MQ->>C2: same event E-77 redelivered
    C2->>DB: INSERT same key
    DB-->>C2: UNIQUE VIOLATION
    C2->>DB: SELECT status for key
    DB-->>C2: IN_PROGRESS
    C2-->>MQ: nack with delay (or ack + skip if COMPLETED)
    C1->>SAP: create PO (ref = key)
    SAP-->>C1: PO 4500012345
    C1->>DB: UPDATE key COMPLETED, poNumber
    C1->>MQ: ack
```

**Why the database, not Object Store?** The unique constraint is enforced **atomically** by PostgreSQL, even across replicas and apps. It sits in the same transaction scope as other state, and it is queryable for reconciliation. Object Store v2 is fine for caching, but it is a poor fit for financially significant dedupe that needs auditability.

**Edge case:** C1 crashes after SAP created the PO but before `COMPLETED`. The key is stuck in `IN_PROGRESS`. A sweeper finds keys older than N minutes, **looks the PO up in SAP by reference**, and completes or retries. Dedupe always combines with lookup, never just "delete and retry".

## Diagram 10 — Asynchronous supplier confirmation (async request-reply, out-of-order)

```mermaid
sequenceDiagram
    autonumber
    participant PROC as Procurement Prc
    participant SUPX as Supplier Exp API
    participant MQ as Anypoint MQ (FIFO, group = PO)
    participant CONF as Confirmation consumer
    participant DB as Integration DB
    participant SAP as SAP Sys API

    PROC->>PROC: PO 4500012345 sent (correlation = PO no.)
    Note over SUPX: Days later the supplier calls back
    SUPX->>SUPX: mTLS + client-id check, schema validation
    SUPX->>MQ: enqueue confirmation v2 (seq 2, date change)
    SUPX-->>SUPX: 202 Accepted to supplier
    SUPX->>MQ: enqueue confirmation v1 (seq 1) - arrived late
    MQ->>CONF: deliver v2 first
    CONF->>DB: last applied seq for PO = 0, expected 1
    CONF->>DB: park v2 in pending_events
    MQ->>CONF: deliver v1
    CONF->>SAP: update PO confirmation (seq 1)
    CONF->>DB: last seq = 1, release parked v2
    CONF->>SAP: update PO confirmation (seq 2)
    CONF->>DB: last seq = 2
```

**Explanation**
- **Async request-reply:** the PO is sent now and the reply (confirmation) arrives days later. **The PO number is the correlation ID.**
- **Ack fast, process later (steps 3–5):** the supplier only waits for durable enqueue, not for SAP.
- **Ordering strategies** (pick per business need):
  1. **Sequence number + parking** (shown): strict, more complex.
  2. **Last-write-wins by supplier timestamp/version:** simpler. Old events are ignored if `version <= stored`. Use it when only the latest state matters.
  3. **FIFO queue with message group = PO:** preserves order *within* the queue, but cannot fix events that the *supplier* sent in the wrong order.
- **Parking needs a timeout:** if seq 1 never arrives, alert after X hours and let a buyer decide. Don't wait forever.

Next: [03.3 Fulfilment & delivery](03-fulfilment-and-delivery.md)
