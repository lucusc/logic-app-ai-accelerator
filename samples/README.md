# Foundry agent example

After infrastructure deployment, use the Foundry project endpoint and model deployment output to create a generic document assistant:

```bash
python -m pip install -r samples/requirements.txt
python samples/create_agent.py \
  --endpoint "$AZURE_FOUNDRY_PROJECT_ENDPOINT" \
  --model "$AZURE_MODEL_DEPLOYMENT"
```

The infrastructure creates the Foundry account, project, resource connections, and Agent Service capability hosts. Agent definitions remain application artifacts so teams can replace this example without changing the platform deployment.

