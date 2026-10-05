"""azd hooks that manage the optional Entra app registration for App Service authentication.

preprovision  creates or updates the app registration and stores its client ID in the azd environment.
postprovision adds the web redirect URI and the managed-identity federated credential.

Both commands do nothing unless AZURE_USE_APP_SERVICE_AUTH is true. No client secrets are created:
App Service authenticates to Entra with the web app's user-assigned managed identity.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from collections.abc import Callable, Mapping
from typing import Any

GRAPH_APP_ID = "00000003-0000-0000-c000-000000000000"
GRAPH_USER_READ_SCOPE_ID = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
FEDERATED_CREDENTIAL_NAME = "web-managed-identity"
FEDERATED_CREDENTIAL_AUDIENCE = "api://AzureADTokenExchange"
SCOPE_VALUE = "user_impersonation"

Runner = Callable[..., subprocess.CompletedProcess]


class HookError(RuntimeError):
    pass


class GraphClient:
    def __init__(self, token: str, endpoint: str) -> None:
        self._token = token
        self._endpoint = endpoint.rstrip("/")

    def request(self, method: str, path: str, body: Mapping[str, Any] | None = None,
                headers: Mapping[str, str] | None = None) -> dict[str, Any] | None:
        """Send a Graph request. Returns None for 404 and {} for empty responses."""
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(f"{self._endpoint}/v1.0{path}", data=data, method=method)
        request.add_header("Authorization", f"Bearer {self._token}")
        request.add_header("Content-Type", "application/json")
        for name, value in (headers or {}).items():
            request.add_header(name, value)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            detail = error.read().decode("utf-8", errors="replace")
            raise HookError(f"Microsoft Graph {method} {path} failed with {error.code}: {detail}") from error
        return json.loads(payload) if payload else {}


def is_enabled(env: Mapping[str, str]) -> bool:
    return env.get("AZURE_USE_APP_SERVICE_AUTH", "").strip().lower() in {"true", "1", "yes"}


def require(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise HookError(f"{name} is required in the azd environment.")
    return value


def unique_name(env: Mapping[str, str]) -> str:
    app_name = env.get("AZURE_APP_NAME") or "aiaccel"
    return f"{app_name}-{require(env, 'AZURE_ENV_NAME')}-web"


def ensure_app_registration(graph: GraphClient, env: Mapping[str, str]) -> str:
    """Create or update the app registration and its service principal; return the client ID."""
    existing_client_id = env.get("AZURE_APP_SERVICE_AUTH_CLIENT_ID", "").strip()
    if existing_client_id:
        app = graph.request("GET", f"/applications(appId='{existing_client_id}')")
        if app is None:
            raise HookError(
                f"AZURE_APP_SERVICE_AUTH_CLIENT_ID {existing_client_id} was not found in the auth tenant."
            )
    else:
        name = unique_name(env)
        app = graph.request(
            "PATCH",
            f"/applications(uniqueName='{name}')",
            {"displayName": env.get("AZURE_APP_SERVICE_AUTH_DISPLAY_NAME") or name, "signInAudience": "AzureADMyOrg"},
            headers={"Prefer": "create-if-missing"},
        )
        # Graph returns 201 with the object on create and 204 with no body on update.
        if not app:
            app = graph.request("GET", f"/applications(uniqueName='{name}')")
        if not app:
            raise HookError(f"Unable to create or read the app registration {name}.")

    client_id = app["appId"]
    graph.request("PATCH", f"/applications/{app['id']}", api_settings(app))
    if graph.request("GET", f"/servicePrincipals(appId='{client_id}')") is None:
        graph.request("POST", "/servicePrincipals", {"appId": client_id})
    return client_id


def api_settings(app: Mapping[str, Any]) -> dict[str, Any]:
    """Build the API, sign-in, and Graph permission settings while preserving existing values."""
    api = app.get("api") or {}
    scopes = list(api.get("oauth2PermissionScopes") or [])
    if not any(scope.get("value") == SCOPE_VALUE for scope in scopes):
        scopes.append({
            "id": str(uuid.uuid4()),
            "value": SCOPE_VALUE,
            "type": "User",
            "isEnabled": True,
            "adminConsentDisplayName": "Access the application",
            "adminConsentDescription": "Allows the app to access the application on behalf of the signed-in user.",
            "userConsentDisplayName": "Access the application",
            "userConsentDescription": "Allows the app to access the application on your behalf.",
        })

    identifier_uri = f"api://{app['appId']}"
    identifier_uris = list(app.get("identifierUris") or [])
    if identifier_uri not in identifier_uris:
        identifier_uris.append(identifier_uri)

    required_access = list(app.get("requiredResourceAccess") or [])
    other_access = [item for item in required_access if item.get("resourceAppId") != GRAPH_APP_ID]
    graph_permissions = [
        permission
        for item in required_access if item.get("resourceAppId") == GRAPH_APP_ID
        for permission in item.get("resourceAccess") or []
    ]
    if not any(permission.get("id") == GRAPH_USER_READ_SCOPE_ID for permission in graph_permissions):
        graph_permissions.append({"id": GRAPH_USER_READ_SCOPE_ID, "type": "Scope"})

    web = app.get("web") or {}
    return {
        "identifierUris": identifier_uris,
        "api": {"requestedAccessTokenVersion": 2, "oauth2PermissionScopes": scopes},
        "requiredResourceAccess": [*other_access, {"resourceAppId": GRAPH_APP_ID, "resourceAccess": graph_permissions}],
        "web": {
            "redirectUris": list(web.get("redirectUris") or []),
            "implicitGrantSettings": {"enableIdTokenIssuance": True, "enableAccessTokenIssuance": False},
        },
    }


def configure_after_provision(graph: GraphClient, env: Mapping[str, str]) -> None:
    """Add the deployed web app redirect URI and trust the web managed identity as the client credential."""
    client_id = require(env, "AZURE_APP_SERVICE_AUTH_CLIENT_ID")
    web_uri = require(env, "WEB_APP_URI").rstrip("/")
    identity_principal_id = require(env, "WEB_IDENTITY_PRINCIPAL_ID")
    tenant_id = require(env, "AZURE_TENANT_ID")
    authority = env.get("AZURE_AUTHORITY_HOST", "https://login.microsoftonline.com").rstrip("/")

    app = graph.request("GET", f"/applications(appId='{client_id}')")
    if app is None:
        raise HookError(f"App registration {client_id} was not found.")

    redirect_uri = f"{web_uri}/.auth/login/aad/callback"
    redirect_uris = list((app.get("web") or {}).get("redirectUris") or [])
    if redirect_uri not in redirect_uris:
        graph.request("PATCH", f"/applications/{app['id']}", {"web": {"redirectUris": [*redirect_uris, redirect_uri]}})

    issuer = f"{authority}/{tenant_id}/v2.0"
    credentials_path = f"/applications/{app['id']}/federatedIdentityCredentials"
    existing = (graph.request("GET", credentials_path) or {}).get("value", [])
    match = next((item for item in existing if item.get("name") == FEDERATED_CREDENTIAL_NAME), None)
    if match is None:
        graph.request("POST", credentials_path, {
            "name": FEDERATED_CREDENTIAL_NAME,
            "issuer": issuer,
            "subject": identity_principal_id,
            "audiences": [FEDERATED_CREDENTIAL_AUDIENCE],
            "description": "Lets App Service authentication use the web app managed identity instead of a secret.",
        })
    elif match.get("issuer") != issuer or match.get("subject") != identity_principal_id:
        graph.request("PATCH", f"{credentials_path}/{match['id']}", {
            "issuer": issuer,
            "subject": identity_principal_id,
            "audiences": [FEDERATED_CREDENTIAL_AUDIENCE],
        })


def graph_endpoint(env: Mapping[str, str]) -> str:
    return env.get("AZURE_GRAPH_ENDPOINT", "https://graph.microsoft.com").rstrip("/")


def get_graph_token(env: Mapping[str, str], run: Runner) -> str:
    endpoint = graph_endpoint(env)
    tenant = env.get("AZURE_AUTH_TENANT_ID") or env.get("AZURE_TENANT_ID") or ""
    commands: list[list[str]] = []
    if shutil.which("azd"):
        command = ["azd", "auth", "token", "--scope", f"{endpoint}/.default", "--output", "json"]
        commands.append(command + (["--tenant-id", tenant] if tenant else []))
    if shutil.which("az"):
        command = ["az", "account", "get-access-token", "--resource", endpoint, "--output", "json"]
        commands.append(command + (["--tenant", tenant] if tenant else []))
    for command in commands:
        result = run(command, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            payload = json.loads(result.stdout)
            token = payload.get("token") or payload.get("accessToken")
            if token:
                return token
    raise HookError("Unable to get a Microsoft Graph token. Run `azd auth login` or `az login` first.")


def azd_env_set(name: str, value: str, run: Runner) -> None:
    result = run(["azd", "env", "set", name, value], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise HookError(f"azd env set {name} failed: {result.stderr.strip()}")


def main(argv: list[str], env: Mapping[str, str] | None = None, run: Runner = subprocess.run,
         graph_factory: Callable[[str, str], GraphClient] = GraphClient) -> int:
    env = os.environ if env is None else env
    if len(argv) != 1 or argv[0] not in {"preprovision", "postprovision"}:
        print("Usage: app_registration.py preprovision|postprovision", file=sys.stderr)
        return 2
    if not is_enabled(env):
        print("App Service authentication is disabled; skipping app registration.")
        return 0

    try:
        graph = graph_factory(get_graph_token(env, run), graph_endpoint(env))
        if argv[0] == "preprovision":
            client_id = ensure_app_registration(graph, env)
            azd_env_set("AZURE_APP_SERVICE_AUTH_CLIENT_ID", client_id, run)
            print(f"App registration ready: {client_id}")
        else:
            configure_after_provision(graph, env)
            print("App registration redirect URI and federated credential configured.")
    except HookError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
