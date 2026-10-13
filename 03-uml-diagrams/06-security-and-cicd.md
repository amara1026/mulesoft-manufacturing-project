# 03.6 — Security Trust Boundaries & CI/CD Deployment Sequence (Diagrams 18, 19)

`Essential`

## Diagram 18 — Security and trust-boundary diagram

```mermaid
flowchart LR
    subgraph Z0["Zone 0 - Untrusted internet"]
        SUP[Supplier systems]
        CAR[Carriers]
        POR[B2B portal users]
    end
    subgraph Z1["Zone 1 - SaaS partners (trusted identity, external network)"]
        SF[Salesforce]
        IDP[Identity Provider<br/>OAuth2 / OIDC]
    end
    subgraph Z2["Zone 2 - MuleSoft Private Space (DMZ-like)"]
        ING[Ingress<br/>TLS 1.2+, mTLS for suppliers]
        EXP[Experience APIs<br/>policies: JWT / client-id / rate limit / IP allow-list]
        PRC[Process APIs<br/>internal ingress only]
        SYS[System APIs<br/>internal only]
    end
    subgraph Z3["Zone 3 - AIM data centre (trusted)"]
        SAP[(SAP)]
        WMS[(WMS)]
        MES[(MES)]
    end
    subgraph Z4["Zone 4 - Data stores"]
        PG[(PostgreSQL<br/>encrypted at rest)]
        MQ{{Anypoint MQ<br/>encrypted at rest}}
    end

    SUP -->|mTLS + client-id| ING
    CAR -->|HTTPS + HMAC webhook| ING
    POR -->|OIDC token| ING
    SF -->|OAuth2 client credentials JWT| ING
    SF -. token request .-> IDP
    ING --> EXP --> PRC --> SYS
    SYS -->|IPsec VPN + firewall allow-list<br/>SAP SNC / TLS, technical user| SAP
    SYS -->|TLS + API key| WMS
    SYS -->|TLS| MES
    PRC -->|TLS, least-privilege DB user| PG
    PRC -->|client credentials per app| MQ
```

**Boundary-by-boundary**

| Boundary | Threats | Controls |
|----------|---------|----------|
| Internet → Ingress | Spoofing, DDoS, credential stuffing | TLS, **mTLS** for suppliers (certificate = identity), WAF/DDoS protection in front, rate limiting, IP allow-lists for carriers |
| Partner → Exp API | Over-privileged clients, replay | OAuth2 scopes per client (`orders:write`, `orders:read`), JWT validation (issuer, audience, expiry), **HMAC + timestamp** on webhooks to stop replay |
| Exp → Prc → Sys | Lateral movement, bypassing Exp policies | Prc/Sys have **no public endpoint**. Internal client-id enforcement, optionally internal mTLS |
| Mule → SAP | Stolen RFC credentials, excessive authorisation | Technical user restricted to required BAPIs (`S_RFC` authorisation object), SNC encryption, VPN, firewall limited to the Private Space CIDR |
| Mule → DB/MQ | Data exfiltration | Per-app credentials, least-privilege grants, encryption at rest and in transit |
| Logs | PII leakage | Mask names, email, phone and address. Never log tokens or full payloads at INFO |

Details: [10-security-governance](../10-security-governance/01-security-architecture.md).

## Diagram 19 — CI/CD deployment sequence

```mermaid
sequenceDiagram
    autonumber
    actor DEV as Developer
    participant GIT as Git (feature branch / PR)
    participant CI as CI pipeline (Jenkins / Azure DevOps)
    participant NEX as Exchange / artifact repo
    participant RM as Runtime Manager (CloudHub 2.0)
    participant APIM as API Manager
    participant SMK as Smoke tests
    actor REL as Release approver

    DEV->>GIT: push feature/AIM-412-shortage-event
    GIT->>CI: PR opened - trigger build
    CI->>CI: mvn clean verify - MUnit + coverage gate 80%
    CI->>CI: static checks - secrets scan, dependency scan
    CI-->>GIT: status checks pass, reviewer approves, merge to develop
    GIT->>CI: build on merge
    CI->>NEX: publish app artifact 1.4.0 (immutable)
    CI->>RM: deploy 1.4.0 to DEV (env properties, encrypted secrets from vault)
    CI->>APIM: apply policies via API instance id
    CI->>SMK: run smoke + Postman/Newman contract tests
    SMK-->>CI: pass
    CI->>RM: promote same artifact to QA, then UAT
    REL->>CI: approve PROD (change ticket CHG-2231)
    CI->>RM: deploy 1.4.0 to PROD - rolling update
    RM-->>CI: replicas healthy
    CI->>SMK: prod smoke tests (read-only + synthetic order to a test customer)
    alt smoke fails or error rate spikes
        CI->>RM: redeploy previous version 1.3.2
    end
```

**Explanation**
- **Build once, deploy many:** the *same* artifact version moves from DEV to PROD. Only properties differ. Rebuilding per environment breaks traceability.
- **Quality gates:** MUnit coverage, failing tests, secret scanning and dependency vulnerabilities block the merge.
- **Secrets** come from a vault (Azure Key Vault, HashiCorp Vault) at deploy time, or are pre-set as *protected* properties in Runtime Manager. They are never stored in the repo.
- **Rolling update** on CloudHub 2.0 replaces replicas gradually, so there's no downtime for stateless apps.
- **Rollback = redeploy the previous artifact.** That only works if DB schema changes are **backward compatible** (expand → migrate → contract) and API changes are non-breaking.
- **Prod smoke tests must be safe:** read-only checks plus a synthetic order for a dedicated test customer that is excluded from billing. Agree this with the business.

Full pipeline YAML/Jenkinsfile: [11.3](../11-deployment-cicd/03-cicd-pipelines.md).
