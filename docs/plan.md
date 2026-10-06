# Logic App AI Accelerator — High-Level Plan

## Purpose

A reusable, application-focused starter for Azure solutions built on Logic Apps
Standard, a web app/API, Azure AI Foundry (agents), Document Intelligence, and
Azure AI Search. It is meant to be cloned into new projects and to deploy into
either a public dev/test setup or an existing PBMM / Azure Landing Zone network.

## Guiding principles

- **Application-focused.** Do not recreate PBMM/ALZ platform services (hub
  networking, firewall and egress, central DNS, policy). Consume them by
  resource ID.
- **Explicit modes and validated inputs.** Networking and monitoring use
  explicit modes. Deployment fails early when required inputs for the selected
  mode are missing.
- **Independent concerns.** Private networking, monitoring, and the creation of
  AI resources can each be switched on or off without depending on the others.
- **Identity first.** Use managed identities and Entra ID (data-plane) roles,
  and turn off local/key authentication wherever possible.
- **Standard resource group layout.**
  - `rg-<app>-<env>`: web app, Logic App, storage, Cosmos DB, container registry
  - `rg-<app>-ai-<env>`: Foundry, Document Intelligence, AI Search
  - `rg-<app>-ops-<env>`: Log Analytics, Application Insights, Azure Monitor
    Private Link Scope (AMPLS)

## Deployment modes

| Setting | Modes | Notes |
|---|---|---|
| `networkMode` | `public`, `private` | `private` integrates with subnets and private DNS zones provided by PBMM/ALZ, which can be in another subscription. Private endpoints and VNet integration use separate subnets. After private connectivity is set up, public access to PaaS services is turned off. |
| `monitoringMode` | `none`, `new`, `existing` | `existing` links to an Application Insights / Log Analytics workspace that is already deployed. Monitoring is independent of `networkMode`. |
| AI resource mode *(planned)* | `new`, `existing` | Each AI service can either be created or reused, with private endpoints configured separately from creation. |

## Phases

### Phase 1 — Initial implementation (complete, not yet deployed)

- Public and private network modes, with validation.
- Subnets and DNS zones passed as resource IDs, so they can live in another
  subscription.
- Monitoring modes `none`, `new`, and `existing`.
- Separate resource groups for app, AI, and operations resources.
- Foundry (account, project, model deployment, connections, capability hosts),
  Document Intelligence, AI Search.
- Sample web app (Quart API and React UI), a sample Logic App workflow, and a
  sample Foundry agent.
- CI workflow for build, lint, and tests, plus a GitHub Actions deployment
  workflow.

### Phase 2 — Parameterization and azd parity (complete, not yet deployed)

Restore the customization the original document-review-platform offered, using
grouped, typed parameters instead of ~115 flat ones.

- **azd integration:**
  - Add `infra/main.bicepparam`, which maps every input to an azd
    environment variable, so `azd env set` can change it. (A `.bicepparam`
    file was chosen over `main.parameters.json` because it supports typed
    objects and arrays.)
  - Register the web app and Logic App as azd services.
  - Expose the outputs azd needs.
- **SKUs (`skus` object):** web App Service plan, Logic App plan, container
  registry, AI Search (including replicas and partitions), AI Services,
  Document Intelligence, Cosmos DB mode and throughput, and storage.
- **Naming (`resourceNames` object):** optional name overrides for each resource.
  Default names use the standard abbreviations plus a unique token. Resource
  group names can already be overridden.
- **Models (`modelDeployments` array):** any number of deployments (for example
  chat or embedding), each with model, version, SKU, and capacity.
- **Identity (`identity` object):**
  - `tenantId` and `authTenantId`.
  - `principalId` and the deploying principal's type, used for developer data
    roles.
  - A toggle for App Service built-in authentication ("Easy Auth").
- **Hooks:** port the azd `preprovision` and `postprovision` hooks that create
  Entra app registrations. Keep secrets out of parameters; use federated
  credentials or managed identity where possible.
- **Hosting:** optional App Service Environment (ASE) IDs, CORS allowed
  origins, and an IP allow-list for public mode.
- **Out of scope:** app-specific settings such as container names and
  instruction files. Each solution owns these.
