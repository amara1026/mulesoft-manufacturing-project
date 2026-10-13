%dw 2.0
/*
 * BAPIs do not throw on business errors: they return a RETURN table.
 * TYPE E or A = error, W = warning, S/I = success/info. Use *row so a single row is still an array.
 */
output application/java
var resp = payload.BAPI_SALESORDER_CREATEFROMDAT2
var messages = resp.tables.RETURN.*row default []
var errors = messages filter (["E", "A"] contains $.TYPE)
var doc = resp."export".SALESDOCUMENT default ""
---
{
  outcome: if (isEmpty(errors) and !isEmpty(doc)) "CREATED" else "REJECTED",
  salesOrderNumber: if (isEmpty(doc)) null else doc,
  recoveredAfterTimeout: false,
  messages: messages map { severity: $.TYPE, code: ($.ID default "") ++ "-" ++ ($.NUMBER default ""), text: $.MESSAGE }
}
