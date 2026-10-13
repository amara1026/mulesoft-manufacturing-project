# 05.5 — Dates, Time Zones, Currency, Units of Measure & Null Handling

`Essential`

A global manufacturer works across time zones, currencies and units every day. Mistakes here cost real money: a wrong delivery day, a cent-level rounding difference that breaks invoice matching, or 1000× too many kilograms.

## 1. Dates and time zones

**Rules AIM follows**
- **Business dates** (requested delivery date, posting date) use `Date`, with no time zone. **Event times** use `DateTime` in UTC.
- Convert to plant-local time only when a downstream system demands it (SAP often expects local date and time fields).

```dataweave
%dw 2.0
output application/json
var eventUtc = |2026-10-13T22:30:00Z|
---
{
  // UTC -> plant local time (shift zone, same instant)
  houstonLocal: eventUtc >> "America/Chicago",            // 2026-10-13T17:30:00-05:00
  puneLocal:    eventUtc >> "Asia/Kolkata",               // 2026-10-14T04:00:00+05:30  (next day!)

  // SAP date/time fields (separate DATS / TIMS)
  sapPostingDate: (eventUtc >> "Asia/Kolkata") as String { format: "yyyyMMdd" },  // 20261014
  sapPostingTime: (eventUtc >> "Asia/Kolkata") as String { format: "HHmmss" },    // 040000

  // Parse SAP date + time into an ISO DateTime in plant zone, then to UTC
  fromSap: (("20261014" ++ "040000") as LocalDateTime { format: "yyyyMMddHHmmss" }
             ++ |+05:30|) >> "UTC",

  // Date arithmetic: promise date = today + lead time (days)
  promiseDate: |2026-10-13| + |P10D|,                      // 2026-10-23
  // Days between dates
  daysLate: (|2026-10-23| - |2026-10-20|).days             // 3
}
```

**Real scenario:** A goods receipt posted at 22:30 UTC in Pune belongs to **14 Oct** locally. If you send `20261013` to SAP, the receipt lands in the wrong day. At month-end that means the **wrong fiscal period**. Finance will notice.

> `LocalDateTime ++ TimeZone` produces a `DateTime`. `>>` shifts to another zone while keeping the same instant.

## 2. Currency and money

```dataweave
%dw 2.0
output application/json
var fx = { "EUR": 1.0712, "INR": 0.01198 }   // to USD, from a rates service (cached daily)
fun toUsd(amount: Number, ccy: String): Number =
  if (ccy == "USD") amount else amount * (fx[ccy] default fail("No FX rate for " ++ ccy))
fun money(n: Number): String = n as String { format: "0.00", roundMode: "HALF_EVEN" }
---
{
  lineValues: payload.lines map {
    lineNumber: $.lineNumber,
    netValue: money($.quantity * $.unitPrice),
    netValueUsd: money(toUsd($.quantity * $.unitPrice, payload.currency))
  },
  orderTotal: money(sum(payload.lines map ($.quantity * $.unitPrice))),
  display: (12345.5 as String { format: "#,##0.00" })     // "12,345.50"
}
```

**Input:** `{"currency":"EUR","lines":[{"lineNumber":10,"quantity":3,"unitPrice":1999.995}]}`
**Output:** `{"lineValues":[{"lineNumber":10,"netValue":"5999.98","netValueUsd":"6427.18"}],"orderTotal":"5999.98","display":"12,345.50"}`

**Explanation and caveats**
- Return money as **strings with fixed scale**, never as floating-point numbers that consumers re-parse.
- **Rounding mode matters:** SAP and invoicing systems usually round half-up per line, while some tax rules use banker's rounding (`HALF_EVEN`). Agree the rule with finance and apply it in **one** function. The `roundMode` format property is available in recent DataWeave versions (2.4+). Verify it on your runtime.
- **Round per line, then sum** vs **sum, then round** gives different totals. SAP pricing rounds per condition per line. Match SAP, or your reconciliation will show 1-cent differences forever.
- **Never compute final prices in Mule.** SAP pricing is the source of truth. These conversions are for **display and analytics**.

## 3. Units of measure (UoM)

Suppliers ship valves in **boxes of 10**, SAP stocks them in **EA**, and the WMS counts **cases**. Conversion factors come from the **SAP material master** (alternative UoMs, table MARM). They are never hard-coded per material.

```dataweave
%dw 2.0
output application/json
// factors loaded from SAP material master (cached), per material: alternative UoM -> base UoM
var uomFactors = {
  "VLV-BL-050": { base: "EA", alt: { "BOX": 10, "PAL": 400 } },
  "SEAL-MECH-40": { base: "EA", alt: { "BAG": 25 } },
  "CSG-SS-200": { base: "KG", alt: { "G": 0.001, "T": 1000 } }
}
fun toBase(material: String, qty: Number, uom: String) = do {
  var m = uomFactors[material]
  ---
  if (m == null) fail("No UoM master data for " ++ material)
  else if (uom == m.base) { qty: qty, uom: m.base }
  else if (m.alt[uom]?) { qty: qty * m.alt[uom], uom: m.base }
  else fail("Unsupported UoM " ++ uom ++ " for " ++ material)
}
---
payload.asnLines map (l) -> {
  material: l.material,
  received: toBase(l.material, l.qty, l.uom)
}
```
**Input:** `{"asnLines":[{"material":"VLV-BL-050","qty":4,"uom":"BOX"},{"material":"CSG-SS-200","qty":250,"uom":"G"}]}`
**Output:** `[{"material":"VLV-BL-050","received":{"qty":40,"uom":"EA"}},{"material":"CSG-SS-200","received":{"qty":0.25,"uom":"KG"}}]`

**Why `fail()` rather than a default:** silently defaulting the factor to 1 turns "4 boxes" into "4 each", so stock is wrong by 36 valves and nobody notices. Fail loudly, route to the DLQ and alert master data.

## 4. Null and missing-field handling

| Situation | Technique | Example |
|-----------|-----------|---------|
| Field might be missing or null | `default` | `payload.uom default "EA"` |
| Check existence (key present at all) | `?` | `if (payload.lotNumber?) ...` |
| Empty string, empty array or null | `isEmpty()` | `if (isEmpty(r.ship_date)) null else ...` |
| Don't output null fields | `skipNullOn="everywhere"` | `output application/json skipNullOn="everywhere"` |
| Include a key only if a condition holds | conditional element | `(lotNumber: payload.lot) if (payload.lot != null)` |
| Safe navigation | selectors are null-safe | `payload.a.b.c` returns `null` (not an error) if `a` is missing |
| Coercion of null | guard first | `payload.qty as Number` **fails** on null, so use `(payload.qty default 0) as Number` |

```dataweave
%dw 2.0
output application/json skipNullOn="everywhere"
---
payload.items map (i) -> {
  materialNumber: i.material,
  batch: i.batch,                                   // omitted when null
  qty: (i.qty default 0) as Number,
  (serialNumbers: i.serials) if (!isEmpty(i.serials)),
  expiryDate: if (isEmpty(i.expiry) or i.expiry == "00000000") null
              else i.expiry as Date { format: "yyyyMMdd" }
}
```

**Interview question:** *"What is the difference between `default` and `skipNullOn`?"*
> "`default` replaces a null or missing value **with a value** at the moment it is read. `skipNullOn` is a **writer** property: it drops fields whose final value is null from the output. I use `default` when the business defined a fallback, and `skipNullOn` when consumers prefer an absent field to `null`. I also check that this convention is written into the API contract, because some consumers treat 'absent' and 'null' differently in PATCH semantics."

Next: [05.6 Large payloads & streaming](06-large-payloads-streaming.md)
