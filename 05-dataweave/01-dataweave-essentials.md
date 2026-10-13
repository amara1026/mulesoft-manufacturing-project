# 05.1 — DataWeave 2.0 Essentials (with Manufacturing Payloads)

`Essential` · *DataWeave 2.x as shipped with Mule 4.9. A few functions noted below need a minimum DW version.*

## 1. Anatomy of a script

```dataweave
%dw 2.0                                   // version directive
output application/json skipNullOn="everywhere"   // output format + writer properties
import * from dw::core::Strings          // module import
var plantNames = { "1000": "Houston", "2000": "Pune", "3000": "Stuttgart" }
fun lineValue(qty: Number, price: Number): Number = qty * price
---
{
  orderId: payload.orderId,
  plant: plantNames[payload.plant] default "UNKNOWN"
}
```

- Everything **above `---`** is the header: declarations. Everything **below** is the body, a single expression.
- The output format is a **writer** decision. The input format comes from the message's **MIME type**. If the type is wrong, DW reads the input wrongly (e.g. JSON treated as a string). That's the #1 beginner bug.

## 2. Core operators in one manufacturing example

**Input**: a WMS availability response
```json
{
  "warehouse": "DC-US-01",
  "asOf": "2026-10-13T07:55:00Z",
  "items": [
    { "sku": "PMP-CF-200", "onHand": 12, "reserved": 4, "status": "OK" },
    { "sku": "VLV-BL-050", "onHand": 9,  "reserved": 4, "status": "OK" },
    { "sku": "SEAL-MECH-40", "onHand": 0, "reserved": 0, "status": "BLOCKED" }
  ]
}
```

**Script**
```dataweave
%dw 2.0
output application/json
---
{
  location: payload.warehouse,
  snapshotTime: payload.asOf,
  available: payload.items
    filter ($.status == "OK")                      // message filtering
    map (item, idx) -> {                            // transformation
      materialNumber: item.sku,
      availableQty: item.onHand - item.reserved,
      position: idx + 1
    }
    orderBy -$.availableQty,                        // descending
  blockedMaterials: (payload.items filter ($.status == "BLOCKED")).sku,
  totalAvailable: sum(payload.items filter ($.status == "OK") map ($.onHand - $.reserved))
}
```

**Output**
```json
{
  "location": "DC-US-01",
  "snapshotTime": "2026-10-13T07:55:00Z",
  "available": [
    { "materialNumber": "PMP-CF-200", "availableQty": 8, "position": 1 },
    { "materialNumber": "VLV-BL-050", "availableQty": 5, "position": 2 }
  ],
  "blockedMaterials": [ "SEAL-MECH-40" ],
  "totalAvailable": 13
}
```

**Explanation**
- `filter`, `map` and `orderBy` chain left to right. `$` is the current item and `$$` is the index (or key).
- `(array).sku` is a **multi-value selector** on an array. It returns `["SEAL-MECH-40"]`.
- `orderBy -$.availableQty` sorts in descending order for numbers. For strings, use `orderBy $.x` then `[-1 to 0]` to reverse.
- `position: idx + 1`: the index comes from the second lambda parameter.

## 3. Selectors cheat-sheet

| Selector | Example | Result |
|----------|---------|--------|
| Single value | `payload.warehouse` | `"DC-US-01"` |
| Multi-value on array | `payload.items.sku` | array of skus |
| Descendants | `payload..sku` | every `sku` at any depth |
| Index / range | `payload.items[0]`, `payload.items[-1]`, `payload.items[0 to 1]` | first, last, slice |
| Dynamic key | `payload[vars.fieldName]` | value at runtime key |
| Key-value pairs | `payload.items[0] pluck $$` | `["sku","onHand",...]` |
| Existence | `payload.items[0].lotNumber?` | `false` |
| XML attribute | `payload.order.@id` | attribute value |
| XML repeated elements | `payload.order.*item` | **all** `item` elements (without `*` you get only the first) |
| Namespace | `ns sap http://sap.com/xi` then `payload.sap#Order` | |

## 4. Objects: `mapObject`, `pluck`, `filterObject`, `update`

