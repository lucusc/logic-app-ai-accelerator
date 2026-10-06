import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))

import teardown_monitoring as hook  # noqa: E402

BASE_ENV = {
    "AZURE_ENV_NAME": "private",
    "AZURE_SUBSCRIPTION_ID": "sub-1",
    "AZURE_OPERATIONS_RESOURCE_GROUP": "rg-ops",
    "AZURE_MONITOR_PRIVATE_LINK_SCOPE_NAME": "ampls-private",
}


def completed(returncode=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=stdout, stderr=stderr)


def test_main_skips_when_monitoring_is_not_application_owned(capsys):
    assert hook.main(env={}, run=pytest.fail) == 0
    assert "skipping" in capsys.readouterr().out


def test_delete_scope_uses_configured_name_and_waits_for_operation():
    calls = []

    def send(method, url, token):
        if "privateEndpoints" in url:
            return 200, {}, b'{"value":[]}'
        calls.append((method, url, token))
        if method == "DELETE":
            return 202, {"Azure-AsyncOperation": "https://operation"}, b""
        return 200, {"Retry-After": "0"}, b'{"status":"Succeeded"}'

    assert hook.delete_scope(BASE_ENV, "token", send, sleep=lambda _: None)
    assert calls == [
        ("DELETE", hook.scope_url("sub-1", "rg-ops", "ampls-private"), "token"),
        ("GET", "https://operation", "token"),
    ]


def test_delete_scope_finds_scope_for_preexisting_environment():
    collection = hook.management_url(
        "/subscriptions/sub-1/resourceGroups/rg-ops/providers/Microsoft.Insights/privateLinkScopes"
    )
    calls = []

    def send(method, url, token):
        if "privateEndpoints" in url:
            return 200, {}, b'{"value":[]}'
        calls.append((method, url))
        if url == collection:
            return 200, {}, json.dumps({"value": [{
                "name": "ampls-discovered",
                "tags": {"azd-env-name": "private", "Repository": "logic-app-ai-accelerator"},
            }]}).encode()
        return 204, {}, b""

    assert hook.delete_scope({key: value for key, value in BASE_ENV.items()
                              if key != "AZURE_MONITOR_PRIVATE_LINK_SCOPE_NAME"}, "token", send)
    assert calls == [
        ("GET", collection),
        ("DELETE", hook.scope_url("sub-1", "rg-ops", "ampls-discovered")),
    ]


def test_delete_scope_skips_missing_scope(capsys):
    assert not hook.delete_scope(BASE_ENV, "token", lambda *_: (404, {}, b""))
    assert "already deleted" in capsys.readouterr().out


def test_main_surfaces_token_failure(capsys):
    assert hook.main(env=BASE_ENV, run=lambda *_args, **_kwargs: completed(returncode=1, stderr="not signed in")) == 1
    assert "not signed in" in capsys.readouterr().err


SCOPE_ID = "/subscriptions/sub-1/resourceGroups/rg-ops/providers/microsoft.insights/privateLinkScopes/ampls-private"


def endpoint(name, status, service_id=SCOPE_ID):
    return {
        "id": f"/subscriptions/sub-1/resourceGroups/rg-ops/providers/Microsoft.Network/privateEndpoints/{name}",
        "name": name,
        "properties": {"privateLinkServiceConnections": [{"properties": {
            "privateLinkServiceId": service_id,
            "privateLinkServiceConnectionState": {"status": status},
        }}]},
    }


def endpoint_sender(endpoints, calls):
    def send(method, url, token):
        calls.append((method, url))
        if method == "GET":
            return 200, {}, json.dumps({"value": endpoints}).encode()
        return 204, {}, b""
    return send


def test_repair_deletes_only_disconnected_scope_endpoints(capsys):
    calls = []
    send = endpoint_sender([
        endpoint("pe-stale", "Disconnected"),
        endpoint("pe-healthy", "Approved"),
        endpoint("pe-storage", "Disconnected", "/subscriptions/sub-1/providers/Microsoft.Storage/storageAccounts/s"),
    ], calls)
    token_run = lambda *_a, **_k: completed(stdout='{"token":"t"}')  # noqa: E731
    assert hook.main(env=BASE_ENV, run=token_run, send=send, argv=["repair"]) == 0
    assert [c[0] for c in calls] == ["GET", "DELETE"]
    assert "pe-stale" in calls[1][1]
    assert "Deleted private endpoint pe-stale" in capsys.readouterr().out


def test_delete_scope_removes_scope_endpoints_before_scope():
    calls = []
    send = endpoint_sender([endpoint("pe-ampls", "Approved")], calls)
    assert hook.delete_scope(BASE_ENV, "token", send, sleep=lambda _: None)
    assert [c[0] for c in calls] == ["GET", "DELETE", "DELETE"]
    assert "privateEndpoints/pe-ampls" in calls[1][1]
    assert "privateLinkScopes/ampls-private" in calls[2][1]
