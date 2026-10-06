# Logic App AI Accelerator

An application-focused accelerator for building Azure Logic Apps Standard solutions that orchestrate AI document processing. It deploys a generic React web app, Quart API, Logic App workflow, Microsoft Foundry resources, Document Intelligence, Azure AI Search, Storage, Cosmos DB, and optional monitoring.

The accelerator does not recreate PBMM or Azure Landing Zone services. Private deployments integrate with existing subnets, NSGs, routing, egress controls, and private DNS zones.

See [docs/plan.md](docs/plan.md) for the phased roadmap.

## Deployment modes

| Setting | Values | Behavior |
|---|---|---|
| `networkMode` | `public`, `private` | Public access for development, or private endpoints and VNet integration using existing network resources |
| `monitoringMode` | `none`, `new`, `existing` | No monitoring, application-owned monitoring, or integration with an existing monitoring platform |

`private` mode requires separate private-endpoint, web-app integration, and Logic App integration subnet resource IDs. It also requires existing private DNS zone resource IDs for every deployed private-link service.

## Resource groups

| Resource group | Contents |
|---|---|
| `rg-<app>-<env>` | Web/API app, Logic App Standard, Storage, Cosmos DB, ACR, managed identities |
| `rg-<app>-ai-<env>` | Microsoft Foundry, model deployment, Document Intelligence, Azure AI Search |
| `rg-<app>-ops-<env>` | Log Analytics, Application Insights, and application-owned monitoring resources |

## Repository layout

```text
app/backend/       Quart API and Azure service orchestration
app/frontend/      React TypeScript sample UI
app/logic/         Logic Apps Standard project
infra/             Subscription-scoped Bicep and reusable modules
docs/              Plan and design documentation
samples/           Foundry agent setup example
scripts/           Verification, parameter checks, and azd hooks
```

## Local development

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r app/backend/requirements.txt -r app/backend/requirements-dev.txt
cd app/frontend && npm install && cd ../..

