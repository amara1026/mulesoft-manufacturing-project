%dw 2.0
import * from dwl::modules::aim::errors
import isoNow from dwl::modules::aim::common
output application/json
var info = errorInfo(error)
---
{
  error: {
    code: info.code,
    // Hide internals on 5xx: clients get a correlation ID, details stay in the logs
    message: if (info.status >= 500) "The request could not be completed. Quote the correlationId when contacting support."
             else (error.description default "Request failed"),
    correlationId: correlationId,
    timestamp: isoNow()
  }
}
