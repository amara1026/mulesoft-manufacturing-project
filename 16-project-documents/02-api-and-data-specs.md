# 16.2 — API Specifications, Dependency Matrix, Data Mapping Specification, Error-Code Catalogue

`Essential` · Covers documents **4, 5, 6 and 7**.

## 4. API specifications

**What it is:** the RAML (or OAS) contract published in Exchange, plus a human-readable API page.
**Where:** [04.2 RAML](../04-api-design/02-raml-specifications.md), and the runnable [order-exp-api.raml](../mule-project/aim-order-integration/src/main/resources/api/order-exp-api.raml).
**Exchange page sections:** Overview · Consumers & use cases · Authentication · Resources · Error codes · Rate limits/SLA tiers · Versioning & deprecation · Support contact · Changelog.
**Lifecycle use:** consumers build against the mock. QA derives contract tests. API Manager instances reference the asset version.

## 5. API dependency matrix

See [04.4](../04-api-design/04-api-dependency-matrix.md). **Lifecycle use:** impact analysis for changes, incident blast-radius assessment, release sequencing (deploy System APIs before the Process APIs that depend on new operations).

## 6. Data mapping specification (excerpt: MAP-ORD-002 Canonical Order → SAP BAPI_SALESORDER_CREATEFROMDAT2)

| # | Target (SAP) | Target type/len | Source (canonical) | Rule / transformation | Default | Mandatory | Example |
|---|--------------|----------------|--------------------|-----------------------|---------|-----------|---------|
| 1 | ORDER_HEADER_IN.DOC_TYPE | CHAR 4 | — | Constant | `ZOR` | Y | ZOR |
| 2 | ORDER_HEADER_IN.SALES_ORG | CHAR 4 | salesArea.salesOrg | Derived from the customer's sales area (lookup by customer) | — | Y | 1000 |
| 3 | ORDER_HEADER_IN.DISTR_CHAN | CHAR 2 | salesArea.distributionChannel | Direct | `10` | Y | 10 |
| 4 | ORDER_HEADER_IN.DIVISION | CHAR 2 | salesArea.division | Direct | `00` | Y | 00 |
| 5 | ORDER_HEADER_IN.PURCH_NO_C | CHAR 35 | customerPoNumber | Truncate to 35 (validated upstream) | externalOrderId | Y | WU-PO-77812 |
| 6 | ORDER_HEADER_IN.REF_1 | CHAR 12 | orderId | **Business reference for lookup** (unique) | — | Y | AIM-2026… |
| 7 | ORDER_HEADER_IN.REQ_DATE_H | DATS 8 | requestedDeliveryDate | `yyyy-MM-dd` → `yyyyMMdd` | — | Y | 20261120 |
| 8 | ORDER_PARTNERS.row.PARTN_ROLE | CHAR 2 | — | Constant sold-to | `AG` | Y | AG |
| 9 | ORDER_PARTNERS.row.PARTN_NUMB | CHAR 10 | customerId | Strip `CUST-`, ALPHA pad to 10 | — | Y | 0000100234 |
| 10 | ORDER_ITEMS_IN.row.ITM_NUMBER | NUMC 6 | lines[].lineNumber | Left-pad 6 | — | Y | 000010 |
| 11 | ORDER_ITEMS_IN.row.MATERIAL | CHAR 40 | lines[].materialNumber | Upper-case, trim | — | Y | PMP-CF-200 |
| 12 | ORDER_ITEMS_IN.row.TARGET_QTY | QUAN 13,3 | lines[].quantity | Format `0.000` | — | Y | 5.000 |
| 13 | ORDER_ITEMS_IN.row.TARGET_QU | UNIT 3 | lines[].unitOfMeasure | Lookup EA→ST, BOX→KAR (confirmed with SAP SD) | — | Y | ST |

**Open points log:** "REF_1 length 12 is too short for the 21-char orderId. **Decision:** use the custom field ZZ_EXT_REF (CHAR 40) via BAPI extension. Owner: SAP SD. Due 2026-08-20." *(This illustrates why mapping specs must check field lengths, a classic late surprise.)*

**Lifecycle use:** signed off by the SAP functional consultant and the business analyst. It's the reference for DW code reviews and golden-file tests. Any default value must appear here.

## 7. Error-code catalogue (excerpt)

| Code | HTTP | Title | Description | Cause category | Retry? | Client action | Support action | Runbook |
|------|------|-------|-------------|----------------|--------|---------------|----------------|---------|
| AIM-ORD-4001 | 400 | Invalid request | Payload failed schema validation | Client | No | Fix the payload (see details[]) | None | — |
| AIM-ORD-4091 | 409 | Request in progress | Same Idempotency-Key is being processed | Client timing | Yes (≥ 2 s, same key) | Retry later | None | — |
| AIM-ORD-4221 | 422 | Idempotency key reused | Same key, different body | Client bug | No | Generate the key per order | Inform the consumer team | RB-ORD-02 |
| AIM-ORD-4223 | 422 | Customer not orderable | Blocked/inactive/credit hold | Business | No | Contact credit team | — | — |
| AIM-ORD-4224 | 422 | Invalid material/UoM | Unknown material or unit | Data | No | Correct the product | Master data check | RB-MD-01 |
| AIM-SAP-4225 | 422 | SAP rejected order | BAPI RETURN E/A | Business/data | No | Per the SAP message | Check the SAP message class | RB-SAP-03 |
| AIM-SAP-5031 | 503 | ERP unavailable | SAP unreachable | Dependency | Yes (backoff) | Retry with the same key | Check VPN/SAP | RB-SAP-01 |
| AIM-SAP-5041 | 504 | ERP outcome unknown | Timeout, lookup inconclusive | Dependency | Yes (same key) | Treat as pending | Monitor PENDING_ERP | RB-SAP-02 |
| AIM-GEN-5001 | 500 | Internal error | Unhandled | Bug | Maybe once | Contact support with correlationId | Incident | RB-GEN-01 |

**Lifecycle use:** consumers implement their handling from this table. Support uses it to triage. Every new error type in code requires a catalogue entry (a code review check).

Next: [16.3 Test documents](03-test-documents.md)
