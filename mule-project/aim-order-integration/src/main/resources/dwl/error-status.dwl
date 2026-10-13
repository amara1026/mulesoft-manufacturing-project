%dw 2.0
import * from dwl::modules::aim::errors
output application/java
---
errorInfo(error).status