```dataweave
%dw 2.0
output application/json
var stockByDc = { "DC-US-01": 8, "DC-IN-01": 0, "DC-EU-01": 21 }
---
{
  // object -> object
  flagged: stockByDc mapObject (qty, dc) -> { (dc): if (qty == 0) "OUT" else "IN" },
  // object -> array
  asRows: stockByDc pluck (qty, dc) -> { location: dc as String, qty: qty },
  // keep only DCs with stock
  inStock: stockByDc filterObject (qty) -> qty > 0,
  // targeted change without rebuilding the object (DW 2.3+)
  corrected: { orderId: "ORD-1", status: "NEW", lines: 2 } update {
    case .status -> "VALIDATED"
  }
}
```

Note: `dc` is a **Key** type in `mapObject`/`pluck`. Use `as String` when you need a string value.

## 5. Conditional logic and pattern matching

```dataweave
%dw 2.0
output application/json
fun deliveryPriority(order) =
  order.customerTier match {
    case "PLATINUM" -> "P1"
    case tier if (order.totalValue > 100000) -> "P1"
    case "GOLD" -> "P2"
    else -> "P3"
  }
fun lineType(materialNumber: String) =
  materialNumber match {
    case m if (m startsWith "PMP-") -> "FINISHED_GOOD"
    case m matches /^(MTR|CSG|SEAL)-.*/ -> "COMPONENT"
    else -> "OTHER"
  }
---
{
  priority: deliveryPriority({ customerTier: "SILVER", totalValue: 250000 }),
  types: ["PMP-CF-200", "SEAL-MECH-40", "XYZ"] map lineType($)
}
```
Output: `{ "priority": "P1", "types": ["FINISHED_GOOD", "COMPONENT", "OTHER"] }`

## 6. Variables, functions, `do` scopes and modules

```dataweave
%dw 2.0
output application/json
fun toSapQty(q: Number): String = q as String { format: "0.000" }
---
payload.lines map (line) -> do {
  var qty = line.quantity default 0
  var isBulk = qty >= 100
  ---
  {
    item: line.lineNumber,
    qty: toSapQty(qty),
    shippingClass: if (isBulk) "PALLET" else "PARCEL"
  }
}
```

**Reusable modules:** put shared functions in `src/main/resources/dwl/modules/aim/common.dwl` and import them with `import * from dwl::modules::aim::common` (the path follows the folder structure, using `::`). Every app then formats SAP dates identically. Better still, publish the module in a shared **DataWeave library** (Exchange) or a common Mule plugin.

## 7. Error-safe DataWeave

```dataweave
%dw 2.0
import try, orElse from dw::Runtime
output application/json
---
{
  // safe number parse: returns 0 when the supplier sends "N/A"
  qty: try(() -> "N/A" as Number) orElse 0,
  // explicit failure with a clear message (raises an error that Mule can handle)
  plant: if (payload.plant?) payload.plant else fail("Missing plant in WMS message")
}
```
`orElse` / `orElseTry` require DataWeave 2.4+ (Mule 4.4+). On older runtimes, use `try(...)` and check `.success`.

## 8. Calling Mule from DataWeave
- `p('sap.salesOrg')` reads a configuration property.
- `lookup('get-plant-for-dc', { dc: "DC-US-01" })` calls a **flow** (not a sub-flow) and returns its payload. It's handy, but it's hidden I/O inside a transform. Prefer explicit flow steps for anything slow.
- `readUrl("classpath://dwl/lookups/uom.json", "application/json")` loads static lookup tables.

## Common mistakes (interview checklist)
1. Missing or incorrect MIME type, so the payload is read as a String or Binary.
2. Using `payload.order.item` on XML with repeated items and getting **only the first**. Use `*item`.
3. Floating-point money (`0.1 + 0.2`): keep amounts as strings or decimals and format at the edges.
4. Referencing `payload` several times on a **stream** that is not repeatable, so the second read is empty.
5. Putting business rules in DW scattered across 20 transforms instead of functions in modules.

Next: [05.2 JSON ↔ XML and SAP mapping](02-json-xml-and-sap-mapping.md)
