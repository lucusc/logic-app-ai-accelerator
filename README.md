# Logic App AI Accelerator

An application-focused accelerator for building Azure Logic Apps Standard solutions that orchestrate AI document processing. It deploys a generic React web app, Quart API, Logic App workflow, Microsoft Foundry resources, Document Intelligence, Azure AI Search, Storage, Cosmos DB, and optional monitoring.

The accelerator does not recreate PBMM or Azure Landing Zone services. Private deployments integrate with existing subnets, NSGs, routing, egress controls, and private DNS zones.

See [docs/plan.md](docs/plan.md) for the phased roadmap.

## Deployment modes

| Setting | Values | Behavior |
|---|---|---|
| `networkMode` | `public`, `private` | Explicitly approved public access with an IP allow-list, or private endpoints and VNet integration using existing network resources |
| `monitoringMode` | `none`, `new`, `existing` | No monitoring, application-owned monitoring, or integration with an existing monitoring platform |

Public mode is not implicit. It requires `allowPublicAccess=true` and at least
one IPv4 CIDR in `hosting.allowedIpRanges`. Private mode requires existing
network resources but does not require the public-access approval.

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
| `networkMode`, `allowPublicAccess`, `privateNetwork` | Public access requires explicit approval and an IP allow-list; private mode takes subnet and private DNS zone resource IDs |
| `monitoringMode`, `existingMonitoring` | `none`, `new`, or `existing` monitoring |
| `aiResources` | Per service (`foundry`, `documentIntelligence`, `search`): `mode` `new` (default) or `existing` with a `resourceId` |
| `resourceGroupNames`, `resourceNames` | Optional overrides for any resource group or resource name |
| `skus` | Web and Logic App plans, ACR, AI Search (replicas, partitions, semantic), AI Services, Document Intelligence, Cosmos DB (serverless or provisioned), storage, log retention |
| `modelDeployments`, `chatDeploymentName` | Any number of model deployments; which one the app uses for chat |
| `identity` | Tenant and auth tenant, the developer principal for data roles, and App Service authentication |
| `hosting` | Optional App Service Environment IDs, CORS origins, and a public-mode IP allow-list |
| `webContainerImage`, `backendApiAudience` | Web container image and the audience the Logic App requests tokens for |

Notable rules: public mode requires `allowPublicAccess=true` and at least one
allowed IPv4 CIDR; private mode requires a Premium container registry; an ASE
requires an Isolated (`I*v2`) plan; and the Logic App plan must be WS1–WS3
otherwise.

## Deploy with azd

`infra/main.bicepparam` maps every parameter to an azd environment variable, so you can change settings with `azd env set` instead of editing files.

The default values are a cost-oriented starter profile: B1 App Service, WS1
Logic Apps Standard, Basic ACR, Basic AI Search, serverless Cosmos DB,
Standard_LRS storage, no monitoring resources, and one chat model deployment.
This profile demonstrates the architecture; it is not a production sizing
recommendation.

For an explicitly approved public development deployment:

```bash
azd env new dev
azd env set AZURE_LOCATION canadacentral
azd env set AZURE_APP_NAME myapp              # optional, default aiaccel
azd env set AZURE_NETWORK_MODE public
azd env set AZURE_ALLOW_PUBLIC_ACCESS true
azd env set AZURE_ALLOWED_IP_RANGES 203.0.113.10/32
azd up
```

Replace the example CIDR with the public IPv4 address or corporate egress range
that should reach the web and Logic Apps endpoints. App Service authentication
is enabled by default. The preprovision hook creates the app registration unless
`AZURE_APP_SERVICE_AUTH_CLIENT_ID` identifies an existing one.

Common settings (see `infra/main.bicepparam` for the full list):

