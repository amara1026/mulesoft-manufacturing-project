# 06.5 — SAP and Salesforce Connectors

`Essential` (concepts) · `Advanced` (configuration details)

> **Version note:** Connector XML element and attribute names differ between connector major versions. Studio generates them from the connector's metadata. The snippets below show the *structure and the decisions*. Always regenerate them in Studio for your installed version, and check the connector reference on docs.mulesoft.com.

## Part A — SAP Connector (SAP S/4HANA / ECC)

### 1. Prerequisites (often underestimated, so plan 2–4 weeks)
| Item | Who provides it |
|------|-----------------|
| SAP JCo 3 libraries (`sapjco3.jar` + OS-specific native lib) and `sapidoc3.jar` for IDocs | Your SAP licence (download from SAP Support Portal). Added to the app as **shared libraries** or via a Maven repo you control |
| Technical RFC user with **S_RFC** authorisation for the specific BAPIs | SAP Basis + security team |
| Network path to the SAP application server / message server (ports `32xx`, `33xx`, `36xx`, `48xx` for SNC) | Network team + VPN to the Private Space |
| For IDocs: **RFC destination + program ID** registered on the SAP gateway, partner profiles (WE20), ports (WE21) | SAP Basis / EDI team |
| SNC (Secure Network Communication) certificates if encryption is required | SAP security |

### 2. Connection configuration (representative)
```xml
<sap:sap-config name="SAP_Config" doc:name="SAP S/4HANA">
    <sap:simple-connection-provider-connection
        applicationServerHost="${sap.ashost}" systemNumber="${sap.sysnr}" client="${sap.client}"
        username="${sap.user}" password="${secure::sap.password}" language="EN">
        <pooling-profile maxActive="${sap.pool.max}" exhaustedAction="WHEN_EXHAUSTED_WAIT" maxWait="5000"/>
    </sap:simple-connection-provider-connection>
</sap:sap-config>
```
For load-balanced SAP systems, use the message-server connection (`msHost`, `r3name`, `group`) instead of a fixed application server.

### 3. Calling a BAPI synchronously (sRFC)
```xml
<flow name="sap-create-sales-order-flow">
    <ee:transform doc:name="Canonical -> BAPI XML">
        <ee:message><ee:set-payload resource="dwl/canonical-to-bapi-salesorder.dwl"/></ee:message>
    </ee:transform>
    <!-- Execute synchronous remote function call; operation name varies by connector version -->
    <sap:sync-rfc config-ref="SAP_Config" key="BAPI_SALESORDER_CREATEFROMDAT2" doc:name="BAPI create sales order"/>
    <ee:transform doc:name="Check RETURN table">
        <ee:message><ee:set-payload resource="dwl/bapi-return-to-result.dwl"/></ee:message>
    </ee:transform>
    <choice doc:name="BAPI success?">
        <when expression="#[payload.success]">
            <sap:sync-rfc config-ref="SAP_Config" key="BAPI_TRANSACTION_COMMIT" doc:name="Commit LUW"/>
        </when>
        <otherwise>
            <sap:sync-rfc config-ref="SAP_Config" key="BAPI_TRANSACTION_ROLLBACK" doc:name="Rollback LUW"/>
            <raise-error type="AIM:SAP_BUSINESS_ERROR" description="#[payload.errors map $.text joinBy '; ']"/>
        </otherwise>
    </choice>
</flow>
```

**Critical detail: the commit must run on the same SAP session.** `BAPI_TRANSACTION_COMMIT` applies to the LUW of the *same connection/session*. The SAP connector provides **transaction scopes/operations** (start/commit SAP transaction) so both calls share one stateful connection. If they run on different pooled connections, the commit does nothing and the order silently disappears. This is a well-known production bug, and naming it in an interview shows real SAP experience.

