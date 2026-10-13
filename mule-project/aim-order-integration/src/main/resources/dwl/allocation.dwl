%dw 2.0
/*
 * Input: scatter-gather result (route "1" = WMS System API availability).
 * Output: per-line allocation (reserved vs backordered) + overall status.
 * Index availability once (groupBy) instead of filtering inside the loop.
 */
output application/java
var availability = (payload."1".payload.lines default []) groupBy $.materialNumber
var lines = vars.order.lines map (l) -> do {
  var hit = availability[l.materialNumber][0]
  var requested = l.quantity as Number
  var available = (hit.availableQty default 0) as Number
  var reservable = min([requested, available])
  ---
  {
    lineNumber: l.lineNumber,
    materialNumber: l.materialNumber,
    unitOfMeasure: l.unitOfMeasure,
    requested: requested,
    reservedQty: reservable,
    backorderedQty: requested - reservable,
    known: (hit.known default false) as Boolean
  }
}
---
{
  lines: lines,
  status: if (isEmpty(lines filter ($.backorderedQty > 0))) "FULL"
          else if (!isEmpty(lines filter ($.reservedQty > 0))) "PARTIAL"
          else "NONE",
  unknownMaterials: (lines filter (not $.known)).materialNumber default []
}