| Variable | Default | Notes |
|---|---|---|
| `AZURE_NETWORK_MODE` | `public` | Public mode does not deploy until explicitly approved; `private` also needs the subnet and DNS settings below |
| `AZURE_ALLOW_PUBLIC_ACCESS` | `false` | Must be `true` for public mode |
| `AZURE_ALLOWED_IP_RANGES` | | Required comma-separated IPv4 CIDRs for public mode |
| `AZURE_PRIVATE_DNS_ZONES_RESOURCE_GROUP_ID` | | Builds standard public-cloud zone IDs from one resource group |
| `AZURE_PRIVATE_DNS_ZONE_IDS` | `{}` | JSON object that overrides individual zone IDs (needed for sovereign clouds) |
| `AZURE_MONITORING_MODE` | `none` | `new` creates application monitoring; `existing` needs an Application Insights connection string and workspace ID |
| `AZURE_FOUNDRY_MODE`, `AZURE_DOCUMENT_INTELLIGENCE_MODE`, `AZURE_SEARCH_MODE` | `new` | `existing` needs `AZURE_EXISTING_FOUNDRY_RESOURCE_ID`, `AZURE_EXISTING_DOCUMENT_INTELLIGENCE_RESOURCE_ID`, or `AZURE_EXISTING_SEARCH_RESOURCE_ID` (see below) |
| `AZURE_WEB_APP_SKU`, `AZURE_LOGIC_APP_SKU` | `B1`, `WS1` | Plus `_TIER` and `_CAPACITY`; use an Isolated v2 SKU with an ASE |
| `AZURE_CONTAINER_REGISTRY_SKU` | `Basic` | Set `Premium` in private mode |
| `AZURE_SEARCH_SKU` | `basic` | Plus `AZURE_SEARCH_REPLICA_COUNT`, `AZURE_SEARCH_PARTITION_COUNT`, `AZURE_SEARCH_SEMANTIC_SEARCH` |
| `AZURE_AI_SERVICES_SKU`, `AZURE_DOCUMENT_INTELLIGENCE_SKU` | `S0`, `S0` | Service-tier overrides |
| `AZURE_COSMOS_MODE` | `serverless` | `provisioned` uses `AZURE_COSMOS_THROUGHPUT` |
| `AZURE_STORAGE_SKU` | `Standard_LRS` | Supports LRS, ZRS, GRS, RA-GRS, GZRS, and RA-GZRS values from `infra/types.bicep` |
| `AZURE_LOG_ANALYTICS_RETENTION_DAYS` | `30` | Used when monitoring mode is `new` |
| `AZURE_CHAT_MODEL_NAME`, `AZURE_CHAT_MODEL_VERSION` | `gpt-4.1-mini`, `2025-04-14` | Optional `AZURE_EMBEDDING_MODEL_NAME` adds an embedding deployment |
| `AZURE_CHAT_DEPLOYMENT_SKU`, `AZURE_CHAT_DEPLOYMENT_CAPACITY` | `GlobalStandard`, `10` | Override model deployment SKU and capacity |
| `AZURE_MODEL_DEPLOYMENTS` | | JSON array that replaces the model list |
| `AZURE_USE_APP_SERVICE_AUTH` | `true` | Set `false` only when another access-control layer is intentionally used |
| `AZURE_PRINCIPAL_TYPE` | `User` | Set by you; azd sets `AZURE_PRINCIPAL_ID` to the signed-in identity automatically |
| `AZURE_NAME_*`, `AZURE_RG_*_NAME` | | Resource and resource group name overrides |

For a production-like profile, override only the capacity required by the
workload. For example:

```bash
azd env set AZURE_WEB_APP_SKU P1v3
azd env set AZURE_WEB_APP_SKU_TIER PremiumV3
azd env set AZURE_WEB_APP_SKU_CAPACITY 2
azd env set AZURE_CONTAINER_REGISTRY_SKU Premium
azd env set AZURE_SEARCH_SKU standard
azd env set AZURE_SEARCH_REPLICA_COUNT 2
azd env set AZURE_STORAGE_SKU Standard_ZRS
azd env set AZURE_MONITORING_MODE new
azd env set AZURE_LOG_ANALYTICS_RETENTION_DAYS 90
```

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

App Service authentication is enabled by default. When it is enabled:

- The `preprovision` hook creates or updates an Entra app registration (`<app>-<env>-web`) and stores its client ID in `AZURE_APP_SERVICE_AUTH_CLIENT_ID`. To use an existing registration, set that variable first.
- The `postprovision` hook adds the web redirect URI and a federated credential that trusts the web app's user-assigned managed identity. No client secret is created.
- The web app requires sign-in, except for `/api/health`. Calls from the Logic App are allowed through its managed identity.

