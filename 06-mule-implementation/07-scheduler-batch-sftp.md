# 06.7 — Scheduler, SFTP and Batch Job (Nightly Inventory Synchronisation)

`Essential`

## 1. Scheduler

```xml
<flow name="inventory-snapshot-poll-flow" maxConcurrency="1">
    <scheduler doc:name="Every night 01:15 plant time">
        <scheduling-strategy>
            <cron expression="0 15 1 * * ?" timeZone="America/Chicago"/>
        </scheduling-strategy>
    </scheduler>
    <flow-ref name="process-inventory-file-flow"/>
</flow>
```

- `maxConcurrency="1"` prevents a second run from starting while the first is still processing.
- **Clustered/multi-replica behaviour:** in a Mule **cluster** (on-prem cluster or CloudHub 2.0 with clustering enabled), schedulers run **on the primary node only**. On multiple replicas **without** clustering, *each replica runs the scheduler*, which gives duplicate processing. Mitigate it with clustering, a single replica for batch apps, or a **DB lock** (`SELECT ... FOR UPDATE SKIP LOCKED` / advisory lock).
- Set the time zone explicitly. The cron default is the server's zone (UTC on CloudHub).

## 2. SFTP: read safely

```xml
<sftp:config name="SFTP_WMS_Config">
    <sftp:connection host="${sftp.host}" port="22" username="${sftp.user}"
                     identityFile="${sftp.keyPath}" passphrase="${secure::sftp.passphrase}"
                     workingDir="/inbound/inventory"/>
</sftp:config>

<flow name="inventory-file-listener-flow">
    <sftp:listener config-ref="SFTP_WMS_Config" directory="/inbound/inventory"
                   autoDelete="false" moveToDirectory="/inbound/inventory/processing"
                   timeBetweenSizeCheck="10" timeBetweenSizeCheckUnit="SECONDS"
                   outputMimeType="application/csv; header=true; separator=;" doc:name="New inventory file">
        <scheduling-strategy><fixed-frequency frequency="5" timeUnit="MINUTES"/></scheduling-strategy>
        <sftp:matcher filenamePattern="inventory_snapshot_*.csv"/>
    </sftp:listener>
    <flow-ref name="register-file-and-check-duplicate-subflow" doc:name="Skip if file already processed"/>
    <batch:execute jobName="inventory-sync-batch" doc:name="Run batch"/>
</flow>
```

**Why each setting matters**
- **`timeBetweenSizeCheck`:** the listener waits until the file size stops changing, so it doesn't read a half-written file. A **`.done` marker** from the producer is even safer.
- **`moveToDirectory`:** moves the file out of the polling directory so the next poll doesn't pick it up again. Final archive/error moves happen in On Complete.
- **Key-based auth** (`identityFile`) instead of passwords. Pin the server's **host key** (known hosts) to prevent MITM.
- **Duplicate-file protection:** register `fileName + checksum` in the DB. The same file re-uploaded by mistake is skipped and an alert is raised.

## 3. Batch Job — full example

