import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOGIC_ROOT = ROOT / "app" / "logic"


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main() -> None:
    required_settings: set[str] = set()
    for path in LOGIC_ROOT.rglob("*.json"):
        content = path.read_text(encoding="utf-8")
        load_json(path)
        required_settings.update(re.findall(r"@appsetting\('([^']+)'\)", content))

    settings = load_json(LOGIC_ROOT / "local.settings.example.json")
    values = settings.get("Values", {}) if isinstance(settings, dict) else {}
    missing = sorted(required_settings - set(values))
    if missing:
        raise SystemExit(f"Missing Logic App settings: {', '.join(missing)}")

    workflow = load_json(LOGIC_ROOT / "workflows" / "process-document" / "workflow.json")
    definition = workflow.get("definition", {}) if isinstance(workflow, dict) else {}
    if workflow.get("kind") != "Stateful":
        raise SystemExit("The sample workflow must remain Stateful.")
    if not definition.get("triggers") or not definition.get("actions"):
        raise SystemExit("The sample workflow requires a trigger and actions.")

    print(f"Validated Logic App JSON and {len(required_settings)} app settings.")


if __name__ == "__main__":
    main()

