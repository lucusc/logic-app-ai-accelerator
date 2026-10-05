#!/usr/bin/env bash
# Deploys the test-only VNet and private DNS zones (see main.bicep) and writes
# the resulting IDs into an azd environment so the accelerator can run in
# private mode. Usage: scripts/test-network/deploy.sh <azd-env-name> <location>
set -euo pipefail

ENV_NAME="${1:?azd environment name}"
LOCATION="${2:?location}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RG="rg-aiaccel-net-${ENV_NAME}"

OUT=$(az deployment sub create \
  --name "aiaccel-test-network-${ENV_NAME}" \
  --location "$LOCATION" \
  --template-file "$HERE/main.bicep" \
  --parameters location="$LOCATION" resourceGroupName="$RG" \
  --query properties.outputs -o json)

val() { echo "$OUT" | python3 -c "import sys,json;print(json.load(sys.stdin)['$1']['value'])"; }

azd env set AZURE_NETWORK_MODE private -e "$ENV_NAME"
azd env set AZURE_PRIVATE_ENDPOINT_SUBNET_ID "$(val privateEndpointSubnetId)" -e "$ENV_NAME"
azd env set AZURE_WEB_INTEGRATION_SUBNET_ID "$(val webIntegrationSubnetId)" -e "$ENV_NAME"
azd env set AZURE_LOGIC_INTEGRATION_SUBNET_ID "$(val logicIntegrationSubnetId)" -e "$ENV_NAME"
azd env set AZURE_AGENT_SUBNET_ID "$(val agentSubnetId)" -e "$ENV_NAME"
azd env set AZURE_PRIVATE_DNS_ZONES_RESOURCE_GROUP_ID "$(val resourceGroupId)" -e "$ENV_NAME"
echo "Test network ready in $RG"