```xml
<batch:job jobName="inventory-sync-batch" blockSize="500" maxConcurrency="8"
           maxFailedRecords="20000" doc:name="Inventory sync batch">
    <batch:process-records>

        <batch:step name="validate-and-map">
            <ee:transform doc:name="WMS row -> canonical">
                <ee:message><ee:set-payload><![CDATA[%dw 2.0
output application/java
---
{
  materialNumber: payload.material,
  plant: payload.plant,
  storageLocation: payload.sloc,
  qty: payload.qty as Number,
  uom: payload.uom
}]]></ee:set-payload></ee:message>
            </ee:transform>
            <validation:is-true expression="#[payload.qty >= 0]" message="Negative stock" doc:name="Qty not negative"/>
        </batch:step>

        <batch:step name="send-deltas-to-sap" acceptPolicy="NO_FAILURES">
            <batch:aggregator size="1000" doc:name="1000 records per SAP call">
                <http:request method="POST" config-ref="HTTP_Request_SAP_Sys_Config"
                              path="/sys/sap/v1/inventory/comparisons" responseTimeout="30000"
                              doc:name="Bulk compare and post deltas">
                    <http:body>#[output application/json --- payload]</http:body>
                </http:request>
            </batch:aggregator>
        </batch:step>

        <batch:step name="capture-failures" acceptPolicy="ONLY_FAILURES">
            <batch:aggregator size="500" doc:name="Write failed rows">
                <db:bulk-insert config-ref="DB_Config" doc:name="Insert failed records">
                    <db:sql><![CDATA[INSERT INTO batch_failure (job_id, material, plant, reason)
                                     VALUES (:jobId, :material, :plant, :reason)]]></db:sql>
                    <db:bulk-input-parameters><![CDATA[#[payload map {
                        jobId: vars.batchJobInstanceId default "n/a",
                        material: $.materialNumber default "?",
                        plant: $.plant default "?",
                        reason: "validation or SAP failure"
                    }]]]></db:bulk-input-parameters>
                </db:bulk-insert>
            </batch:aggregator>
        </batch:step>
    </batch:process-records>

    <batch:on-complete>
        <logger level="INFO" category="aim.batch" message="#[output application/json --- {
            job: 'inventory-sync', total: payload.totalRecords, ok: payload.successfulRecords,
            failed: payload.failedRecords, elapsedMs: payload.elapsedTimeInMillis }]"/>
        <!-- publish completion event, move file to /archive or /error depending on failedRecords -->
    </batch:on-complete>
</batch:job>
```

### How Batch works (what interviewers probe)
1. **Load and dispatch phase:** the input is split into records, which are stored in **persistent queues** (disk), so memory is bounded.
2. **Process phase:** records move through steps in **blocks** (`blockSize`). Blocks are processed by up to `maxConcurrency` threads. Within a block, records go through a step sequentially.
3. **Step acceptance:** `acceptPolicy` = `NO_FAILURES` (default), `ONLY_FAILURES`, or `ALL`. `acceptExpression` filters records per step.
4. **Failures:** a record that fails in a step is marked failed and skips later `NO_FAILURES` steps. When failures exceed `maxFailedRecords`, the job **stops** (default `0` = stop on the first failure; `-1` = never stop).
5. **On Complete:** receives a `BatchJobResult` (total, successful, failed, elapsed, per-step stats).
6. **Batch Aggregator:** collects N records and processes them together (bulk API calls). With `streaming="true"` it processes *all* records as a stream, which suits writing one output file.

### Important limits and behaviours
- **Variables set inside one record's step** stay with that record. They aren't shared across records. Use a DB or OS for cross-record state.
- **Batch is not transactional across records.** Each record succeeds or fails independently, so design for partial success.
- **Ordering is not guaranteed** across blocks. Don't use Batch when record order matters.
- **Instance ID:** each run has a job instance ID (useful for logs). Exactly how it's exposed (a variable or attribute) depends on the runtime version.
- **Tuning:** start with `blockSize = 100–500` and `maxConcurrency = 2 × cores`, then load-test with production-sized files. Larger blocks mean fewer disk I/O operations and more heap.

## 4. Alternatives to Batch
| Need | Alternative |
|------|-------------|
| Small files (< 10k rows), order matters | `foreach` over a streamed payload |
| Parallel I/O on a moderate list | `parallel-foreach` with `maxConcurrency` |
| Very high volume, continuous | Event streaming (MQ/Kafka) instead of files |
| Pure DB-to-DB replication | ETL / database-native tools; MuleSoft might be the wrong tool |

## Interview angle
**Q: "Your batch processed 2M records and 3,000 failed. How do you handle and report it?"**
> "The job shouldn't stop for 3,000 bad records, so maxFailedRecords is set to a threshold, about 1%, that separates bad rows from a corrupt file. Failed records go to an ONLY_FAILURES step that bulk-writes them to an error table with the reason. On Complete publishes a summary event and writes an error CSV back to SFTP for the WMS team. The file goes to /error if failures exceed the threshold, otherwise to /archive. Because the SAP step only posts *deltas* and is keyed by material + plant + snapshot date, re-running the corrected rows is safe."

Next section: [07 — Integration patterns](../07-integration-patterns/01-api-and-routing-patterns.md)
