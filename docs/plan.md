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

- Confirm App Service authentication end to end (the infrastructure and hooks
  were added in Phase 2): user sign-in, and the Logic App's managed identity
  calling the API.
- Confirm the Logic App HTTP action accepts the user-assigned identity from an
  app setting.
- First `azd provision` attempt (public mode, dev SKUs): the preprovision hook
  created the app registration, and resource groups, storage, ACR,
  monitoring, and developer roles deployed. Cosmos DB creation was refused
  with "high demand" in both Canada Central and Canada East. The environment
  was torn down and is blocked until a Cosmos DB region access request
  (aka.ms/cosmosdbquota) is approved.
- Foundry Agent Service in private mode: add the input for its delegated agent
  subnet, plus the post-capability-host roles on Cosmos DB and Storage.
- Confirm the Foundry local-authentication setting and the Logic App trigger
  path in a real environment.
- Fix configuration mismatches, such as the Logic App worker runtime setting.
- Run `what-if` and a test deployment in `public` mode, then in `private` mode.

### Phase 4 — Reuse of existing resources

- `new` or `existing` mode for Foundry/OpenAI, Document Intelligence, and AI
  Search.
- Private endpoints for existing AI resources, independent of whether the
  accelerator created them.
- Wire up the Azure Monitor Private Link Scope (AMPLS) supplied for
  `existing` monitoring, or document clearly that its owner manages it.
- Diagnostic settings on all resources when monitoring is enabled.

### Phase 5 — Usability and validation

- Format checks on resource IDs and other inputs. The typed parameters
  themselves are introduced in Phase 2.
- A network contract document listing what PBMM/ALZ must provide: subnets,
  delegations, NSG rules, routing, and private DNS zones.
- Test the mode combinations (network × monitoring × new/existing AI ×
  SKU/model overrides) using
  `what-if` and parameter tests that check invalid inputs are rejected.
- Tests for the real Azure path in the API, and checks for the Logic App
  workflow.
- Template guidance: how to rename, extend, and add workflows or agents.

### Future enhancements

- `private-managed` network mode: a minimal VNet, separate integration and
  private-endpoint subnets, private DNS zones, and an NSG option of `create`,
  `existing`, or `none` (with private endpoint network policies enabled when an
  NSG is expected).
- Key Vault for secrets, plus a Key Vault private endpoint.
- Resiliency: zone redundancy, backup, and multi-region options.
- Custom RBAC roles, and role assignments scoped to individual resources.
- Search shared private links, for indexers and skillsets.

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
- Nothing has been deployed to Azure yet, so runtime behaviour is unverified
  until Phase 3.
