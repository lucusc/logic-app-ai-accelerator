# Logic App AI Accelerator

An application-focused accelerator for building Azure Logic Apps Standard solutions that orchestrate AI document processing. It deploys a generic React web app, Quart API, Logic App workflow, Microsoft Foundry resources, Document Intelligence, Azure AI Search, Storage, Cosmos DB, and optional monitoring.

The accelerator does not recreate PBMM or Azure Landing Zone services. Private deployments integrate with existing subnets, NSGs, routing, egress controls, and private DNS zones.

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
samples/           Foundry agent setup example
scripts/           Local verification
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
az bicep build --file infra/main.bicep
```

## Deploy

Copy `infra/main.parameters.example.json` to an environment-specific parameter file, provide the required values, and preview the subscription deployment:

```bash
az deployment sub what-if \
  --location <deployment-location> \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.example.json
```

Deploy infrastructure before packaging and deploying `app/logic`. The Logic Apps zip must contain the contents of `app/logic` at its root.

The included deployment workflow builds a single container containing the Quart API and compiled React application, pushes it with ACR Tasks, and zip-deploys the Logic App project. Private deployments require a self-hosted runner with access to the existing private network and SCM endpoint.
