#!/bin/bash
# Asserts lint_note.py enforces the AGENTS.md closed enums + verb T-box on
# single notes, and that load_agents_contract parses the verbs table.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/../.."
LINT="$REPO/plugins/ai-os-lite/skills/write-note/scripts/lint_note.py"
AUDIT_DIR="$REPO/plugins/ai-os-lite/skills/vault-audit/scripts"
FIXTURE="$REPO/fixtures/write-note"

fail=0; pass=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=1; }

# --- contract loader parses verb fields from the fixture AGENTS.md ---
VERBS="$(python3 - "$AUDIT_DIR" "$FIXTURE" <<'PY'
import sys, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location(
    "audit_vault", Path(sys.argv[1]) / "audit_vault.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
contract, errs, warns = m.load_agents_contract(Path(sys.argv[2]))
print(",".join(sorted(contract["verb_fields"])) if contract else "ERR:" + ";".join(errs))
PY
)"
expected="blocked_by,goal,informs,owned_by,quarter_goal,unlocks,uses_system"
if [ "$VERBS" = "$expected" ]; then ok "loader parses exact verb_fields set"; else bad "loader verb_fields mismatch: got '$VERBS' want '$expected'"; fi

# --- lint_note.py per-note checks ---
lint() { python3 "$LINT" "$FIXTURE" "$FIXTURE/$1" 2>/dev/null; }

has_v() {  # has_v <file> <check> <kind: violations|warnings>
  local out; out="$(lint "$1")"
  local n; n=$(jq --arg c "$2" "[.${3}[]? | select(.check==\$c)] | length" <<<"$out" 2>/dev/null)
  if [[ "${n:-0}" -ge 1 ]]; then ok "$2 flags $1"; else bad "$2 did NOT flag $1 (got: $out)"; fi
}

out="$(lint "6. Main Notes/good-note.md")"; rc=$?
if [[ $rc -eq 0 ]] && [[ "$(jq '.violations|length' <<<"$out")" == "0" ]]; then
  ok "clean note passes (exit 0, no violations)"
else bad "clean note flagged: rc=$rc $out"; fi

has_v "6. Main Notes/bad-type.md"              invalid_type          violations
has_v "Personal/Tasks/bad-status.md"           invalid_status        violations
has_v "6. Main Notes/bad-verb-value.md"        malformed_verb_value  violations
has_v "6. Main Notes/bad-part-of.md"           forbidden_verb_field  violations
has_v "4. Contacts/People/status-on-person.md" unexpected_status     violations
has_v "6. Main Notes/misrouted-resource.md"    routing_mismatch      warnings
has_v "6. Main Notes/no-type.md"               missing_type          violations
has_v "6. Main Notes/bad-area.md"              invalid_area          violations

lint "6. Main Notes/bad-type.md" >/dev/null; [[ $? -eq 1 ]] && ok "violation exit code is 1" || bad "violation exit code not 1"

# a note that only trips a warning (no violations) must still exit 0
lint "6. Main Notes/misrouted-resource.md" >/dev/null; [[ $? -eq 0 ]] && ok "warnings-only note exits 0" || bad "warnings-only note did not exit 0"

# contract/parse failure (no AGENTS.md in the vault root) must exit 2
EMPTY_VAULT="$(mktemp -d "${TMPDIR:-/tmp}/write-note-empty-vault.XXXXXX")"
python3 "$LINT" "$EMPTY_VAULT" "$FIXTURE/6. Main Notes/good-note.md" >/dev/null 2>&1
rc=$?
[[ $rc -eq 2 ]] && ok "contract/parse failure exits 2" || bad "contract/parse failure exit code not 2 (got $rc)"
rm -rf "$EMPTY_VAULT"

echo; echo "passed=$pass failed_any=$fail"
exit $fail