ACCELERATOR_MOCK_SERVICES=true \
PYTHONPATH=app/backend/src \
.venv/bin/python -m quart --app accelerator.app:create_app run --port 50505
```

In another terminal:

```bash
cd app/frontend
npm run dev
```

## Validate

```bash
./scripts/verify.sh
```

This builds the Bicep template, type-checks `infra/main.bicepparam` and the example parameter files, validates the Logic App project, and runs the hook, API, and frontend tests and lint.

## Parameters

`infra/main.bicep` uses grouped, typed parameters defined in `infra/types.bicep`. Invalid combinations fail at deployment start with a clear message.

| Parameter | Purpose |
|---|---|
| `appName`, `environmentName`, `location`, `tags` | Naming inputs, region, and extra tags |
| `networkMode`, `privateNetwork` | `public` or `private`; private mode takes subnet and private DNS zone resource IDs |
| `monitoringMode`, `existingMonitoring` | `none`, `new`, or `existing` monitoring |
| `aiResources` | Per service (`foundry`, `documentIntelligence`, `search`): `mode` `new` (default) or `existing` with a `resourceId` |
| `resourceGroupNames`, `resourceNames` | Optional overrides for any resource group or resource name |
| `skus` | Web and Logic App plans, ACR, AI Search (replicas, partitions, semantic), AI Services, Document Intelligence, Cosmos DB (serverless or provisioned), storage, log retention |
| `modelDeployments`, `chatDeploymentName` | Any number of model deployments; which one the app uses for chat |
| `identity` | Tenant and auth tenant, the developer principal for data roles, and App Service authentication |
| `hosting` | Optional App Service Environment IDs, CORS origins, and a public-mode IP allow-list |
| `webContainerImage`, `backendApiAudience` | Web container image and the audience the Logic App requests tokens for |

Notable rules: private mode requires a Premium container registry; an ASE requires an Isolated (`I*v2`) plan; the Logic App plan must be WS1–WS3 otherwise; the IP allow-list applies only to public mode.

## Deploy with azd

`infra/main.bicepparam` maps every parameter to an azd environment variable, so you can change settings with `azd env set` instead of editing files.

```bash
azd env new dev
azd env set AZURE_LOCATION canadacentral
azd env set AZURE_APP_NAME myapp              # optional, default aiaccel
azd up
```

Common settings (see `infra/main.bicepparam` for the full list):

| Variable | Default | Notes |
|---|---|---|
| `AZURE_NETWORK_MODE` | `public` | `private` also needs `AZURE_PRIVATE_ENDPOINT_SUBNET_ID`, `AZURE_WEB_INTEGRATION_SUBNET_ID`, `AZURE_LOGIC_INTEGRATION_SUBNET_ID`, `AZURE_AGENT_SUBNET_ID` (delegated to `Microsoft.App/environments`), and DNS zones |
| `AZURE_PRIVATE_DNS_ZONES_RESOURCE_GROUP_ID` | | Builds standard public-cloud zone IDs from one resource group |
| `AZURE_PRIVATE_DNS_ZONE_IDS` | `{}` | JSON object that overrides individual zone IDs (needed for sovereign clouds) |
| `AZURE_MONITORING_MODE` | `new` | `existing` needs `AZURE_EXISTING_APPLICATION_INSIGHTS_CONNECTION_STRING` and `AZURE_EXISTING_LOG_ANALYTICS_WORKSPACE_ID` |
| `AZURE_FOUNDRY_MODE`, `AZURE_DOCUMENT_INTELLIGENCE_MODE`, `AZURE_SEARCH_MODE` | `new` | `existing` needs `AZURE_EXISTING_FOUNDRY_RESOURCE_ID`, `AZURE_EXISTING_DOCUMENT_INTELLIGENCE_RESOURCE_ID`, or `AZURE_EXISTING_SEARCH_RESOURCE_ID` (see below) |
| `AZURE_WEB_APP_SKU`, `AZURE_LOGIC_APP_SKU` | `P1v3`, `WS1` | Plus `_TIER` and `_CAPACITY` |
| `AZURE_CONTAINER_REGISTRY_SKU` | `Premium` | `Basic` or `Standard` are allowed in public mode |
| `AZURE_SEARCH_SKU` | `standard` | Plus `AZURE_SEARCH_REPLICA_COUNT`, `AZURE_SEARCH_PARTITION_COUNT`, `AZURE_SEARCH_SEMANTIC_SEARCH` |
| `AZURE_COSMOS_MODE` | `serverless` | `provisioned` uses `AZURE_COSMOS_THROUGHPUT` |
| `AZURE_CHAT_MODEL_NAME`, `AZURE_CHAT_MODEL_VERSION` | `gpt-4.1-mini`, `2025-04-14` | Optional `AZURE_EMBEDDING_MODEL_NAME` adds an embedding deployment |
| `AZURE_MODEL_DEPLOYMENTS` | | JSON array that replaces the model list |
| `AZURE_USE_APP_SERVICE_AUTH` | `false` | Turns on Entra sign-in for the web app (see below) |
| `AZURE_PRINCIPAL_TYPE` | `User` | Set by you; azd sets `AZURE_PRINCIPAL_ID` to the signed-in identity automatically |
| `AZURE_NAME_*`, `AZURE_RG_*_NAME` | | Resource and resource group name overrides |

If your subscription forces storage `publicNetworkAccess` to `Disabled`, the Logic App can't reach its host storage in `public` mode; use `private` mode. `scripts/test-network/deploy.sh <env> <location>` builds a throwaway VNet and DNS zones for trying it.

azd deploys two services: `web` (container built remotely in ACR) and `logic` (the `app/logic` workflow project, deployed through the Functions host that Logic Apps Standard runs on). In `private` mode, run azd from a machine that can reach the private endpoints and SCM sites.

### Reusing existing AI and monitoring resources

Each AI service can be reused by ID, in another resource group or subscription. For `existing` resources the accelerator:

- does not create or change the resource, its networking, or its authentication settings;
- grants the web identity, the Foundry project identity (Search only), and the developer principal their data roles **on the resource itself**, so the deployment identity needs permission to create role assignments there;
- creates the private endpoint in the application's private endpoint subnet in `private` mode. Public network access on the existing resource is not changed; turn it off yourself if required;
- sends no diagnostics for it (the owner manages those).

Requirements and limits:

- The existing resource must allow Entra ID (data-plane RBAC) authentication; Search must have RBAC enabled.
- With an existing Foundry account, models are not deployed: `modelDeployments` must list the deployments that already exist, and `chatDeploymentName` must be one of them. No project, connections, or capability host are created, so `AZURE_FOUNDRY_PROJECT_*` outputs are empty and `samples/create_agent.py` needs your own project. Reusing an existing Foundry project is not supported yet.

`existingMonitoring.azureMonitorPrivateLinkScopeId` is informational. The accelerator does not modify an existing Azure Monitor Private Link Scope: its owner must add the workspace and Application Insights as scoped resources and provide the private endpoint and DNS. Diagnostic settings (Logic App, web app, storage blob, Cosmos DB, container registry, and any new Foundry, Document Intelligence, and Search) go to the selected workspace whenever `monitoringMode` is not `none`.

### App Service authentication

When `AZURE_USE_APP_SERVICE_AUTH=true`:

- The `preprovision` hook creates or updates an Entra app registration (`<app>-<env>-web`) and stores its client ID in `AZURE_APP_SERVICE_AUTH_CLIENT_ID`. To use an existing registration, set that variable first.
- The `postprovision` hook adds the web redirect URI and a federated credential that trusts the web app's user-assigned managed identity. No client secret is created.
- The web app requires sign-in, except for `/api/health`. Calls from the Logic App are allowed through its managed identity.

The hooks need Python 3 and permission to manage app registrations in the auth tenant (`AZURE_AUTH_TENANT_ID`, which defaults to the deployment tenant).

### Teardown and soft-delete

- In private mode the `predown` hook deletes the Azure Monitor Private Link Scope and its private endpoints, so the workspace can be removed. The `preprovision` hook also deletes any AMPLS private endpoint left `Disconnected`, which Azure cannot update.
- Foundry and Document Intelligence accounts are soft-deleted by default, so redeploying the same environment name fails with `FlagMustBeSetForRestore`. For repeated test cycles, run `azd env set AZURE_PURGE_SOFT_DELETED_ON_DOWN true`. The `postdown` hook then purges the accounts that `down` removed. It does nothing unless set, so real environments keep soft-delete recovery.

## Deploy without azd

Copy `infra/main.parameters.example.json` (public) or `infra/private.parameters.example.json` (private) to an environment-specific file, provide the required values, and preview the subscription deployment:

```bash
az deployment sub what-if \
  --location <deployment-location> \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.example.json
```

Deploy infrastructure before packaging and deploying `app/logic`. The Logic Apps zip must contain the contents of `app/logic` at its root.

The included GitHub Actions workflow builds a single container containing the Quart API and compiled React application, pushes it with ACR Tasks, and zip-deploys the Logic App project. It does not run the azd hooks, so create the app registration separately if you enable App Service authentication. Private deployments require a self-hosted runner with access to the existing private network and SCM endpoint.
