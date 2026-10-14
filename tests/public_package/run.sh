#!/usr/bin/env bash
# Isolated, no-account first-use check with a synthetic local review fixture.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-os-first-use.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT
VAULT="$RUN_DIR/demo"
export PYTHONDONTWRITEBYTECODE=1 AI_OS_LOCAL_ONLY=1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Seed only this disposable workspace; no production auto-acceptance path exists.
python3 - "$ROOT" "$VAULT" <<'PYREVIEW'
import pathlib, sys
root, workspace = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(root/'setup/tools'))
from license_consent import load_policy, make_receipt, save_receipt
policy = load_policy(root)
save_receipt(workspace.resolve(), policy, make_receipt(policy, 'Synthetic Test User', 'personal'))
PYREVIEW
bash "$ROOT/setup/setup-vault.sh" "$VAULT" > "$RUN_DIR/setup.log"
bash "$ROOT/plugins/ai-os-lite/skills/start-day/scripts/gather_morning_context.sh" 2026-10-12 "$VAULT" > "$RUN_DIR/context.json"
python3 "$ROOT/plugins/ai-os-lite/skills/start-day/scripts/render_start_day.py" "$RUN_DIR/context.json" > "$RUN_DIR/brief.md"
python3 - "$VAULT" "$RUN_DIR" <<'PY'
import hashlib, json, sys
from pathlib import Path
vault, run = map(Path, sys.argv[1:])
data = json.loads((run/'context.json').read_text())
assert data['task_notes']['count'] == 3
assert data['task_notes']['todo_count'] == 3
assert data['task_notes']['source'] == 'filesystem'
assert data['source_manifest']['todoist'].startswith('skipped:')
brief = (run/'brief.md').read_text()
assert 'Add my first project' in brief
assert '### Control Queue' in brief
assert 'not wired' not in brief
assert (vault/'AGENTS.md').read_bytes()
# Owner customization and short daily note must survive repeat setup/scaffold.
(vault/'Personal/Personal.md').write_text('My custom dashboard.\n')
(vault/'1. Daily/2026-10-12.md').write_text('My short daily note.\n')
snapshot = {str(p.relative_to(vault)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in vault.rglob('*') if p.is_file() and '.git' not in p.parts}
(run/'before.json').write_text(json.dumps(snapshot))
PY
bash "$ROOT/setup/setup-vault.sh" "$VAULT" > "$RUN_DIR/repeat.log"
bash "$ROOT/plugins/ai-os-lite/skills/start-day/scripts/ensure_daily_hub.sh" 2026-10-12 "$VAULT" > "$RUN_DIR/hub.json"
python3 - "$VAULT" "$RUN_DIR" <<'PY'
import hashlib, json, sys
from pathlib import Path
vault, run = map(Path, sys.argv[1:])
before = json.loads((run/'before.json').read_text())
after = {str(p.relative_to(vault)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in vault.rglob('*') if p.is_file() and '.git' not in p.parts}
assert before == after, 'repeat setup changed existing content'
assert not json.loads((run/'hub.json').read_text())['created']
print('PASS: synthetic-review no-account setup → three tasks → useful brief → customized repeat preservation')
PY
