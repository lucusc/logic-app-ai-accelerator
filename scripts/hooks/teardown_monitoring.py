"""Remove the project-managed AMPLS (and its private endpoints) around azd teardown and provisioning."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping

API_VERSION = "2021-07-01-preview"
PRIVATE_ENDPOINT_API_VERSION = "2024-05-01"
MANAGEMENT_ENDPOINT = "https://management.azure.com"
MAX_POLL_ATTEMPTS = 60

Runner = Callable[..., subprocess.CompletedProcess]
Request = Callable[[str, str, str], tuple[int, Mapping[str, str], bytes]]


class HookError(RuntimeError):
    pass


def require(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise HookError(f"{name} is required in the azd environment.")
    return value


def management_url(path: str, api_version: str = API_VERSION) -> str:
    return f"{MANAGEMENT_ENDPOINT}{path}?api-version={api_version}"


def request(method: str, url: str, token: str) -> tuple[int, Mapping[str, str], bytes]:
    azure_request = urllib.request.Request(url, method=method)
    azure_request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(azure_request, timeout=60) as response:
            return response.status, dict(response.headers.items()), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers.items()), error.read()
    except urllib.error.URLError as error:
        raise HookError(f"Azure Resource Manager {method} {url} failed: {error.reason}") from error


def get_token(run: Runner) -> str:
    result = run(
        ["azd", "auth", "token", "--scope", f"{MANAGEMENT_ENDPOINT}/.default", "--output", "json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HookError(f"Unable to get an Azure Resource Manager token: {result.stderr.strip()}")
    try:
        token = json.loads(result.stdout)["token"]
    except (KeyError, json.JSONDecodeError) as error:
        raise HookError("azd returned an invalid Azure Resource Manager token response.") from error
    if not token:
        raise HookError("azd returned an empty Azure Resource Manager token.")
    return token


def header(headers: Mapping[str, str], name: str) -> str:
    return next((value for key, value in headers.items() if key.lower() == name.lower()), "")


def scope_url(subscription_id: str, resource_group: str, scope_name: str) -> str:
    return management_url(
        f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
        f"/providers/Microsoft.Insights/privateLinkScopes/{scope_name}"
    )


def find_scope_name(env: Mapping[str, str], token: str, send: Request) -> str | None:
    configured_name = env.get("AZURE_MONITOR_PRIVATE_LINK_SCOPE_NAME", "").strip()
    if configured_name:
        return configured_name

    subscription_id = require(env, "AZURE_SUBSCRIPTION_ID")
    resource_group = require(env, "AZURE_OPERATIONS_RESOURCE_GROUP")
    environment_name = require(env, "AZURE_ENV_NAME")
    collection_url = management_url(
        f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
        "/providers/Microsoft.Insights/privateLinkScopes"
    )
    status, _, body = send("GET", collection_url, token)
    if status == 404:
        return None
    if status != 200:
        raise HookError(
            f"Unable to list Azure Monitor Private Link Scopes: HTTP {status}: "
            f"{body.decode(errors='replace')}"
        )

    scopes = json.loads(body).get("value", [])
    matches = [
        scope["name"]
        for scope in scopes
        if (scope.get("tags") or {}).get("azd-env-name") == environment_name
        and (scope.get("tags") or {}).get("Repository") == "logic-app-ai-accelerator"
    ]
    if len(matches) > 1:
        raise HookError(
            "Multiple project-managed Azure Monitor Private Link Scopes were found; "
            "set AZURE_MONITOR_PRIVATE_LINK_SCOPE_NAME before retrying teardown."
        )
    return matches[0] if matches else None


def wait_for_operation(operation_url: str, token: str, send: Request,
                       sleep: Callable[[float], None]) -> None:
    for _ in range(MAX_POLL_ATTEMPTS):
        status, headers, body = send("GET", operation_url, token)
        if status != 200:
            raise HookError(
                f"Unable to poll Azure Monitor Private Link Scope deletion: HTTP {status}: "
                f"{body.decode(errors='replace')}"
            )
        state = json.loads(body).get("status", "")
        if state == "Succeeded":
            return
        if state in {"Failed", "Canceled"}:
            raise HookError(
                f"Azure Monitor Private Link Scope deletion {state.lower()}: "
                f"{body.decode(errors='replace')}"
            )
        sleep(float(header(headers, "Retry-After") or 5))
    raise HookError("Timed out waiting for Azure Monitor Private Link Scope deletion.")


def private_endpoints_url(env: Mapping[str, str]) -> str:
    return management_url(
        f"/subscriptions/{require(env, 'AZURE_SUBSCRIPTION_ID')}"
        f"/resourceGroups/{require(env, 'AZURE_OPERATIONS_RESOURCE_GROUP')}"
        "/providers/Microsoft.Network/privateEndpoints",
        PRIVATE_ENDPOINT_API_VERSION,
    )


def delete_private_endpoints(env: Mapping[str, str], token: str, send: Request,
                             sleep: Callable[[float], None], only_disconnected: bool) -> int:
    """Delete AMPLS private endpoints; Azure cannot update an endpoint whose scope was deleted."""
    status, _, body = send("GET", private_endpoints_url(env), token)
    if status == 404:
        return 0
    if status != 200:
        raise HookError(f"Unable to list private endpoints: HTTP {status}: {body.decode(errors='replace')}")

    deleted = 0
    for endpoint in json.loads(body).get("value", []):
        connections = (endpoint.get("properties", {}).get("privateLinkServiceConnections") or []) + (
            endpoint.get("properties", {}).get("manualPrivateLinkServiceConnections") or [])
        targets_scope = any(
            "/providers/microsoft.insights/privatelinkscopes/" in
            (c.get("properties", {}).get("privateLinkServiceId") or "").lower()
            for c in connections
        )
        disconnected = any(
            (c.get("properties", {}).get("privateLinkServiceConnectionState") or {}).get("status") == "Disconnected"
            for c in connections
        )
        if not targets_scope or (only_disconnected and not disconnected):
            continue
        url = f"{MANAGEMENT_ENDPOINT}{endpoint['id']}?api-version={PRIVATE_ENDPOINT_API_VERSION}"
        status, headers, body = send("DELETE", url, token)
        if status not in {200, 202, 204}:
            raise HookError(
                f"Unable to delete private endpoint {endpoint['name']}: HTTP {status}: "
                f"{body.decode(errors='replace')}"
            )
        operation_url = header(headers, "Azure-AsyncOperation") or header(headers, "Location")
        if status == 202 and operation_url:
            wait_for_operation(operation_url, token, send, sleep)
        print(f"Deleted private endpoint {endpoint['name']}.")
        deleted += 1
    return deleted


def delete_scope(env: Mapping[str, str], token: str, send: Request = request,
                 sleep: Callable[[float], None] = time.sleep) -> bool:
    delete_private_endpoints(env, token, send, sleep, only_disconnected=False)
    scope_name = find_scope_name(env, token, send)
    if scope_name is None:
        print("No project-managed Azure Monitor Private Link Scope found; skipping.")
        return False

    url = scope_url(require(env, "AZURE_SUBSCRIPTION_ID"), require(env, "AZURE_OPERATIONS_RESOURCE_GROUP"), scope_name)
    status, headers, body = send("DELETE", url, token)
    if status == 404:
        print(f"Azure Monitor Private Link Scope {scope_name} is already deleted.")
        return False
    if status not in {200, 202, 204}:
        raise HookError(
            f"Unable to delete Azure Monitor Private Link Scope {scope_name}: HTTP {status}: "
            f"{body.decode(errors='replace')}"
        )

    operation_url = header(headers, "Azure-AsyncOperation") or header(headers, "Location")
    if status == 202:
        if not operation_url:
            raise HookError("Azure Monitor Private Link Scope deletion returned 202 without an operation URL.")
        wait_for_operation(operation_url, token, send, sleep)
    print(f"Deleted Azure Monitor Private Link Scope {scope_name}.")
    return True


def main(env: Mapping[str, str] | None = None, run: Runner = subprocess.run,
         send: Request = request, sleep: Callable[[float], None] = time.sleep,
         argv: list[str] | None = None) -> int:
    env = os.environ if env is None else env
    repair = (sys.argv[1:] if argv is None else argv) == ["repair"]
    if not env.get("AZURE_OPERATIONS_RESOURCE_GROUP", "").strip():
        print("No application-owned monitoring resources configured; skipping.")
        return 0
    try:
        token = get_token(run)
        if repair:
            delete_private_endpoints(env, token, send, sleep, only_disconnected=True)
        else:
            delete_scope(env, token, send, sleep)
    except HookError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
