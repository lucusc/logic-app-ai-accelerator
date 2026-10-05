"""Type-check the example ARM parameter files and the azd bicepparam file against infra/main.bicep."""

import json
import subprocess
import sys
from pathlib import Path

INFRA = Path(__file__).resolve().parents[1] / "infra"


def build_params(path: Path, env: dict[str, str] | None = None) -> None:
    result = subprocess.run(
        ["az", "bicep", "build-params", "--file", str(path), "--stdout"],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    diagnostics = [line for line in result.stderr.splitlines() if " Error " in line or " Warning " in line]
    if result.returncode != 0 or diagnostics:
        raise SystemExit(f"{path.name} failed:\n" + "\n".join(diagnostics or [result.stderr]))


def main() -> None:
    for example in sorted(INFRA.glob("*.parameters.example.json")):
        names = json.loads(example.read_text(encoding="utf-8"))["parameters"]
        check = INFRA / f".check-{example.stem}.bicepparam"
        lines = [
            "using './main.bicep'",
            f"var p = loadJsonContent('{example.name}').parameters",
            *[f"param {name} = p.{name}.value" for name in names],
        ]
        check.write_text("\n".join(lines) + "\n", encoding="utf-8")
        try:
            build_params(check)
        finally:
            check.unlink()
        print(f"Validated {example.name}")

    build_params(INFRA / "main.bicepparam")
    print("Validated main.bicepparam")


if __name__ == "__main__":
    sys.exit(main())
