"""Optionally purge soft-deleted Cognitive Services accounts after `azd down`.

Opt in with `azd env set AZURE_PURGE_SOFT_DELETED_ON_DOWN true`. Without it the hook does nothing,
so soft-delete protection stays in effect for real environments.

azd clears deployment outputs during `down`, so `snapshot` (predown) records the account names in
AZURE_SOFT_DELETE_PURGE_TARGETS and `purge` (postdown) consumes them.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from collections.abc import Callable, Mapping

from teardown_monitoring import (
    MANAGEMENT_ENDPOINT,
    HookError,
    Request,
    Runner,
    get_token,
    header,
    request,
    wait_for_operation,
)

API_VERSION = "2025-04-01-preview"
OPT_IN = "AZURE_PURGE_SOFT_DELETED_ON_DOWN"
TARGETS = "AZURE_SOFT_DELETE_PURGE_TARGETS"


def is_enabled(env: Mapping[str, str]) -> bool:
    return env.get(OPT_IN, "").strip().lower() == "true"


def azd_env_set(name: str, value: str, run: Runner) -> None:
    result = run(["azd", "env", "set", name, value], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise HookError(f"azd env set {name} failed: {result.stderr.strip()}")


def snapshot(env: Mapping[str, str], token: str, send: Request, run: Runner) -> list[dict[str, str]]:
    resource_group = env.get("AZURE_AI_RESOURCE_GROUP", "").strip()
    subscription_id = env.get("AZURE_SUBSCRIPTION_ID", "").strip()
    if not resource_group or not subscription_id:
        return []
    url = (
        f"{MANAGEMENT_ENDPOINT}/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
        f"/providers/Microsoft.CognitiveServices/accounts?api-version={API_VERSION}"
    )
    status, _, body = send("GET", url, token)
    if status == 404:
        return []
    if status != 200:
        raise HookError(f"Unable to list Cognitive Services accounts: HTTP {status}: {body.decode(errors='replace')}")
    targets = [
        {"name": account["name"], "location": account["location"], "resourceGroup": resource_group}
        for account in json.loads(body).get("value", [])
    ]
    azd_env_set(TARGETS, json.dumps(targets), run)
    return targets


def purge(env: Mapping[str, str], token: str, send: Request, sleep: Callable[[float], None],
          run: Runner) -> int:
    subscription_id = env.get("AZURE_SUBSCRIPTION_ID", "").strip()
    targets = json.loads(env.get(TARGETS, "") or "[]")
    purged = 0
    for target in targets:
        url = (
            f"{MANAGEMENT_ENDPOINT}/subscriptions/{subscription_id}/providers/Microsoft.CognitiveServices"
            f"/locations/{target['location']}/resourceGroups/{target['resourceGroup']}"
            f"/deletedAccounts/{target['name']}?api-version={API_VERSION}"
        )
        status, headers, body = send("DELETE", url, token)
        if status == 404:
            continue
        if status not in {200, 202, 204}:
            raise HookError(f"Unable to purge {target['name']}: HTTP {status}: {body.decode(errors='replace')}")
        operation_url = header(headers, "Azure-AsyncOperation") or header(headers, "Location")
        if status == 202 and operation_url:
            wait_for_operation(operation_url, token, send, sleep)
        print(f"Purged soft-deleted account {target['name']}.")
        purged += 1
    azd_env_set(TARGETS, "[]", run)
    return purged


def main(argv: list[str], env: Mapping[str, str] | None = None, run: Runner = subprocess.run,
         send: Request = request, sleep: Callable[[float], None] = time.sleep) -> int:
    env = os.environ if env is None else env
    if len(argv) != 1 or argv[0] not in {"snapshot", "purge"}:
        print("Usage: purge_soft_deleted.py snapshot|purge", file=sys.stderr)
        return 2
    if not is_enabled(env):
        print(f"{OPT_IN} is not true; keeping soft-deleted accounts.")
        return 0
    try:
        token = get_token(run)
        if argv[0] == "snapshot":
            snapshot(env, token, send, run)
        else:
            purge(env, token, send, sleep, run)
    except HookError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
