# 11.2 — Maven Build Lifecycle, Exchange Publishing and Git Workflow

`Essential`

## 1. Maven lifecycle for a Mule app

| Phase | What happens for `packaging=mule-application` |
|-------|-----------------------------------------------|
| `validate` | POM/project checks |
| `compile` | Compiles Java (if any). Processes resources |
| `test` | **MUnit** runs via `munit-maven-plugin` (+ coverage report) |
| `package` | `mule-maven-plugin` builds `target/<app>-<version>-mule-application.jar` (deployable) |
| `verify` | Coverage gates fail the build if thresholds aren't met |
| `deploy` | Publishes the artifact to Exchange (Maven facade). With `-DmuleDeploy`, also deploys to the target runtime |

Common commands:
```bash
mvn clean package                                   # build + MUnit
mvn clean package -DskipMunitTests                  # build only (never in CI for main branches)
mvn clean deploy -DmuleDeploy -Denv=qa              # publish + deploy (CloudHub 2.0 profile)
mvn munit:test -Dmunit.test=prc-order-management-test-suite.xml   # one suite
```

## 2. CloudHub 2.0 deployment configuration (mule-maven-plugin)

```xml
<plugin>
  <groupId>org.mule.tools.maven</groupId>
  <artifactId>mule-maven-plugin</artifactId>
  <version>${mule.maven.plugin.version}</version>
  <extensions>true</extensions>
  <configuration>
    <cloudhub2Deployment>
      <uri>https://anypoint.mulesoft.com</uri>
      <provider>MC</provider>
      <environment>${deploy.environment}</environment>          <!-- e.g. QA -->
      <target>${deploy.target}</target>                          <!-- Private Space name -->
      <muleVersion>${app.runtime}</muleVersion>
      <applicationName>${deploy.appName}</applicationName>        <!-- e.g. qa-order-mgmt-prc-api -->
      <replicas>${deploy.replicas}</replicas>
      <vCores>${deploy.vcores}</vCores>
      <connectedAppClientId>${anypoint.clientId}</connectedAppClientId>
      <connectedAppClientSecret>${anypoint.clientSecret}</connectedAppClientSecret>
      <connectedAppGrantType>client_credentials</connectedAppGrantType>
      <properties>
        <env>${deploy.env}</env>
        <api.id>${deploy.apiId}</api.id>
      </properties>
      <secureProperties>
        <secure.key>${secure.key}</secure.key>
      </secureProperties>
      <deploymentSettings>
        <updateStrategy>rolling</updateStrategy>
        <clustered>false</clustered>
        <http><inbound><lastMileSecurity>false</lastMileSecurity></inbound></http>
      </deploymentSettings>
    </cloudhub2Deployment>
  </configuration>
</plugin>
```
*Element names follow the mule-maven-plugin 4.x documentation. Confirm them against the plugin version you use.* **Important:** for Exchange publishing, the POM `groupId` must be your **business group (organisation) ID**.

## 3. Parent POM strategy

`aim-parent-pom` centralises:
- Plugin versions (mule-maven-plugin, munit), repositories (Exchange, MuleSoft releases).
- MUnit coverage thresholds.
- Common properties (`app.runtime=4.9.x`).
- **Benefit:** a runtime upgrade happens in one place, and every app picks it up on its next build.

## 4. Git workflow and pull requests

**Branch policy (GitFlow-lite, see the diagram in [06.1](../06-mule-implementation/01-dev-setup-and-repo.md))**

| Branch | Deploys to | Protection |
|--------|-----------|------------|
| `feature/*` | Local / DEV on demand | — |
| `develop` | DEV (auto) | PR + 1 approval + green build |
| `release/x.y.z` | QA → UAT | PR + green build. Only fixes |
| `main` | PROD (manual approval) | PR from release/hotfix only. Tag `vX.Y.Z` |
| `hotfix/*` | QA (fast track) → PROD | Merge back to `develop` |

**PR template (AIM)**
```markdown
## What / Why
AIM-412: publish inventory.shortage-detected via outbox for partial stock.

## Changes
- prc-order-management.xml: allocation choice + outbox insert
- dwl/allocation.dwl (new) + golden tests
## Risk & rollback
- New outbox event type; consumers ignore unknown types (tolerant). Rollback = redeploy 1.3.2.
## Tests
- MUnit T2 (partial stock), T3 (duplicate). Coverage 86%.
## Checklist
- [x] No secrets / PII in logs   - [x] doc:name unique   - [x] Error codes in catalogue
- [x] RAML/Exchange version bumped (minor)   - [x] Runbook updated
```

## 5. Versioning of app artifacts
- **Semantic versioning** of the app (`1.4.0`), independent of the API major version (`v1`).
- **SNAPSHOTs** never go beyond DEV. Release builds are immutable.
- The application name in Runtime Manager is stable per environment (`prod-order-mgmt-prc-api`), and the artifact version changes on each release.

Next: [11.3 CI/CD pipelines](03-cicd-pipelines.md)
