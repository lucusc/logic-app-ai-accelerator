# Logic App project

`process-document` is a stateful workflow triggered when a PDF is uploaded to the configured Blob container. It calls the accelerator API using the Logic App's user-assigned managed identity, which the web app's App Service authentication allows when it is enabled.

Required app settings:

- `AZURE_STORAGE_ENDPOINT`
- `AZURE_STORAGE_SUBMISSIONS_CONTAINER`
- `BACKEND_API_URL`
- `BACKEND_API_AUDIENCE` (set to `api://<client-id>` when App Service authentication is enabled)
- `WORKFLOWS_IDENTITY_RESOURCE_ID` (resource ID of the user-assigned identity used for the API call)
- `WORKFLOWS_TENANT_ID`
- `WORKFLOWS_SUBSCRIPTION_ID`
- `WORKFLOWS_RESOURCE_GROUP_NAME`
- `WORKFLOWS_LOCATION_NAME`

Package the contents of this directory at the root of the deployment zip, or run `azd deploy logic`. `package.json` exists only so azd can package this project with the Functions host; it is excluded from the deployment by `.funcignore`.

