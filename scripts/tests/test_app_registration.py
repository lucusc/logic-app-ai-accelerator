import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))

import app_registration as hook  # noqa: E402

BASE_ENV = {
    "AZURE_USE_APP_SERVICE_AUTH": "true",
    "AZURE_ENV_NAME": "dev",
    "AZURE_APP_NAME": "demo",
    "AZURE_TENANT_ID": "tenant-1",
}


class FakeGraph:
    def __init__(self, responses=None):
        self.responses = responses or {}
        self.calls = []

    def request(self, method, path, body=None, headers=None):
        self.calls.append((method, path, body, headers))
        return self.responses.get((method, path), {})

    def bodies(self, method, path):
        return [body for call_method, call_path, body, _ in self.calls
                if call_method == method and call_path == path]


def completed(returncode=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=stdout, stderr=stderr)


def test_main_skips_when_auth_disabled(capsys):
    result = hook.main(
        ["preprovision"],
        env={"AZURE_ENV_NAME": "dev", "AZURE_USE_APP_SERVICE_AUTH": "false"},
        run=pytest.fail,
    )

    assert result == 0
    assert "skipping" in capsys.readouterr().out


def test_auth_is_enabled_by_default():
    assert hook.is_enabled({}) is True


def test_main_rejects_unknown_command():
    assert hook.main(["deploy"], env=BASE_ENV) == 2


def test_preprovision_creates_registration_and_service_principal():
    created = {"id": "obj-1", "appId": "client-1"}
    graph = FakeGraph({
        ("PATCH", "/applications(uniqueName='demo-dev-web')"): created,
        ("GET", "/servicePrincipals(appId='client-1')"): None,
    })

    client_id = hook.ensure_app_registration(graph, BASE_ENV)

    assert client_id == "client-1"
    _, _, upsert_body, upsert_headers = graph.calls[0]
    assert upsert_body["displayName"] == "demo-dev-web"
    assert upsert_headers == {"Prefer": "create-if-missing"}
    settings = graph.bodies("PATCH", "/applications/obj-1")[0]
    assert settings["identifierUris"] == ["api://client-1"]
    assert settings["api"]["requestedAccessTokenVersion"] == 2
    assert settings["api"]["oauth2PermissionScopes"][0]["value"] == "user_impersonation"
    assert settings["web"]["implicitGrantSettings"]["enableIdTokenIssuance"] is True
    assert graph.bodies("POST", "/servicePrincipals") == [{"appId": "client-1"}]


def test_preprovision_reads_registration_when_upsert_returns_no_body():
    graph = FakeGraph({
        ("PATCH", "/applications(uniqueName='demo-dev-web')"): {},
        ("GET", "/applications(uniqueName='demo-dev-web')"): {"id": "obj-1", "appId": "client-1"},
        ("GET", "/servicePrincipals(appId='client-1')"): {"id": "sp-1"},
    })

    assert hook.ensure_app_registration(graph, BASE_ENV) == "client-1"
    assert graph.bodies("POST", "/servicePrincipals") == []


def test_preprovision_uses_existing_client_id():
    env = {**BASE_ENV, "AZURE_APP_SERVICE_AUTH_CLIENT_ID": "client-9"}
    graph = FakeGraph({("GET", "/applications(appId='client-9')"): {"id": "obj-9", "appId": "client-9"}})

    assert hook.ensure_app_registration(graph, env) == "client-9"
    assert not any(path.startswith("/applications(uniqueName") for _, path, _, _ in graph.calls)


def test_preprovision_fails_when_existing_client_id_is_missing():
    env = {**BASE_ENV, "AZURE_APP_SERVICE_AUTH_CLIENT_ID": "missing"}
    graph = FakeGraph({("GET", "/applications(appId='missing')"): None})

    with pytest.raises(hook.HookError, match="missing was not found"):
        hook.ensure_app_registration(graph, env)


def test_api_settings_preserves_existing_values_without_duplicates():
    app = {
        "appId": "client-1",
        "identifierUris": ["api://client-1"],
        "api": {"oauth2PermissionScopes": [{"id": "s1", "value": "user_impersonation"}]},
        "requiredResourceAccess": [
            {"resourceAppId": "other", "resourceAccess": [{"id": "x", "type": "Role"}]},
            {"resourceAppId": hook.GRAPH_APP_ID,
             "resourceAccess": [{"id": hook.GRAPH_USER_READ_SCOPE_ID, "type": "Scope"}]},
        ],
        "web": {"redirectUris": ["https://existing/callback"]},
    }

    settings = hook.api_settings(app)

    assert settings["identifierUris"] == ["api://client-1"]
    assert settings["api"]["oauth2PermissionScopes"] == [{"id": "s1", "value": "user_impersonation"}]
    assert settings["requiredResourceAccess"][0]["resourceAppId"] == "other"
    assert settings["requiredResourceAccess"][1]["resourceAccess"] == [
        {"id": hook.GRAPH_USER_READ_SCOPE_ID, "type": "Scope"}
    ]
    assert settings["web"]["redirectUris"] == ["https://existing/callback"]