- **Must avoid:** the original's flaws — untyped on/off settings that can
  combine into invalid configurations, secrets passed as parameters, misspelled
  names, and stale region allow-lists.
- **Delivered notes:**
  - App Service authentication uses a managed-identity federated credential
    instead of a client secret. The Logic App calls the API with its
    user-assigned identity, which the web app allows.
  - The resource token was shortened, which fixes storage account names that
    could exceed 24 characters.
  - Output names changed to azd-style `UPPER_SNAKE_CASE`.
  - The `fail()` validations were confirmed with `az deployment sub validate`.
    The default public configuration passes. Six invalid inputs are each
    rejected with a clear message: Basic ACR in private mode, an unknown chat
    deployment, an IP allow-list in private mode, a non-WS Logic App SKU, App
    Service authentication without a client ID, and existing monitoring
    without inputs.

### Phase 3 — Hardening and first deployment

Goal: a working public-mode deployment, end to end, with `azd up`. Then the
first private-mode deployment. Fix whatever real Azure surfaces.

**Starting state:** see "Implementation handoff" below. The `p3dev` azd
environment is ready for swedencentral. A previous attempt in Canada Central
and Canada East was blocked by Cosmos DB regional capacity, and both
environments were torn down.

**Tasks, in order:**

1. **Fix known bugs before deploying** (details under "Known issues"):
   - Make the blob trigger connection use the user-assigned identity (K1).
   - Align the Logic App worker runtime between infrastructure and local
     settings (K2).
   - Add the `scripts/` checks to CI (K6).
2. **Public deployment:**
   - Run `azd provision`. The preprovision hook reuses the existing app
     registration; the postprovision hook must add the redirect URI and the
     federated credential.
   - Fix template errors as they appear. Rerun until provisioning succeeds.
   - Run `azd deploy` (both the `web` and `logic` services).
3. **End-to-end checks (public):**
   - `GET /api/health` returns 200 without sign-in. Other routes redirect to
     Entra sign-in, and sign-in works in a browser.
   - Uploading a PDF to the `documents` container fires the Logic App, and
     the HTTP action reaches the API through Easy Auth using the user-assigned
     identity (K3). Confirm the trigger path behaviour, including
     subfolders (K4).
   - The API calls Document Intelligence, the Foundry model, Search, and
     Cosmos DB with managed identity. Local auth is off on all AI services
     (K5).
   - `samples/create_agent.py` creates an agent with the deployment outputs.
   - Re-run `azd provision`. It must be idempotent: no image reset, and no
     duplicate app registration or credential.
4. **Foundry Agent Service in private mode (K7):** add an optional delegated
   agent subnet input (`privateNetwork.agentSubnetId`) and the account
   `networkInjections`. Add the role assignments that are required after the
   capability host exists (Cosmos DB container-scoped data roles, Storage blob
   conditions), following the official standard-agent-setup template.
5. **Private deployment:** run `what-if`, then deploy in `private` mode into a
   test VNet that you own and that simulates the PBMM/ALZ network (it lives
   outside the accelerator). App code must be deployed from a machine or
   runner that can reach the private network. Document anything a platform
   team must provide.
6. **Re-review authorization** (from `docs/review.md`): confirm that role
   assignments and Easy Auth still work when resource group names, resource
   names, tenant, or auth tenant are overridden.

**Done when:** public mode works end to end with `azd up` from a clean
environment; private mode provisions successfully, and its checks pass from
inside the network; all fixes are committed; `docs/plan.md` and the README
reflect what was learned.

#### Phase 3 results

Status: code fixes done and committed. Public mode could not be completed and
private mode was not deployed, so end-to-end checks remain open.

**Fixed after real provisioning in `p3dev` (public, swedencentral):**
- Document Intelligence rejects `networkAcls.bypass`.
- Search with `disableLocalAuth: true` must not set `authOptions`.
- The project capability host needs the project identity's roles first (Storage Blob Data Contributor, Cosmos DB Operator, Search Index Data Contributor, Search Service Contributor), and connections must exist. It lives in `modules/ai/project-capability-host.bicep` and runs after the role modules. A failed capability host can't be updated: delete it with `az rest --method delete`, then redeploy.
- With agent `networkInjections`, the platform creates the account capability host itself, so ours is skipped in that case.
- Remote build needs a root `.dockerignore` (otherwise "archive/tar: write too long").
- The backend needs `aiohttp` for `azure.identity.aio`.
- The output `AZURE_MODEL_DEPLOYMENTS` collided with the input of the same name and broke the second `azd provision`. It is now `AZURE_MODEL_DEPLOYMENT_NAMES`.