### 4. Receiving IDocs from SAP (outbound from SAP → Mule)
```xml
<flow name="sap-idoc-matmas-listener-flow">
    <sap:document-listener config-ref="SAP_Server_Config" gatewayHost="${sap.gwhost}"
                           gatewayService="${sap.gwserv}" programID="AIM_MULE_IDOC" doc:name="MATMAS IDoc listener"/>
    <!-- payload = IDoc XML (e.g. MATMAS05) -->
    <ee:transform doc:name="IDoc -> canonical material"/>
    <anypoint-mq:publish config-ref="MQ_Config" destination="${mq.x.materialChanged}" doc:name="Publish material.changed"/>
</flow>
```
- IDocs are **transactional RFC (tRFC)**. SAP sends a **TID**, and the connector uses it to avoid processing the same IDoc twice. Persist TIDs durably (the connector's TID store config) in clustered or multi-replica setups.
- Acknowledge quickly by publishing to MQ, then process asynchronously. Long-running listener flows block SAP's outbound queue (SM58 backlog).

### 5. BAPI/RFC vs OData vs IDoc — when to use which
| Option | Good for | Drawbacks |
|--------|----------|-----------|
| **BAPI/RFC via SAP Connector** | Rich synchronous create/simulate (pricing, ATP), ECC and S/4 on-prem | JCo libs, native libs, stateful sessions, SAP-specific skills |
| **OData (S/4HANA APIs) via HTTP** | Reads, simple creates, **S/4HANA Cloud** (often the only option) | Some BAPIs have no OData equivalent. Batch requests are complex |
| **IDoc** | Asynchronous, high-volume document exchange (orders, deliveries, invoices, master data) | Monitoring lives in SAP (WE02/BD87). Partner profile setup |

## Part B — Salesforce Connector

### 1. Authentication: OAuth 2.0 JWT bearer (server-to-server)
```xml
<salesforce:sfdc-config name="Salesforce_Config" doc:name="Salesforce">
    <salesforce:jwt-connection consumerKey="${sf.consumerKey}" principal="${sf.integrationUser}"
                               keyStore="${sf.keystore.path}" storePassword="${secure::sf.keystorePassword}"
                               audienceUrl="${sf.loginUrl}"/>
</salesforce:sfdc-config>
```
Use a **dedicated integration user** with a minimal permission set. Never use a person's account (password resets break the integration, and audit becomes muddled).

### 2. Query and upsert by external ID
```xml
<salesforce:query config-ref="Salesforce_Config" doc:name="Get account by SAP id">
    <salesforce:salesforce-query><![CDATA[SELECT Id, Name, Status__c, Credit_Block__c
        FROM Account WHERE SAP_Customer_Id__c = ':sapId' LIMIT 1]]></salesforce:salesforce-query>
    <salesforce:parameters><![CDATA[#[{ sapId: vars.sapCustomerId }]]]></salesforce:parameters>
</salesforce:query>

<salesforce:upsert config-ref="Salesforce_Config" objectType="Order"
                   externalIdFieldName="AIM_Order_Id__c" doc:name="Upsert order status">
    <salesforce:records><![CDATA[#[[{
        AIM_Order_Id__c: payload.orderId,
        Status: payload.salesforceStatus,
        SAP_Order_Number__c: payload.sapOrderNumber,
        Tracking_Number__c: payload.trackingNumber
    }]]]]></salesforce:records>
</salesforce:upsert>
```

**Why upsert by external ID:** it's **naturally idempotent**. Replaying the same status event updates the same record instead of creating a duplicate. The external ID field must be marked *External ID* and *Unique* in Salesforce.

### 3. Salesforce governor limits and how the design respects them
| Limit (varies by edition, check current values) | AIM design response |
|---|---|
| Daily API request limit per org | Batch status updates per order (one upsert of N records), and use the Composite API |
| Record locking (`UNABLE_TO_LOCK_ROW`) on parent Account during parallel updates | Treat it as retryable with jitter. Reduce parallelism per account |
| Bulk API for > ~2,000 records | Nightly product/price sync uses **Bulk API 2.0** jobs |

### 4. Receiving events from Salesforce
- **Platform Events / Change Data Capture** via the connector's streaming listener (newer versions use the **Pub/Sub API**). Example: `Order_Submitted__e` as an alternative to the synchronous callout.
- **Replay ID:** store the last processed replay ID durably so a restart resumes without loss (within Salesforce's retention window).
- Trade-off: events decouple Salesforce from Mule's availability, but the rep no longer gets the SAP number synchronously. AIM uses a **callout for submit** and **CDC for account changes**.

## Interview angle
**Q: "What's the most common SAP integration bug you know of?"**
> "Two come to mind. First, forgetting `BAPI_TRANSACTION_COMMIT`, or running it on a different connection from the BAPI call, so SAP returns success but nothing is saved. The fix is to use the connector's transaction scope so both calls share the same session. Second, ALPHA conversion: sending customer `100234` instead of `0000100234`, which gives 'customer not found'. I centralise padding in a DataWeave module and unit-test it."

Next: [06.6 Messaging (Anypoint MQ / VM / Kafka)](06-messaging-anypoint-mq.md)