def postprovision_env():
    return {
        **BASE_ENV,
        "AZURE_APP_SERVICE_AUTH_CLIENT_ID": "client-1",
        "WEB_APP_URI": "https://app-demo.azurewebsites.net/",
        "WEB_IDENTITY_PRINCIPAL_ID": "mi-principal",
    }


def test_postprovision_adds_redirect_uri_and_federated_credential():
    graph = FakeGraph({
        ("GET", "/applications(appId='client-1')"): {"id": "obj-1", "web": {"redirectUris": []}},
        ("GET", "/applications/obj-1/federatedIdentityCredentials"): {"value": []},
    })

    hook.configure_after_provision(graph, postprovision_env())

    assert graph.bodies("PATCH", "/applications/obj-1") == [
        {"web": {"redirectUris": ["https://app-demo.azurewebsites.net/.auth/login/aad/callback"]}}
    ]
    credential = graph.bodies("POST", "/applications/obj-1/federatedIdentityCredentials")[0]
    assert credential["issuer"] == "https://login.microsoftonline.com/tenant-1/v2.0"
    assert credential["subject"] == "mi-principal"
    assert credential["audiences"] == ["api://AzureADTokenExchange"]


def test_postprovision_is_idempotent():
    callback = "https://app-demo.azurewebsites.net/.auth/login/aad/callback"
    graph = FakeGraph({
        ("GET", "/applications(appId='client-1')"): {"id": "obj-1", "web": {"redirectUris": [callback]}},
        ("GET", "/applications/obj-1/federatedIdentityCredentials"): {"value": [{
            "id": "fic-1",
            "name": hook.FEDERATED_CREDENTIAL_NAME,
            "issuer": "https://login.microsoftonline.com/tenant-1/v2.0",
            "subject": "mi-principal",
        }]},
    })

    hook.configure_after_provision(graph, postprovision_env())

    assert [call[0] for call in graph.calls] == ["GET", "GET"]


def test_postprovision_updates_credential_when_identity_changes():
    graph = FakeGraph({
        ("GET", "/applications(appId='client-1')"): {"id": "obj-1", "web": {"redirectUris": []}},
        ("GET", "/applications/obj-1/federatedIdentityCredentials"): {"value": [{
            "id": "fic-1", "name": hook.FEDERATED_CREDENTIAL_NAME, "issuer": "old", "subject": "old",
        }]},
    })

    hook.configure_after_provision(graph, postprovision_env())

    patch = graph.bodies("PATCH", "/applications/obj-1/federatedIdentityCredentials/fic-1")[0]
    assert patch["subject"] == "mi-principal"


def test_postprovision_requires_provision_outputs():
    env = {**BASE_ENV, "AZURE_APP_SERVICE_AUTH_CLIENT_ID": "client-1"}

    with pytest.raises(hook.HookError, match="WEB_APP_URI"):
        hook.configure_after_provision(FakeGraph(), env)


def test_main_preprovision_stores_client_id(monkeypatch):
    monkeypatch.setattr(hook.shutil, "which", lambda name: name == "azd")
    commands = []

    def run(command, **_):
        commands.append(command)
        if command[:3] == ["azd", "auth", "token"]:
            return completed(stdout=json.dumps({"token": "graph-token"}))
        return completed()

    graph = FakeGraph({
        ("PATCH", "/applications(uniqueName='demo-dev-web')"): {"id": "obj-1", "appId": "client-1"},
    })

    result = hook.main(["preprovision"], env=BASE_ENV, run=run, graph_factory=lambda token, _: graph)

    assert result == 0
    assert "--tenant-id" in commands[0]
    assert commands[-1] == ["azd", "env", "set", "AZURE_APP_SERVICE_AUTH_CLIENT_ID", "client-1"]


def test_main_reports_missing_token(monkeypatch, capsys):
    monkeypatch.setattr(hook.shutil, "which", lambda name: name)

    result = hook.main(["postprovision"], env=BASE_ENV, run=lambda command, **_: completed(returncode=1))

    assert result == 1
    assert "Microsoft Graph token" in capsys.readouterr().err
