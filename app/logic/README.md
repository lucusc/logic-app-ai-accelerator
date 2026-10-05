# Logic App project

`process-document` is a stateful workflow triggered when a PDF is uploaded to the configured Blob container. It calls the accelerator API using the Logic App managed identity.

Required app settings:

- `AZURE_STORAGE_ENDPOINT`
- `AZURE_STORAGE_SUBMISSIONS_CONTAINER`
- `BACKEND_API_URL`
- `BACKEND_API_AUDIENCE`
- `WORKFLOWS_TENANT_ID`
- `WORKFLOWS_SUBSCRIPTION_ID`
- `WORKFLOWS_RESOURCE_GROUP_NAME`
- `WORKFLOWS_LOCATION_NAME`

Package the contents of this directory at the root of the deployment zip.