**Blocked: storage policy.** In the test subscription, a policy forces
`publicNetworkAccess` to `Disabled` on storage accounts. The Logic App host
then returns 503 (identity-based host storage gets 403), so public mode with
public storage can't work there. Logic Apps Standard needs a network path to
its host storage (blob, queue, table, file). Options: use private endpoints
plus VNet integration even in public mode, or get a policy exemption.

**Not verified:** Logic App blob trigger, K3, K4, K5, `samples/create_agent.py`,
a browser sign-in (unauthenticated routes return 401, not a redirect), private
provisioning, and the in-network checks. The first private attempt in
swedencentral failed with `ResourcesForSkuUnavailable` for Search (basic and
standard); northeurope accepted a test Search service. Treat as transient
regional capacity.

**Verified:** what-if of private mode (34 resources) passes; resource group
and resource name overrides pass `what-if`; `verify.sh` is green.

**For the platform team (private mode):** private endpoints for the Logic App
storage (blob, file, queue, table) and web storage (blob); a delegated agent
subnet (`Microsoft.App/environments`); web and Logic App integration subnets
(`Microsoft.Web/serverFarms`); the private DNS zones; and a runner inside the
network for `azd deploy`. `scripts/test-network/` builds a test VNet like this.

**Teardown quirks:** delete the Azure Monitor private link scope before purging
the Log Analytics workspace; a Foundry account must reach a terminal state
before its resource group deletes; purge soft-deleted Cognitive Services
accounts.

### Phase 4 — Reuse of existing resources (implemented; validated, not deployed)

Goal: let a solution plug in AI and monitoring resources that already exist.

- **AI resource mode:** add `new` or `existing` per service: Foundry account
  (or Azure OpenAI), Document Intelligence, and AI Search. Use a typed object
  per service in `types.bicep`, e.g. `{ mode: 'new' | 'existing', resourceId? }`.
  For `existing`:
  - Reference the resource by ID; it can be in another subscription or
    resource group.
  - Skip creating it and its model deployments. Model deployments must already
    exist, but the template still validates that the chat deployment name is
    in the list.
  - Still assign the workload and developer roles. Cross-subscription role
    assignments need a module scoped to that resource group.
  - Still create the project, connections, and capability host when the
    Foundry account is new. An existing Foundry project is a stretch goal.
- **Private endpoints for existing AI resources:** create them in private mode
  whether or not the accelerator created the resource. Do not change the
  public network access of a resource the accelerator doesn't own; document
  this instead.
- **AMPLS for `existing` monitoring (K8):** `existingMonitoring.azureMonitorPrivateLinkScopeId`
  is accepted but unused. Pick one approach and document it: either add
  scoped resources and a private endpoint to the supplied AMPLS (needs
  permission on it), or state that the AMPLS owner does this.
- **Diagnostic settings (K9):** only the web app has them. Add them for the
  Logic App, storage (blob service), Cosmos DB, ACR, Foundry, Document
  Intelligence, and Search, sent to the selected workspace when
  `monitoringMode != 'none'`.
- Update `main.bicepparam`, the example parameter files, the README, and
  `check_parameter_files.py` for every new input.

**Phase 4 results:** `aiResources` (`foundry`, `documentIntelligence`, `search`; `mode` and `resourceId`) is implemented, with `AZURE_*_MODE` / `AZURE_EXISTING_*_RESOURCE_ID` azd variables. Existing resources are parsed from the ID (type and segment count checked), roles are granted on the resource through `modules/shared/ai-resource-role-assignment.bicep` scoped to its own resource group, and private endpoints are still created. An existing Foundry account gets no project, connections, or capability host. K8 is resolved by documenting that the AMPLS owner does the work; K9 adds diagnostics for the Logic App, storage blob service, Cosmos DB, ACR, and new Foundry, Document Intelligence, and Search. `az deployment sub validate` succeeds for new and all-existing in both network modes and rejects missing or wrong-type IDs. A real `what-if`/deployment against existing resources and the diagnostic categories remain unverified.

