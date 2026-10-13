%dw 2.0
/*
 * Canonical order (JSON) -> BAPI_SALESORDER_CREATEFROMDAT2 (XML shaped like SAP Connector metadata).
 * Our order ID is longer than REF_1 (CHAR 12), so it travels in a custom header field via
 * EXTENSIONIN / BAPE_VBAK (mapping-spec decision, see study kit 16.2). VALUEPART1 = VBELN (10 blanks) + ZZ_EXT_REF.
 * Sales area and plant are fixed for this training project (assumption).
 */
import leftPad from dw::core::Strings
import * from dwl::modules::aim::common
output application/xml
---
BAPI_SALESORDER_CREATEFROMDAT2: {
  "import": {
    ORDER_HEADER_IN: {
      DOC_TYPE: "ZOR",
      SALES_ORG: "1000",
      DISTR_CHAN: "10",
      DIVISION: "00",
      PURCH_NO_C: payload.customerPoNumber default payload.externalOrderId,
      REQ_DATE_H: toSapDate(payload.requestedDeliveryDate as Date),
      CURRENCY: payload.currency
    }
  },
  tables: {
    ORDER_PARTNERS: {
      row: { PARTN_ROLE: "AG", PARTN_NUMB: sapAlpha(payload.customerId replace "CUST-" with "") }
    },
    ORDER_ITEMS_IN: {
      (payload.lines map (l) -> {
        row: {
          ITM_NUMBER: leftPad(l.lineNumber as String, 6, "0"),
          MATERIAL: upper(l.materialNumber),
          PLANT: p('order.plant'),
          TARGET_QTY: l.quantity as String { format: "0.000" },
          TARGET_QU: sapUom(l.unitOfMeasure)
        }
      })
    },
    EXTENSIONIN: {
      row: { STRUCTURE: "BAPE_VBAK", VALUEPART1: "          " ++ payload.orderId }
    }
  }
}
