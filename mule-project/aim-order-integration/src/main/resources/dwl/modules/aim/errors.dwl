%dw 2.0
/**
 * Single source of truth: Mule error type -> HTTP status + AIM error code.
 * Mirrors the error-code catalogue (04.3 / 16.2 in the study kit).
 */
var catalogue = {
  "AIM:BAD_REQUEST":               { status: 400, code: "AIM-ORD-4001" },
  "APIKIT:BAD_REQUEST":            { status: 400, code: "AIM-ORD-4001" },
  "APIKIT:NOT_FOUND":              { status: 404, code: "AIM-GEN-4041" },
  "AIM:ORDER_NOT_FOUND":           { status: 404, code: "AIM-ORD-4041" },
  "AIM:DEAD_LETTER_NOT_FOUND":     { status: 404, code: "AIM-OPS-4041" },
  "APIKIT:METHOD_NOT_ALLOWED":     { status: 405, code: "AIM-GEN-4051" },
  "APIKIT:NOT_ACCEPTABLE":         { status: 406, code: "AIM-GEN-4061" },
  "APIKIT:UNSUPPORTED_MEDIA_TYPE": { status: 415, code: "AIM-GEN-4151" },
  "APIKIT:NOT_IMPLEMENTED":        { status: 501, code: "AIM-GEN-5011" },
  "AIM:DUPLICATE_IN_PROGRESS":     { status: 409, code: "AIM-ORD-4091" },
  "AIM:CONCURRENT_UPDATE":         { status: 409, code: "AIM-ORD-4092" },
  "AIM:IDEMPOTENCY_KEY_REUSED":    { status: 422, code: "AIM-ORD-4221" },
  "AIM:CUSTOMER_INVALID":          { status: 422, code: "AIM-ORD-4223" },
  "AIM:MATERIAL_INVALID":          { status: 422, code: "AIM-ORD-4224" },
  "AIM:SAP_BUSINESS_ERROR":        { status: 422, code: "AIM-SAP-4225" },
  "AIM:SAP_UNAVAILABLE":           { status: 503, code: "AIM-SAP-5031" },
  "HTTP:CONNECTIVITY":             { status: 503, code: "AIM-DEP-5031" },
  "HTTP:SERVICE_UNAVAILABLE":      { status: 503, code: "AIM-DEP-5031" },
  "HTTP:TIMEOUT":                  { status: 504, code: "AIM-DEP-5041" },
  "MULE:COMPOSITE_ROUTING":        { status: 502, code: "AIM-DEP-5021" }
}

fun errorKey(e) = (e.errorType.namespace default "MULE") ++ ":" ++ (e.errorType.identifier default "UNKNOWN")

fun errorInfo(e) =
  catalogue[errorKey(e)] default (
    if ((e.errorType.namespace default "") == "HTTP") { status: 502, code: "AIM-DEP-5021" }
    else { status: 500, code: "AIM-GEN-5001" }
  )