**Done when:** `what-if` succeeds for new and existing AI resources in both
network modes, and one deployment with an existing AI Search (or Document
Intelligence) works end to end.

### Phase 5 — Usability and validation

- **Input format checks:** validate resource IDs (subnet, DNS zone,
  workspace, ASE, existing AI resources) with `fail()` in `main.bicep`. Check
  the resource provider and type segments, not just that the value is
  non-empty.
- **Network contract document** (`docs/network-contract.md`) listing what
  PBMM/ALZ must provide:
  - Subnets: private endpoints, web integration, Logic App integration, and
    the Foundry agent subnet, with sizes and required delegations
    (`Microsoft.Web/serverFarms`, and `Microsoft.App/environments` for the
    agent subnet).
  - NSG rules, UDR and egress requirements: Entra ID, the ACR data endpoint,
    and Azure Monitor.
  - The full private DNS zone list, mapped to the `privateDnsZoneIds` keys,
    plus sovereign-cloud zone names (K10).
  - The roles the deployment identity needs on the network and DNS resource
    groups.
- **Mode-matrix tests:** a script that runs `az deployment sub validate` or
  `what-if` across network × monitoring × AI mode × SKU and model overrides.
  It should also check that invalid inputs are rejected; reuse the six Phase 2
  negative cases and extend the list. Make it runnable manually or in CI with
  Azure credentials.
- **Tests for the real Azure path in the API:** add unit tests for
  `AzureDocumentProcessor` (`app/backend/src/accelerator/services/processor.py`)
  with the Azure SDK clients mocked. Extend `validate_logic_app.py` to check
  that `connections.json` and the workflow use the identity app setting.
- **Template guidance** (`docs/extending.md`): how to rename the app, add a
  workflow, add a model deployment, add an agent, and replace the sample
  API/UI. Also how to move the repo out as an accelerator.

**Done when:** `./scripts/verify.sh` and CI cover the new tests; the
mode-matrix script passes; the docs exist and are linked from the README.

### Future enhancements

- `private-managed` network mode: a minimal VNet, separate integration and
  private-endpoint subnets, private DNS zones, and an NSG option of `create`,
  `existing`, or `none` (with private endpoint network policies enabled when an
  NSG is expected).
- Key Vault for secrets, plus a Key Vault private endpoint.
- Resiliency: zone redundancy, backup, and multi-region options.
- Custom RBAC roles, and role assignments scoped to individual resources.
- Search shared private links, for indexers and skillsets.

## Implementation handoff

Context for an agent or engineer picking up Phase 3 or later.

### Repository and tooling

- **Repo:** `/home/lucrawford/src/work/goa/logic-app-ai-accelerator`. It is
  standalone; it was derived from an analysis of the
  `document-review-platform` infrastructure, but no business logic was
  carried over.
- **Layout:**
  - `infra/main.bicep` — subscription-scope composition root. It creates three
    resource groups and holds the validations, role assignments, and outputs.
  - `infra/types.bicep` — shared exported types.
  - `infra/main.bicepparam` — azd environment variable mapping.
  - `infra/modules/{application,ai,monitoring,networking,shared}` — modules.
  - `app/backend` — Quart API with a mock/Azure processor switch,
    `ACCELERATOR_MOCK_SERVICES`.
  - `app/frontend` — React and Vite.
  - `app/logic` — Logic Apps Standard project.
  - `scripts/` — `verify.sh`, the parameter checks, the Logic App validator,
    and `hooks/app_registration.py` with tests.
- **Verify:** run `./scripts/verify.sh`. It builds the Bicep, type-checks
  `main.bicepparam` and the example files, validates the Logic App, and runs
  ruff and pytest (backend and scripts) and the frontend tests, lint, and
  build. It must stay green.
