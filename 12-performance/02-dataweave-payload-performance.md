# 12.2 — DataWeave Optimisation and Large-Payload Handling

`Advanced` · Builds on [05.6](../05-dataweave/06-large-payloads-streaming.md)

## 1. Performance hierarchy (biggest wins first)

1. **Don't move data you don't need:** project the needed fields early, filter at the source (`$select` in OData, column lists in SQL), and send deltas instead of full snapshots.
2. **Reduce round trips:** bulk APIs, Batch Aggregator, Composite APIs (Salesforce), `divideBy` chunks.
3. **Stream instead of loading:** repeatable file-store streams, DW `streaming=true`, Batch.
4. **Fix the algorithmic complexity:** pre-indexed lookups instead of nested `filter` (O(n·m) → O(n+m)).
5. **Micro-optimise DW:** single pass, avoid repeated `write`/`read`, avoid `lookup()` in loops.

## 2. Measuring before optimising
- Time each transform: log `durationMs` around heavy transforms in PERF environments.
- Watch **heap and GC** during the run (Anypoint Monitoring JVM metrics).
- Reproduce with **production-sized** data. Most DW issues are invisible with 100-row test files.

## 3. Common DW performance fixes (before → after)

**a) Nested lookups**
```dataweave
// BEFORE: O(lines x materials)
payload.lines map (l) -> (vars.materials filter ($.id == l.materialNumber))[0].description
// AFTER: build an index once
var idx = vars.materials groupBy $.id
---
payload.lines map (l) -> idx[l.materialNumber][0].description
```

**b) Multiple passes**
```dataweave
// BEFORE: 3 passes over 200k rows
{ ok: sizeOf(payload filter $.ok), failed: sizeOf(payload filter !$.ok), total: sizeOf(payload) }
// AFTER: one pass
payload reduce (r, acc = { ok: 0, failed: 0, total: 0 }) ->
  { ok: acc.ok + (if (r.ok) 1 else 0), failed: acc.failed + (if (r.ok) 0 else 1), total: acc.total + 1 }
```

**c) Repeated serialisation for logging**
```xml
<!-- BEFORE: serialises the whole payload just to log it -->
<logger level="INFO" message="#[write(payload, 'application/json')]"/>
<!-- AFTER -->
<logger level="INFO" message="#['Order ' ++ vars.orderId ++ ' lines=' ++ sizeOf(payload.lines) as String]"/>
```

**d) Output format choice:** use `output application/java` for intermediate variables that are only used by subsequent DW scripts. That avoids serialise/parse cycles between steps.

## 4. Large-payload architecture decisions

| Scenario | Wrong approach | Right approach |
|----------|----------------|----------------|
| 250 MB inventory CSV | `sftp:read` → `ee:transform` of the whole file → For Each | SFTP stream → Batch Job (blockSize, aggregator) |
| 15 MB ASN with 20k lines → SAP | One giant BAPI call | Split into SAP-sized chunks (e.g. 1,000 lines). Correlate the results |
| Customer drawing/PDF attachments with orders | Base64 in the order JSON through every layer | Store in object storage. Pass a URL/reference (claim-check pattern) |
| Event > 10 MB (MQ limit) | Fails on publish | Claim check: store the payload, publish the reference |

**Claim-check pattern:** store the large payload in object storage or the DB and pass only a key through the integration. Consumers fetch it if they need it. This keeps queues and memory small.

## 5. Mule streaming strategies

| Strategy | Config | Use |
|----------|--------|-----|
| Repeatable file-store (EE default) | `<repeatable-file-store-stream inMemorySize="512" bufferUnit="KB"/>` | Default. Buffers in memory, then spills to disk |
| Repeatable in-memory | `<repeatable-in-memory-stream initialBufferSize="512" maxBufferSize="10" bufferUnit="MB"/>` | Small payloads. Fails if the max is exceeded |
| Non-repeatable | `<non-repeatable-stream/>` | Single read, lowest memory. Beware of a second read |

Set the strategy on the connector operation or source that produces the stream (e.g. `sftp:read`, `http:listener`).

## Interview angle
**Q: "A transform of a 50 MB XML takes 40 s and 3 GB of heap. Ideas?"**
> "First, confirm where the time goes and whether the whole document is needed. Often we need 10% of the fields, so we can project them early or use a streaming XML read with sequential access. Then check the script for multiple passes, nested filters used as lookups, and descendant selectors (`..`) over the whole tree, which are expensive on large XML. If the output is going to SAP, chunk it. If the document must be processed record by record, move it into a Batch Job. I'd measure each change with the same production-sized file."

Next: [12.3 Capacity, backpressure & DR](03-capacity-backpressure-dr.md)
