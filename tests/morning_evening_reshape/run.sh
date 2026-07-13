#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ai-os-lite-morning-brief.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

assert_contains() {
  local label="$1" file="$2" text="$3"
  grep -qF "$text" "$file" || fail "$label"
  pass "$label"
}

assert_absent() {
  local label="$1" file="$2" text="$3"
  if grep -qF "$text" "$file"; then fail "$label"; fi
  pass "$label"
}

VAULT="$TMP/vault"
mkdir -p "$VAULT"

bash "$ROOT/plugins/ai-os-lite/skills/start-day/scripts/ensure_journal.sh" 2026-07-12 "$VAULT" >/dev/null
bash "$ROOT/plugins/ai-os-lite/skills/start-day/scripts/ensure_daily_hub.sh" 2026-07-12 "$VAULT" >/dev/null

MORNING="$VAULT/5. Resources/Personal/Journal/Morning Entries/2026-07-12.md"
DAILY="$VAULT/1. Daily/2026-07-12.md"
EVENING_SKILL="$ROOT/plugins/ai-os-lite/skills/process-evening/SKILL.md"
PREP_SKILL="$ROOT/plugins/ai-os-lite/skills/prep-evening/SKILL.md"

assert_contains "Morning Brief completion field" "$MORNING" "habit_morning_brief: false"
assert_absent "no starter journaling habit" "$MORNING" "habit_journaled"
assert_absent "no starter exercise habit" "$MORNING" "habit_exercise"
assert_contains "daily hub Morning Brief heading" "$DAILY" "## Morning Brief"
assert_contains "daily hub Morning Brief link" "$DAILY" "Open Morning Brief"
assert_absent "daily hub has no prescribed evening-reflection heading" "$DAILY" "## Evening Reflection"

assert_contains "Evening completion field" "$PREP_SKILL" "habit_evening_reflection: false"
for file in "$PREP_SKILL" "$EVENING_SKILL"; do
  assert_absent "no prescribed what-went-well prompt in $(basename "$(dirname "$file")")" "$file" "**What went well today:**"
  assert_absent "no prescribed improvement prompt in $(basename "$(dirname "$file")")" "$file" "**What could I improve:**"
  assert_absent "no prescribed gratitude count in $(basename "$(dirname "$file")")" "$file" "What are 3 things you're grateful for?"
done

python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
scripts = root / "plugins/ai-os-lite/skills/process-morning/scripts"
sys.path.insert(0, str(scripts))
from write_ai_summary import replace_ai_summary, upsert_frontmatter_bool

source = "---\ntype: journal\nhabit_morning_brief: false\n---\n\n## Morning\nraw words\n\n### AI Summary\nplaceholder\n"
updated = replace_ai_summary(source, "**Summary**: grounded")
updated = upsert_frontmatter_bool(updated, "habit_morning_brief", True)
assert "habit_morning_brief: true" in updated
assert "raw words" in updated
assert "**Summary**: grounded" in updated
PY
pass "Morning Brief writer stamps completion without touching raw input"

assert_contains "plugin registers process-morning" "$ROOT/plugins/ai-os-lite/.claude-plugin/plugin.json" '"./skills/process-morning"'

if rg -n '/Users/|Yandi|Evonik|Amerinkas|Adoptify|CogniSphere|Metacrylate|Managed AI|RS42' "$ROOT/plugins/ai-os-lite/skills" >/dev/null; then
  fail "privacy scan found founder/company-specific runtime content"
fi
pass "privacy scan has no founder/company-specific runtime content"

if rg -n 'process-journal' "$ROOT/plugins" "$ROOT/README.md" "$ROOT/.claude-plugin" >/dev/null; then
  fail "legacy process-journal identifier remains"
fi
pass "legacy process-journal identifier removed"
