# 05.6 — Large Payloads, Streaming and DataWeave Performance

`Advanced` (but frequently asked in senior interviews)

## 1. Why large payloads hurt

A 250 MB WMS inventory CSV with 2M rows becomes **several times larger in memory** once parsed into an object model, because each value is an object with overhead. Ten concurrent requests like that will exhaust a 1-vCore replica's heap, causing an `OutOfMemoryError` or long GC pauses. The usual symptom is an app that restarts at 01:20 every night.

## 2. How Mule and DataWeave handle streams

| Concept | What it means | Default |
|---------|---------------|---------|
| **Repeatable streams** | Mule buffers the stream so it can be read multiple times (in memory up to a limit, then on disk for file-store) | Repeatable **file-store** in EE (in-memory buffer, then a temp file) |
| **Non-repeatable stream** | Read once only. Lowest memory | Must be configured explicitly |
| **DW reader `streaming=true`** | DW parses lazily and can process elements one at a time (JSON, XML, CSV) | Off |
| **DW writer `deferred=true`** | DW does not build the whole output first. It streams it to the next processor | Off |
| **Batch Job** | Splits records and stores them in persistent queues, so memory is bounded regardless of file size | — |

## 3. A streaming-friendly transform (CSV → JSON lines to SAP)

```dataweave
%dw 2.0
@StreamCapable()
input payload application/csv streaming=true, header=true, separator=";"
output application/json deferred=true
---
payload map (r) -> {
  materialNumber: r.material,
  plant: r.plant,
  storageLocation: r.sloc,
  qty: r.qty as Number
}
```

**Rules for streaming to actually work**
1. **Reference `payload` only once**, and access it sequentially. `sizeOf(payload)`, `groupBy`, `orderBy` and indexing `payload[-1]` all force DW to load the whole input.
2. `@StreamCapable()` makes DW **fail at compile time** if the script isn't stream-compatible. This is a safety net.
3. The input must actually be a stream (SFTP read, HTTP body). If an earlier processor already turned it into a Java object, there's nothing to stream.

## 4. Choosing the right tool for size

| Payload | Approach |
|---------|----------|
| < 1 MB (typical API) | Normal DW. Optimise for readability |
| 1–50 MB (big order, large ASN) | DW with care: avoid multiple passes. Possibly `streaming=true` |
| 50 MB – GBs (inventory snapshot) | **Batch Job** (records persisted, block-wise) or **For Each with streaming** + `divideBy` chunks |
| Continuous high-volume events | Don't use files. Use events (MQ/Kafka) with small messages |

## 5. Performance anti-patterns and fixes

| Anti-pattern | Why it's slow | Fix |
|--------------|---------------|-----|
| `payload filter (...) map (...)` repeated 5 times in the same script over the same 100k array | 5 full passes | Compute once into a `var`, or combine logic in one `map` |
| Lookup inside a loop with `filter`: `lines map (l) -> (materials filter ($.id == l.id))[0]` | O(n × m) | Build an **index object** once: `var idx = materials groupBy $.id`, then `idx[l.id][0]` (O(1) lookups) |
| `lookup()` (flow call) inside `map` | One flow execution per element, hidden I/O | Fetch all reference data before the transform |
| String concatenation to build XML/CSV | Error-prone and slow | Let DW writers do it (`output application/xml`) |
| Logging the whole payload (`#[payload]`) at INFO | Forces stream consumption and serialisation, plus PII leak | Log IDs and counts only |
| `write(payload, "application/json")` to compute size for logging | Full serialisation | Use attributes such as `Content-Length` if available |

**Example of the index fix:**
```dataweave
%dw 2.0
output application/json
var materialIndex = vars.materials groupBy $.materialNumber   // built once
---
payload.lines map (l) -> {
  lineNumber: l.lineNumber,
  description: materialIndex[l.materialNumber][0].description default "UNKNOWN",
  procurementType: materialIndex[l.materialNumber][0].procurementType default "BUY"
}
```
With 10k lines and 50k materials, this goes from ~500M comparisons to ~60k operations.

## 6. Memory-safe chunking for API calls (For Each + divideBy)

```xml
<!-- send 1000 records per SAP call instead of 1 or 2M -->
<foreach collection="#[dw::core::Arrays::divideBy(payload, 1000)]" doc:name="For each 1000-record chunk">
    <http:request method="POST" config-ref="SAP_Sys_API" path="/inventory/bulk-adjustments"
                  responseTimeout="30000" doc:name="Send chunk to SAP Sys API"/>
</foreach>
```
`divideBy` over a fully loaded 2M-row array still needs memory. For truly big data, use a **Batch Job with a Batch Aggregator** (size 1000), which reads records from its persistent queue ([06.7](../06-mule-implementation/07-scheduler-batch-sftp.md)).

## 7. Troubleshooting a DataWeave memory problem (method)
1. **Symptom:** heap climbs during the transform, GC pauses, `OutOfMemoryError`, replica restarts. Check Anypoint Monitoring JVM metrics (heap, GC time) around the incident.
2. **Reproduce** locally with a production-sized file. Use a heap dump (`-XX:+HeapDumpOnOutOfMemoryError`) and VisualVM, or Studio's profiler.
3. **Find the full-load trigger:** `groupBy`, `orderBy`, `sizeOf`, multiple `payload` references, or `write()` for logging.
4. **Fix:** stream, move to Batch, pre-index lookups, reduce payload fields early (*project* only the needed fields first).
5. **Prevent:** a performance test with a 2× production-size file in the pipeline, plus an alert on heap > 80% for 5 minutes.

(Full incident walkthrough: [13 scenario 6](../13-production-troubleshooting/02-scenarios-06-10.md).)

## Interview angle
**Q: "A DataWeave transform works in test but crashes production nightly. How do you approach it?"**
> "I check whether production data is simply bigger. Test files are often 1,000 rows and production files 2 million. I look at heap and GC metrics at the failure time, reproduce locally with a production-sized file and a heap dump, and inspect the script for operations that defeat streaming, like groupBy, sizeOf or multiple payload references. The fix is usually to restructure: stream the read, move the bulk processing into a Batch Job with an aggregator, and pre-index lookups. Then I add a load test with production-sized data to the pipeline so the same thing can't regress."

Next section: [06 — Mule implementation](../06-mule-implementation/01-dev-setup-and-repo.md)
