#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

az bicep build --file "$ROOT/infra/main.bicep" --stdout >/dev/null
python "$ROOT/scripts/check_parameter_files.py"
python "$ROOT/scripts/validate_logic_app.py"

"$ROOT/.venv/bin/python" -m ruff check "$ROOT/scripts"
"$ROOT/.venv/bin/python" -m pytest -q "$ROOT/scripts/tests"

"$ROOT/.venv/bin/python" -m ruff check "$ROOT/app/backend/src" "$ROOT/app/backend/tests"
"$ROOT/.venv/bin/python" -m pytest -q "$ROOT/app/backend/tests"

npm --prefix "$ROOT/app/frontend" test
npm --prefix "$ROOT/app/frontend" run lint
npm --prefix "$ROOT/app/frontend" run build

