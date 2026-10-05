# Foundry agent example

After infrastructure deployment, use the `foundryProjectEndpoint` and `modelDeploymentName` deployment outputs to create a generic document assistant:

```bash
outputs=$(az deployment sub show --name <deployment-name> --query properties.outputs --output json)
AZURE_FOUNDRY_PROJECT_ENDPOINT=$(jq -r '.foundryProjectEndpoint.value' <<<"$outputs")
AZURE_MODEL_DEPLOYMENT=$(jq -r '.modelDeploymentName.value' <<<"$outputs")

python -m pip install -r samples/requirements.txt
python samples/create_agent.py \
  --endpoint "$AZURE_FOUNDRY_PROJECT_ENDPOINT" \
  --model "$AZURE_MODEL_DEPLOYMENT"
```

The infrastructure creates the Foundry account, project, resource connections, and Agent Service capability hosts. Agent definitions remain application artifacts so teams can replace this example without changing the platform deployment.


The identity running the script needs the **Azure AI User** role on the Foundry project. The infrastructure does not assign it yet; developer role assignments are planned for Phase 2. In `private` mode, run the script from a network that can reach the Foundry private endpoint.
