# 05.2 — JSON ↔ XML Transformations and SAP-Oriented Mapping

`Essential`

## Example 1 — Canonical order (JSON) → SAP BAPI XML (JSON → XML)

The SAP Connector represents a BAPI call as XML with `import`, `tables` and `export` sections. In Studio, DataSense metadata generates this structure for you. The layout below **mirrors that shape**, but you should always check it against the metadata your connector version produces.

**Input (canonical order)**
```json
{
  "orderId": "AIM-20261013-7F3A9C21",
  "customerId": "CUST-100234",
  "customerPoNumber": "WU-PO-77812",
  "requestedDeliveryDate": "2026-11-20",
  "currency": "USD",
  "salesArea": { "salesOrg": "1000", "distributionChannel": "10", "division": "00" },
  "lines": [
    { "lineNumber": 10, "materialNumber": "PMP-CF-200", "quantity": 5, "unitOfMeasure": "EA", "plant": "1000" },
    { "lineNumber": 20, "materialNumber": "VLV-BL-050", "quantity": 40, "unitOfMeasure": "EA", "plant": "1000" }
  ]
}
```

**Script**
```dataweave
%dw 2.0
output application/xml
import leftPad from dw::core::Strings
var sapCustomer = leftPad(payload.customerId replace "CUST-" with "", 10, "0")
fun sapItem(n: Number): String = leftPad(n as String, 6, "0")
fun sapDate(d: String): String = (d as Date) as String { format: "yyyyMMdd" }
fun sapUom(u: String): String = { "EA": "ST", "PC": "ST", "KG": "KG", "M": "M", "BOX": "KAR" }[u] default u
---
BAPI_SALESORDER_CREATEFROMDAT2: {
  "import": {
    ORDER_HEADER_IN: {
      DOC_TYPE: "ZOR",
      SALES_ORG: payload.salesArea.salesOrg,
      DISTR_CHAN: payload.salesArea.distributionChannel,
      DIVISION: payload.salesArea.division,
      PURCH_NO_C: payload.customerPoNumber,
      REF_1: payload.orderId,
      REQ_DATE_H: sapDate(payload.requestedDeliveryDate),
      CURRENCY: payload.currency
    }
  },
  tables: {
    ORDER_PARTNERS: {
      row: { PARTN_ROLE: "AG", PARTN_NUMB: sapCustomer }
    },
    ORDER_ITEMS_IN: {
      (payload.lines map (l) -> {
        row: {
          ITM_NUMBER: sapItem(l.lineNumber),
          MATERIAL: l.materialNumber,
          PLANT: l.plant,
          TARGET_QTY: l.quantity as String { format: "0.000" },
          TARGET_QU: sapUom(l.unitOfMeasure)
        }
      })
    },
    ORDER_SCHEDULES_IN: {
      (payload.lines map (l) -> {
        row: {
          ITM_NUMBER: sapItem(l.lineNumber),
          REQ_DATE: sapDate(payload.requestedDeliveryDate),
          REQ_QTY: l.quantity as String { format: "0.000" }
        }
      })
    }
  }
}
```

**Output (abridged)**
```xml
<?xml version='1.0' encoding='UTF-8'?>
<BAPI_SALESORDER_CREATEFROMDAT2>
  <import>
    <ORDER_HEADER_IN>
      <DOC_TYPE>ZOR</DOC_TYPE><SALES_ORG>1000</SALES_ORG><DISTR_CHAN>10</DISTR_CHAN><DIVISION>00</DIVISION>
      <PURCH_NO_C>WU-PO-77812</PURCH_NO_C><REF_1>AIM-20261013-7F3A9C21</REF_1>
      <REQ_DATE_H>20261120</REQ_DATE_H><CURRENCY>USD</CURRENCY>
    </ORDER_HEADER_IN>
  </import>
  <tables>
    <ORDER_PARTNERS><row><PARTN_ROLE>AG</PARTN_ROLE><PARTN_NUMB>0000100234</PARTN_NUMB></row></ORDER_PARTNERS>
    <ORDER_ITEMS_IN>
      <row><ITM_NUMBER>000010</ITM_NUMBER><MATERIAL>PMP-CF-200</MATERIAL><PLANT>1000</PLANT><TARGET_QTY>5.000</TARGET_QTY><TARGET_QU>ST</TARGET_QU></row>
      <row><ITM_NUMBER>000020</ITM_NUMBER><MATERIAL>VLV-BL-050</MATERIAL><PLANT>1000</PLANT><TARGET_QTY>40.000</TARGET_QTY><TARGET_QU>ST</TARGET_QU></row>
    </ORDER_ITEMS_IN>
    <ORDER_SCHEDULES_IN>...</ORDER_SCHEDULES_IN>
  </tables>
</BAPI_SALESORDER_CREATEFROMDAT2>
```

**What a senior should notice**
- **Leading zeros (ALPHA conversion):** SAP stores customer `100234` as `0000100234`. A missing pad gives "customer not found", which is one of the most common SAP integration bugs.
- **Internal vs external UoM:** SAP's *internal* unit for "each" is often `ST` (German *Stück*), while the external/ISO code is `EA`/`PCE`. Confirm with the SAP team which one the BAPI expects. The lookup function makes the mapping explicit.
- **Repeating `row` elements:** writing XML repeated elements uses the **dynamic object** `{( array map ... )}`. Each array element contributes a `row` key to the same parent.
- **The `import` key is quoted** because `import` is a DataWeave keyword.
- `REF_1` carries our order ID. This is the **external reference that is used for the lookup after a timeout** ([03.2](../03-uml-diagrams/02-failure-recovery-sequences.md)). Real-world catch: `REF_1` is only CHAR 12, too short for a 21-character order ID. The mapping spec ([16.2](../16-project-documents/02-api-and-data-specs.md)) therefore moves the reference to a custom field passed through `EXTENSIONIN` / `BAPE_VBAK`, and that is what the mini project does in `canonical-to-bapi-salesorder.dwl`. Always check target field lengths.

