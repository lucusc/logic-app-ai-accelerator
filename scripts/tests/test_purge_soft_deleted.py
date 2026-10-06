import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))

import purge_soft_deleted as hook  # noqa: E402

ENV = {
    "AZURE_PURGE_SOFT_DELETED_ON_DOWN": "true",
    "AZURE_SUBSCRIPTION_ID": "sub-1",
    "AZURE_AI_RESOURCE_GROUP": "rg-ai",
}


def completed(returncode=0, stdout=""):
    return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=stdout, stderr="")


def test_does_nothing_without_opt_in(capsys):
    assert hook.main(["purge"], env={}, run=lambda *_a, **_k: (_ for _ in ()).throw(AssertionError())) == 0
    assert "keeping soft-deleted" in capsys.readouterr().out


def test_snapshot_records_account_names():
    sets = []

    def run(cmd, **_kwargs):
        if cmd[:3] == ["azd", "env", "set"]:
            sets.append(cmd[3:])
        return completed(stdout='{"token":"t"}')

    accounts = {"value": [{"name": "aif-x", "location": "swedencentral"}]}
    send = lambda *_a: (200, {}, json.dumps(accounts).encode())  # noqa: E731
    assert hook.main(["snapshot"], env=ENV, run=run, send=send) == 0
    assert sets == [[hook.TARGETS, json.dumps(
        [{"name": "aif-x", "location": "swedencentral", "resourceGroup": "rg-ai"}])]]


def test_purge_deletes_recorded_accounts_and_clears_targets():
    calls, sets = [], []
    env = {**ENV, hook.TARGETS: json.dumps(
        [{"name": "aif-x", "location": "swedencentral", "resourceGroup": "rg-ai"}])}

    def run(cmd, **_kwargs):
        if cmd[:3] == ["azd", "env", "set"]:
            sets.append(cmd[3:])
        return completed(stdout='{"token":"t"}')

    def send(method, url, token):
        calls.append((method, url))
        return 204, {}, b""

    assert hook.main(["purge"], env=env, run=run, send=send) == 0
    assert calls[0][0] == "DELETE"
    assert "locations/swedencentral/resourceGroups/rg-ai/deletedAccounts/aif-x" in calls[0][1]
    assert sets == [[hook.TARGETS, "[]"]]