The hooks need Python 3 and permission to manage app registrations in the auth tenant (`AZURE_AUTH_TENANT_ID`, which defaults to the deployment tenant).

### Identity-based data access

The application and Logic App use managed identities and Entra data-plane
roles. Storage shared-key access is disabled, Cosmos DB local authentication is
disabled, and newly created Foundry, Document Intelligence, and Search
resources disable local authentication.

If key-based troubleshooting is unavoidable, make the exception directly on
the affected resource and immediately restore the secure setting afterward.
The next Bicep deployment also restores the secure value:

```bash
# Temporary exceptions
az storage account update -g <rg> -n <storage> --allow-shared-key-access true
az cosmosdb update -g <rg> -n <cosmos> --disable-local-auth false
az resource update --ids <foundry-or-document-intelligence-resource-id> \
  --set properties.disableLocalAuth=false
az search service update -g <rg> -n <search> --disable-local-auth false

# Restore the accelerator defaults
az storage account update -g <rg> -n <storage> --allow-shared-key-access false
az cosmosdb update -g <rg> -n <cosmos> --disable-local-auth true
az resource update --ids <foundry-or-document-intelligence-resource-id> \
  --set properties.disableLocalAuth=true
az search service update -g <rg> -n <search> --disable-local-auth true
```

Do not store keys obtained during troubleshooting in application settings,
parameter files, workflow secrets, or source control.

### Teardown and soft-delete

- In private mode the `predown` hook deletes the Azure Monitor Private Link Scope and its private endpoints, so the workspace can be removed. The `preprovision` hook also deletes any AMPLS private endpoint left `Disconnected`, which Azure cannot update.
- Foundry and Document Intelligence accounts are soft-deleted by default, so redeploying the same environment name fails with `FlagMustBeSetForRestore`. For repeated test cycles, run `azd env set AZURE_PURGE_SOFT_DELETED_ON_DOWN true`. The `postdown` hook then purges the accounts that `down` removed. It does nothing unless set, so real environments keep soft-delete recovery.

## Deploy without azd

Copy `infra/main.parameters.example.json` (explicit public starter) or
`infra/private.parameters.example.json` (private production example) to an
environment-specific file and replace every placeholder. Public parameter files
must include `allowPublicAccess: true`, at least one allowed IPv4 CIDR, and an
App Service authentication client ID.

```bash
az deployment sub what-if \
  --location <deployment-location> \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.example.json
```

Deploy infrastructure before deploying either application artifact. The Logic
Apps zip must contain the contents of `app/logic` at its root.

### Independent GitHub Actions deployments

Three manually triggered workflows provide independent release paths:

| Workflow | Purpose | Immutable identifier |
|---|---|---|
| `deploy-infrastructure.yml` | Deploy subscription-scoped Bicep and publish ARM outputs | Deployment `infra-<SHA prefix>` and artifact `infrastructure-<SHA>` |
| `deploy-application.yml` | Build the combined Quart/React image and update App Service | Image `<configured-name>:<full SHA>`, deployed by digest |
| `deploy-logic-app.yml` | Package and zip-deploy `app/logic` | Package and artifact `logic-<full SHA>.zip` |

Configure these GitHub environment variables:

| Variable | Used by |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | OIDC login for all workflows |
| `AZURE_DEPLOYMENT_LOCATION` | Infrastructure workflow |
| `AZURE_APPLICATION_RESOURCE_GROUP`, `AZURE_CONTAINER_REGISTRY_NAME`, `WEB_APP_NAME` | Application workflow |
| `AZURE_WEB_IMAGE_NAME` | Application image repository, for example `myapp-dev-web` |
| `LOGIC_APP_NAME` | Logic App workflow |

Select the protected GitHub Environment with each workflow's required
`environment_name` dispatch input. Resource names can also be supplied as
workflow-dispatch inputs. The
infrastructure workflow uploads `deployment-outputs.json`; its values can be
copied directly into the corresponding GitHub environment variables.

The GitHub infrastructure workflow does not run azd hooks. Because
authentication is enabled by default, create the Entra app registration first
and put its client ID in the selected parameter file. Private deployments
require a self-hosted runner with access to private endpoints and the SCM site.