## Example 2 — SAP BAPI response (XML) → JSON, with RETURN-table error handling (XML → JSON)

**Input**
```xml
<BAPI_SALESORDER_CREATEFROMDAT2>
  <export><SALESDOCUMENT>0000456789</SALESDOCUMENT></export>
  <tables>
    <RETURN>
      <row><TYPE>S</TYPE><ID>V1</ID><NUMBER>311</NUMBER><MESSAGE>Standard Order 456789 has been saved</MESSAGE></row>
      <row><TYPE>W</TYPE><ID>V1</ID><NUMBER>555</NUMBER><MESSAGE>Requested delivery date cannot be met</MESSAGE></row>
    </RETURN>
  </tables>
</BAPI_SALESORDER_CREATEFROMDAT2>
```

**Script**
```dataweave
%dw 2.0
output application/json
var resp = payload.BAPI_SALESORDER_CREATEFROMDAT2
var messages = resp.tables.RETURN.*row default []
var errors = messages filter (["E", "A"] contains $.TYPE)
---
{
  success: isEmpty(errors) and !isEmpty(resp.export.SALESDOCUMENT),
  salesOrderNumber: resp.export.SALESDOCUMENT,
  warnings: (messages filter ($.TYPE == "W")) map { code: "$($.ID)-$($.NUMBER)", text: $.MESSAGE },
  errors: errors map { code: "$($.ID)-$($.NUMBER)", text: $.MESSAGE }
}
```

**Output**
```json
{
  "success": true,
  "salesOrderNumber": "0000456789",
  "warnings": [ { "code": "V1-555", "text": "Requested delivery date cannot be met" } ],
  "errors": []
}
```

**Explanation:** `*row` returns **all** rows, even when there is only one. Without `*`, a single-row RETURN becomes an object, not an array, and the code breaks only on single-message responses (a classic intermittent bug). The Mule flow then uses a **Choice**: if `success == false`, raise `AIM:SAP_BUSINESS_ERROR` with the error texts.

## Example 3 — IDoc XML (ORDERS05 inbound from a supplier-facing system) → canonical JSON

```xml
<ORDERS05>
  <IDOC BEGIN="1">
    <EDI_DC40 SEGMENT="1"><DOCNUM>0000000071234567</DOCNUM><MESTYP>ORDRSP</MESTYP></EDI_DC40>
    <E1EDK01 SEGMENT="1"><BELNR>4500012345</BELNR><CURCY>USD</CURCY></E1EDK01>
    <E1EDP01 SEGMENT="1"><POSEX>00010</POSEX><MENGE>35.000</MENGE><MENEE>PCE</MENEE>
      <E1EDP20 SEGMENT="1"><WMENG>35.000</WMENG><EDATU>20261022</EDATU></E1EDP20>
    </E1EDP01>
  </IDOC>
</ORDERS05>
```

```dataweave
%dw 2.0
output application/json
var idoc = payload.ORDERS05.IDOC
---
{
  messageId: idoc.EDI_DC40.DOCNUM,
  messageType: idoc.EDI_DC40.MESTYP,
  poNumber: idoc.E1EDK01.BELNR,
  lines: idoc.*E1EDP01 map (p) -> {
    poItem: p.POSEX as Number,
    confirmedQty: p.E1EDP20.WMENG as Number,
    confirmedDate: (p.E1EDP20.EDATU as Date { format: "yyyyMMdd" }) as String { format: "yyyy-MM-dd" },
    uom: p.MENEE
  }
}
```
**Output:** `{"messageId":"0000000071234567","messageType":"ORDRSP","poNumber":"4500012345","lines":[{"poItem":10,"confirmedQty":35,"confirmedDate":"2026-10-22","uom":"PCE"}]}`

Notes: `"00010" as Number` gives `10`. Segment attributes such as `SEGMENT="1"` are ignored unless you select them with `.@SEGMENT`.

## Example 4 — JSON → XML with attributes and namespaces (carrier booking SOAP-style)

```dataweave
%dw 2.0
output application/xml
ns soap http://schemas.xmlsoap.org/soap/envelope/
ns fl http://freightlink.example.com/booking/v2
---
soap#Envelope: {
  soap#Body: {
    fl#BookShipment @(shipperRef: payload.deliveryNumber, service: "LTL"): {
      fl#Packages: {
        (payload.handlingUnits map (hu) -> {
          fl#Package @(id: hu.huId): {
            fl#WeightKg: hu.weightKg,
            fl#Dims @(unit: "cm"): "$(hu.length)x$(hu.width)x$(hu.height)"
          }
        })
      }
    }
  }
}
```

The output has the `soap`/`fl` prefixes declared on the root and attributes on `BookShipment` and `Package`. For real SOAP services, prefer the **Web Service Consumer** connector, which builds the envelope from the WSDL. You then map only the body.

## Practice exercise
Write a script that converts SAP `RETURN` messages into the AIM error contract ([04.3](../04-api-design/03-error-contract-and-versioning.md)), using `AIM-SAP-4225` and one `details[]` entry per E/A message.

Next: [05.3 Supplier payloads, canonical model, lookups](03-supplier-canonical-lookups.md)
