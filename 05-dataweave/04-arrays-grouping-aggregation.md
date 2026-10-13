# 05.4 — Nested Arrays, Filtering, Grouping, Flattening & Aggregation

`Essential`

## Example 1 — Aggregate inventory across warehouses (groupBy + sum)

**Input**: availability lines from 3 DCs (WMS + SAP ATP merged)
```json
[
  { "dc": "DC-US-01", "materialNumber": "PMP-CF-200", "onHand": 12, "reserved": 4 },
  { "dc": "DC-EU-01", "materialNumber": "PMP-CF-200", "onHand": 6,  "reserved": 0 },
  { "dc": "DC-US-01", "materialNumber": "VLV-BL-050", "onHand": 9,  "reserved": 4 },
  { "dc": "DC-IN-01", "materialNumber": "VLV-BL-050", "onHand": 30, "reserved": 30 },
  { "dc": "DC-EU-01", "materialNumber": "VLV-BL-050", "onHand": 3,  "reserved": 1 }
]
```

**Script**
```dataweave
%dw 2.0
output application/json
---
(payload groupBy $.materialNumber) pluck (rows, material) -> {
  materialNumber: material as String,
  totalAvailable: sum(rows map ($.onHand - $.reserved)),
  locations: rows
    filter (($.onHand - $.reserved) > 0)
    map { dc: $.dc, available: $.onHand - $.reserved }
    orderBy -$.available
}
```

**Output**
```json
[
  { "materialNumber": "PMP-CF-200", "totalAvailable": 14,
    "locations": [ { "dc": "DC-US-01", "available": 8 }, { "dc": "DC-EU-01", "available": 6 } ] },
  { "materialNumber": "VLV-BL-050", "totalAvailable": 7,
    "locations": [ { "dc": "DC-US-01", "available": 5 }, { "dc": "DC-EU-01", "available": 2 } ] }
]
```

`groupBy` returns an **object** (`{ "PMP-CF-200": [...], ... }`), and `pluck` turns it back into an array. `DC-IN-01` disappears for valves because its available quantity is 0.

## Example 2 — Shortage calculation: match order lines to availability (join)

```dataweave
%dw 2.0
output application/json
import leftJoin from dw::core::Arrays
var order = [
  { "lineNumber": 10, "materialNumber": "PMP-CF-200", "quantity": 5 },
  { "lineNumber": 20, "materialNumber": "VLV-BL-050", "quantity": 40 },
  { "lineNumber": 30, "materialNumber": "CSG-SS-200", "quantity": 2 }
]
var avail = [
  { "materialNumber": "PMP-CF-200", "totalAvailable": 14 },
  { "materialNumber": "VLV-BL-050", "totalAvailable": 7 }
]
---
leftJoin(order, avail, (o) -> o.materialNumber, (a) -> a.materialNumber) map (j) -> do {
  var available = j.r.totalAvailable default 0
  var reservable = min([j.l.quantity, available])
  ---
  {
    lineNumber: j.l.lineNumber,
    materialNumber: j.l.materialNumber,
    requested: j.l.quantity,
    reservable: reservable,
    shortage: j.l.quantity - reservable,
    status: if (reservable == j.l.quantity) "FULL"
            else if (reservable > 0) "PARTIAL" else "NONE"
  }
}
```

**Output**
```json
[
  { "lineNumber": 10, "materialNumber": "PMP-CF-200", "requested": 5,  "reservable": 5, "shortage": 0,  "status": "FULL" },
  { "lineNumber": 20, "materialNumber": "VLV-BL-050", "requested": 40, "reservable": 7, "shortage": 33, "status": "PARTIAL" },
  { "lineNumber": 30, "materialNumber": "CSG-SS-200", "requested": 2,  "reservable": 0, "shortage": 2,  "status": "NONE" }
]
```

- `leftJoin` (from `dw::core::Arrays`) keeps every order line, even those with no availability record. Each element is `{ l: ..., r: ... }`, and `r` is missing when there's no match.
- This is a **pure function**: easy to unit test in MUnit with many cases. Put it in a module.

> In a real system, the same material appearing on **two lines** must share the availability (allocation). That is a reduce, shown next.

## Example 3 — Allocation across lines with `reduce` (stateful iteration)