- **Tools:** Bicep CLI 0.44.x, azd 1.28.x, Python 3.12 (`.venv`), Node 20.
- **Way of working:**
  - Commit at regular intervals, with Co-authored-by trailers.
  - Stop and get confirmation before moving to the next phase.
  - Keep changes application-focused: never create hub networking, a
    firewall, or central DNS.

### Current Azure environment

- **Subscription:** `ME-MngEnvMCAP010603-lucrawford-1`
  (`bfa88b00-5760-4934-8c13-19988faa8563`).
- **Tenant:** `043282d2-4515-4bb6-b36d-219dce194997`.
- **azd environment `p3dev`**, currently empty in Azure:
  - `AZURE_LOCATION=swedencentral`, `AZURE_NETWORK_MODE=public`.
  - Dev SKUs: `AZURE_WEB_APP_SKU=B1`, `AZURE_CONTAINER_REGISTRY_SKU=Basic`,
    `AZURE_SEARCH_SKU=basic`.
  - `AZURE_USE_APP_SERVICE_AUTH=true`, with
    `AZURE_APP_SERVICE_AUTH_CLIENT_ID=d5819619-eeee-4524-88f2-ddcab8399aa2`
    (app registration `aiaccel-p3dev-web`, created by the hook).
  - swedencentral offers gpt-4.1-mini `2025-04-14` GlobalStandard and AI
    Search.
- **Resource names** include a token derived from the location, so changing
  region changes every name.
- **Clean up** with `azd down --force --purge`. The app registration survives
  `azd down` and is reused.
- **If Cosmos DB fails with "high demand":** delete the failed account before
  retrying, because a failed account blocks re-creation.

### Bicep and azd conventions and gotchas

- **Validations:** use `fail()` inside ternaries on variables, so ARM rejects
  bad input at template validation. `assert` is not used. Keep multi-line
  boolean expressions on one line.
- **Typed parameters:** grouped objects with optional properties (`?`).
  Resolve defaults with `valueOrDefault()` or `??` in `main.bicep`. An empty
  string means "not set".
- **Role assignment names** must be computable at deployment start, so
  role assignments across resource groups go through
  `modules/shared/role-assignment.bicep`, called from the subscription scope.
- **Existing-resource names** must be known at start. Don't use module
  outputs as an `existing` resource name (error BCP307); use the resolved
  `names.*` plus `dependsOn`.
- **`.bicepparam` files** don't allow user-defined functions or
  `environment()`. `json()` is evaluated eagerly, so give JSON environment
  variables a valid default (`'[]'` or `'{}'`).
- **azd:**
  - Services `web` (Docker, remote build) and `logic` (`host: function`,
    `language: js`; `app/logic/package.json` exists only for packaging and is
    excluded by `.funcignore`).
  - Services are matched by the `azd-service-name` tag.
  - azd injects `AZURE_PRINCIPAL_ID`. `SERVICE_WEB_IMAGE_NAME` is fed back
    into `webContainerImage`.
- **Outputs** use azd-style `UPPER_SNAKE_CASE`. `.github/workflows/deploy.yml`
  and `samples/README.md` read them.
- **Preview APIs:** Foundry capability hosts and connections use preview API
  versions. `capabilityHostKind` needs `#disable-next-line BCP037`.

### Identity model

| Principal | Used for | Roles (scope) |
|---|---|---|
| Web system-assigned identity | API calls to Storage, Cosmos DB, AI (`DefaultAzureCredential`; `AZURE_CLIENT_ID` is not set) | AcrPull, Storage Blob Data Contributor (app resource group); OpenAI User, Cognitive Services User, Search Index Data Contributor (AI resource group); Cosmos DB data role |
| Web user-assigned identity | Easy Auth federated credential only (`OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID`) | None |
| Logic App user-assigned identity | `AzureWebJobsStorage`, the HTTP call to the API (`WORKFLOWS_IDENTITY_RESOURCE_ID`), and the blob trigger (after K1) | Storage Blob, Queue, Table, and File data roles (app resource group). Its client ID is in Easy Auth `allowedApplications` |
| Foundry project system-assigned identity | Agent Service storage, threads, and vector store | Storage Blob Data Contributor, Cosmos DB Operator, Search Index Data Contributor, Search Service Contributor |
| Developer (`identity.principalId`) | Local development and samples | Storage Blob Data Contributor, AcrPush, Azure AI User, OpenAI User, Cognitive Services User, Search roles, Cosmos DB data role |

