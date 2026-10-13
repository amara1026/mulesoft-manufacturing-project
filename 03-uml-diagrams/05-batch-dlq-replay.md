# 03.5 — Batch Inventory Sync & DLQ / Replay / Reconciliation (Diagrams 16, 17)

`Essential` (16) · `Advanced` (17)

## Diagram 16 — Batch inventory synchronisation architecture

**Scenario:** Every night at 01:00 the WMS drops `inventory_snapshot_YYYYMMDD.csv` (~2M rows, ~250 MB) on SFTP. It must update SAP's view of available stock and the analytics platform, and it must report row-level failures.

```mermaid
flowchart LR
    WMS[(WMS)] -->|01:00 writes .csv + .done marker| SFTP[(SFTP /inbound/inventory)]
    subgraph APP["inventory-sync-batch-app"]
        SCH[Scheduler 01:15<br/>or SFTP On New File] --> CHK{.done marker present?<br/>checksum OK?}
        CHK -->|no| WAIT[Retry in 10 min / alert at 03:00]
        CHK -->|yes| RD[SFTP read - streaming]
        RD --> BJ[[Batch Job<br/>blockSize 500, maxConcurrency 8]]
        subgraph STEPS["Batch steps"]
            ST1[Step 1 Validate + transform<br/>to canonical]
            ST2[Step 2 Compare with SAP<br/>Batch Aggregator 1000]
            ST3[Step 3 Send deltas to SAP<br/>bulk call per 1000]
            ST4[Step 4 FailedOnly<br/>write error rows]
        end
        BJ --> ST1 --> ST2 --> ST3
        ST1 -.failed records.-> ST4
        ST3 -.failed records.-> ST4
        BJ --> ONC[On Complete<br/>summary + metrics]
    end
    ST3 --> SAP[(SAP via SAP Sys API)]
    ST4 --> ERRF[(SFTP /errors/*.csv<br/>+ DB recon_result)]
    ONC --> MQ{{inventory.sync-completed event}}
    ONC --> MV[Move file to /archive]
    MQ --> AN[Analytics]
```

**Explanation**
- **Completion marker / checksum:** never start reading a file the producer is still writing. Use a `.done` file, a rename convention (`.tmp` → `.csv`), or a file-age check.
- **Streaming read:** the SFTP read is a *stream*. The Batch Job splits records without loading 250 MB into the heap. Batch persists records to its **internal on-disk queues**, so memory stays bounded.
- **Block size and concurrency:** the defaults are `blockSize=100` and concurrency based on available cores. Tune them with load tests. Bigger blocks mean fewer I/O round trips but more memory per thread.
- **Batch Aggregator:** sends 1000 records per SAP call instead of 2M single calls. This is the key performance lever.
- **Delta-only:** compare with SAP and send only changes. That usually cuts traffic by 90%+.
- **Failed-records step (`acceptPolicy="ONLY_FAILURES"`)** writes the failed rows to an error file and the DB, so the job continues past bad rows. The **`maxFailedRecords`** threshold (e.g. 1% of the total) stops the job if the file is clearly corrupt.
- **On Complete** emits a summary (total, successful, failed) as an event and moves the file to the archive. Idempotency: the file name + checksum is recorded, so the **same file isn't processed twice**.

**Alternatives:** an event-driven delta feed from the WMS (better freshness, more complex); SAP IDoc `WMMBXY` per movement; a direct DB-to-DB ETL tool for pure replication. Batch is chosen because the WMS only supports a nightly export.

## Diagram 17 — Dead-letter queue, controlled replay and reconciliation

```mermaid
flowchart TB
    Q{{order-status-sync queue}} --> C[Consumer]
    C -->|success| ACK[ack]
    C -->|retryable error<br/>timeout, 503, 429| NACK[nack - redeliver<br/>with backoff]
    NACK --> Q
    C -->|non-retryable<br/>400, mapping error| DLQDIRECT[publish to DLQ<br/>+ error metadata]
    Q -->|delivery count exceeds maxDeliveries 5| DLQ{{order-status-sync-dlq}}
    DLQDIRECT --> DLQ
    DLQ --> ALERT[Alert: DLQ depth > 0<br/>runbook link]
    ALERT --> OPS([Support engineer])
    OPS --> INSPECT[Inspect via replay API<br/>GET /dlq/messages]
    INSPECT --> FIX{Root cause fixed?}
    FIX -->|data issue| EDIT[Correct payload<br/>4-eyes approval]
    FIX -->|system recovered| REPLAY
    EDIT --> REPLAY[POST /dlq/replay<br/>ids, dryRun, rate limit]
    REPLAY --> AUD[(audit: who, when, what)]
    REPLAY --> Q
    RECON[Reconciliation job<br/>every 4h] -->|compare Mule state vs SAP vs Salesforce| DIFF{Differences?}
    DIFF -->|yes| REPUB[Re-publish status event<br/>or open ops task]
    DIFF -->|no| OK[Report OK]
    REPUB --> Q
```

**Explanation**
- **Retryable vs non-retryable classification** is the most important decision. Retrying a 400 is pointless. Not retrying a 503 loses data. Map Mule error types to these classes once, in shared error-handling config.
- **Anypoint MQ** has native DLQ support: configure a DLQ on the queue and set **max deliveries**. After N failed deliveries the broker moves the message. Non-retryable errors can be sent to the DLQ immediately by the app, which saves wasted attempts.
- **Controlled replay:** replay is a *write action* with business impact, so it needs an API with authentication, an audit trail, dry-run and rate limiting. Do not drag messages around in the console. Replay relies on **consumer idempotency**. Without it, replays create duplicates (scenario #18).
- **Reconciliation** is the safety net that catches what the DLQ never saw: silent failures, lost events, bugs. It compares the **source of truth** (SAP) with downstream copies and repairs them by re-publishing.

**Common mistakes:** having no alert on DLQ depth, so it becomes a graveyard; replaying everything at once and overloading the recovered system; editing payloads with no approval or audit.

Next: [03.6 Security & CI/CD diagrams](06-security-and-cicd.md)