```dataweave
%dw 2.0
output application/json
var lines = [
  { "lineNumber": 10, "materialNumber": "VLV-BL-050", "quantity": 4 },
  { "lineNumber": 20, "materialNumber": "VLV-BL-050", "quantity": 6 }
]
var available = { "VLV-BL-050": 7 }
---
(lines reduce (line, acc = { remaining: available, result: [] }) -> do {
  var left = acc.remaining[line.materialNumber] default 0
  var alloc = min([line.quantity, left])
  ---
  {
    remaining: acc.remaining mapObject (v, k) ->
      { (k): if ((k as String) == line.materialNumber) v - alloc else v },
    result: acc.result << { lineNumber: line.lineNumber, allocated: alloc, shortage: line.quantity - alloc }
  }
}).result
```
**Output:** `[{"lineNumber":10,"allocated":4,"shortage":0},{"lineNumber":20,"allocated":3,"shortage":3}]`

`reduce` carries an accumulator. Here it holds both the *remaining stock* and the *results*. `<<` appends to an array.

## Example 4 — Flattening nested shipments → handling units → items

**Input**
```json
{ "deliveryNumber": "80001234", "handlingUnits": [
  { "huId": "HU-001", "items": [ { "material": "PMP-CF-200", "qty": 2 }, { "material": "SEAL-MECH-40", "qty": 4 } ] },
  { "huId": "HU-002", "items": [ { "material": "PMP-CF-200", "qty": 3 } ] } ] }
```

```dataweave
%dw 2.0
output application/json
---
{
  deliveryNumber: payload.deliveryNumber,
  packingList: payload.handlingUnits flatMap (hu) ->
    hu.items map (it) -> { huId: hu.huId, material: it.material, qty: it.qty },
  totalsByMaterial: flatten(payload.handlingUnits.items)
    groupBy $.material
    mapObject (items, m) -> { (m): sum(items.qty) },
  huCount: sizeOf(payload.handlingUnits)
}
```

**Output**
```json
{
  "deliveryNumber": "80001234",
  "packingList": [
    { "huId": "HU-001", "material": "PMP-CF-200", "qty": 2 },
    { "huId": "HU-001", "material": "SEAL-MECH-40", "qty": 4 },
    { "huId": "HU-002", "material": "PMP-CF-200", "qty": 3 }
  ],
  "totalsByMaterial": { "PMP-CF-200": 5, "SEAL-MECH-40": 4 },
  "huCount": 2
}
```

- `flatMap` = `map` then `flatten`. It keeps the parent context (`hu.huId`) available while iterating children.
- `payload.handlingUnits.items` is an array of arrays, so `flatten` makes it one list.

## Example 5 — Deduplicate and detect duplicates in a batch

```dataweave
%dw 2.0
output application/json
var events = [
  { "eventId": "E1", "prodOrder": "1000234", "seq": 1 },
  { "eventId": "E2", "prodOrder": "1000234", "seq": 2 },
  { "eventId": "E1", "prodOrder": "1000234", "seq": 1 }
]
---
{
  unique: events distinctBy $.eventId,
  duplicates: (events groupBy $.eventId) filterObject (sizeOf($) > 1) pluck $$,
  lastSeqPerOrder: (events groupBy $.prodOrder) mapObject (v, k) -> { (k): max(v.seq) }
}
```
**Output:** `unique` holds the E1 and E2 events (the repeated E1 is dropped), `duplicates` is `["E1"]`, and `lastSeqPerOrder` is `{"1000234": 2}`.

## Function quick reference

| Need | Function |
|------|----------|
| Keep matching | `filter`, `filterObject` |
| Transform each | `map`, `mapObject` |
| Object → array | `pluck` |
| Group | `groupBy` (returns object) |
| Flatten | `flatten`, `flatMap` |
| Aggregate | `sum`, `max`, `min`, `avg`, `sizeOf`, `reduce`, `dw::core::Arrays::sumBy`, `countBy` |
| Unique | `distinctBy` |
| Join | `dw::core::Arrays::join`, `leftJoin`, `outerJoin` |
| Split into chunks | `dw::core::Arrays::divideBy` (e.g. 1000-row SAP bulk calls) |
| Any / all | `dw::core::Arrays::some`, `every` |

Next: [05.5 Dates, currency, UoM and null handling](05-dates-currency-uom-nulls.md)