Role assignments are scoped to the resource group. Resource-level scoping is a
future enhancement.

### Known issues

| ID | Issue | Location | Phase |
|---|---|---|---|
| K1 | **Fixed.** Was: the blob trigger connection uses `ManagedServiceIdentity` without an identity, so it runs as the Logic App system-assigned identity, which has no storage roles. Add `"identity": "@appsetting('WORKFLOWS_IDENTITY_RESOURCE_ID')"` to `authProvider`, or give the system-assigned identity the roles. | `app/logic/connections.json` | 3 |
| K2 | **Resolved:** `FUNCTIONS_WORKER_RUNTIME` is `dotnet` in both places, the value Logic Apps Standard expects (the working reference project uses it too). | `infra/modules/application/compute.bicep` (~line 127), `app/logic/local.settings.example.json` | 3 |
| K3 | Not yet confirmed: a parameterized `identity` (`@appsetting(...)`) on the HTTP action works in Standard. If it doesn't, put the resource ID in `parameters.json` or hard-code it at deploy time. | `app/logic/workflows/process-document/workflow.json` | 3 |
| K4 | The blob trigger `path` is `documents/{name}.pdf`. Check whether it fires for subfolders, and how `{name}` resolves. | Same workflow | 3 |
| K5 | `disableLocalAuth: true` on Foundry, Document Intelligence, and Search. Confirm that the agent capability host and samples work this way. | `infra/modules/ai/stack.bicep` | 3 |
| K6 | **Fixed.** Was: CI did not run `check_parameter_files.py`, the `scripts/` ruff check, or the `scripts/tests` pytest run, which `verify.sh` does. | `.github/workflows/ci.yml` | 3 |
| K7 | **Implemented, not deployed:** agent subnet, `networkInjections`, and post-capability-host roles. Passes `what-if`; never provisioned (see Phase 3 results). | `infra/modules/ai/stack.bicep`, `infra/types.bicep` | 3 |
| K8 | **Resolved:** `existingMonitoring.azureMonitorPrivateLinkScopeId` is informational; the AMPLS owner manages scoped resources and DNS (see README). | `infra/main.bicep`, `infra/modules/monitoring/stack.bicep` | 4 |
| K9 | **Implemented, not deployed:** diagnostic settings for web, Logic App, storage blob, Cosmos DB, ACR, and new AI resources. | All modules | 4 |
| K10 | Public-cloud names are hard-coded: private DNS zone names in `main.bicepparam` (override with `AZURE_PRIVATE_DNS_ZONE_IDS`) and the `foundryOpenAiEndpoint` output (`openai.azure.com`). | `infra/main.bicepparam`, `infra/modules/ai/stack.bicep` | 5 |
| K11 | **Unconfirmed assumptions:** a Logic App on an ASE uses a Windows plan with an `I*v2` SKU; apps on an ASE get no private endpoint; Document Intelligence F0 supports private endpoints; App Service plan `tier` can be omitted. | `infra/modules/application/compute.bicep`, `infra/main.bicep` | 3–5 |
| K12 | The web IP allow-list adds the Logic App's current outbound IPs (not all possible outbound IPs). The SCM site is intentionally unrestricted so CI can deploy. | `infra/modules/application/compute.bicep` | 5 |
| K13 | With Easy Auth enabled, the GitHub Actions deploy workflow doesn't run the hooks. The app registration must be created separately. | `.github/workflows/deploy.yml` | 5 |

## Out of scope

- Hub networking, firewall and egress, and central DNS (PBMM/ALZ provides
  these).
- Migrating the document-review business logic. The accelerator ships generic
  samples only.

## Key risks

- Some Foundry capability host and Agent Service networking APIs are in preview
  and may change.
- Cosmos DB region capacity can block new accounts per subscription. Request
  region access before the first deployment.
- Private-mode deployment of app code needs a self-hosted runner that can reach
  the private network.
- Nothing has been deployed to Azure successfully yet, so runtime behaviour
  is unverified until Phase 3.
