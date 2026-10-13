%dw 2.0
/*
 * Builds the events written to the outbox in the same DB transaction as the order state.
 * Expects vars: orderId, order, orderStatus, sapOrderNumber, allocation.
 * Envelope: eventId, eventType, schemaVersion, occurredAt, source, correlationId, data.
 */
import isoNow from dwl::modules::aim::common
output application/java
fun envelope(eventType: String, data) = {
  eventId: uuid(),
  eventType: eventType,
  schemaVersion: "1.0",
  occurredAt: isoNow(),
  source: "order-mgmt-prc-api",
  correlationId: correlationId,
  data: data
}
var base = {
  orderId: vars.orderId,
  externalOrderId: vars.order.externalOrderId,
  customerId: vars.order.customerId,
  status: vars.orderStatus,
  sapOrderNumber: vars.sapOrderNumber,
  lines: vars.allocation.lines map { lineNumber: $.lineNumber, materialNumber: $.materialNumber, reservedQty: $.reservedQty, backorderedQty: $.backorderedQty }
}
var shortages = vars.allocation.lines filter ($.backorderedQty > 0)
var statusEvent = vars.orderStatus match {
  case "PENDING_ERP" -> "order.erp-pending"
  case "CONFIRMED" -> "order.confirmed"
  else -> "order.backordered"
}
---
[ envelope(statusEvent, base) ]
++ (if (vars.orderStatus != "PENDING_ERP" and !isEmpty(shortages))
      [ envelope("inventory.shortage-detected", base ++ {
          shortages: shortages map { lineNumber: $.lineNumber, materialNumber: $.materialNumber, quantity: $.backorderedQty, unitOfMeasure: $.unitOfMeasure }
        }) ]
    else [])
