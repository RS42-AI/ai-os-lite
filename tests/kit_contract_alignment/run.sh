#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$ROOT/plugins/ai-os-lite/skills/vault-audit/scripts/audit_vault.py"
REPAIR="$ROOT/plugins/ai-os-lite/skills/vault-audit/scripts/repair_structure.py"
LINT="$ROOT/plugins/ai-os-lite/skills/write-note/scripts/lint_note.py"
PROJECT_CONTEXT="$ROOT/plugins/ai-os-lite/skills/project-sync/scripts/gather_project_context.sh"
LITE_STRUCTURE="$ROOT/plugins/ai-os-lite/skills/vault-audit/references/project-structure.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lite-kit-contract.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
VAULT="$TMP/vault"

pass=0
fail=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
assert_eq() {
  local label="$1" got="$2" want="$3"
  [[ "$got" == "$want" ]] && ok "$label" || bad "$label (got '$got', want '$want')"
}

KIT_STRUCTURE_PROFILE="${KIT_STRUCTURE_PROFILE:-$ROOT/setup/structure/project-structure.json}"
if [[ -f "$KIT_STRUCTURE_PROFILE" ]]; then
  if cmp -s "$LITE_STRUCTURE" "$KIT_STRUCTURE_PROFILE"; then
    ok "Lite and Kit ship the same project-structure schema"
  else
    bad "Lite and Kit project-structure schemas differ"
  fi
fi

mkdir -p "$VAULT/system-settings/Contracts" "$VAULT/system-settings/Templates"
cat > "$VAULT/AGENTS.md" <<'EOF'
# Portable fixture contract

| Area folder | `area` slug |
|---|---|
| `3. Areas/7. Studio/` | `studio` |
| `Personal/` | `personal` |

| Value | Description | Where it lives |
|---|---|---|
| `project` | Project hub | `2. Projects/{Area}/{Project}/` or `Personal/2. Projects/{Project}/` |
| `task` | Action | `*/Tasks/` |
| `resource` | Curated reference | `5. Resources/{Area}/` or `{Project}/Resources/` |
| `journal` | Daily reflection | `5. Resources/Personal/Journal/` |

| `type` | allowed `status` (progression →) | pause / terminal |
|---|---|---|
| `project` | `draft` → `active` → `done` | `on-hold`, `superseded`, `archived` |
| `task` | `todo` → `active` → `done` | `on-hold`, `archived` |
| `journal`, `resource` | *(no `status` field)* | — |

| Verb | Meaning (A —verb→ B) | Written as |
|---|---|---|
| `serves_goal` | work advances a goal | `goal:` |
| `part_of` | containment | `project:` / `area:` — **never a separate field** |
EOF

cat > "$VAULT/system-settings/Contracts/node-contract.json" <<'EOF'
{"schema_version":1,"approvals":{},"profiles":{"project":{"state":"candidate","enforcement_scope":"writer_only","required_fields":["date","type","status","area","project"]}}}
EOF
cat > "$VAULT/system-settings/Contracts/body-contract.json" <<'EOF'
{"schema_version":1,"approvals":{},"profiles":{"project":{"state":"candidate","enforcement_scope":"writer_only","anchors":[{"label":"Overview","min_count":1}]}}}
EOF
cat > "$VAULT/system-settings/Contracts/relationship-contract.json" <<'EOF'
{"schema_version":1,"approvals":{},"profiles":{"goal":{"state":"candidate","enforcement_scope":"writer_only","verb":"serves_goal"}}}
EOF
cat > "$VAULT/system-settings/Templates/Project Hub Template.md" <<'EOF'
---
type: project
status: draft
---
## Overview
## Current Status
EOF

make_hub() {
  local path="$1" area="$2" slug="$3"
  mkdir -p "$(dirname "$VAULT/$path")"
  cat > "$VAULT/$path" <<EOF
---
date: 2026-09-06
type: project
status: draft
area: $area
project: $slug
---

# $(basename "$path" .md)

## Human-owned context

No standard prose has been supplied.
EOF
}

make_hub "2. Projects/7. Studio/Collection/Launch Space/Launch Space.md" studio launch
mkdir -p "$VAULT/2. Projects/7. Studio/Collection/Launch Space/Tasks"
make_hub "Personal/2. Projects/Home Plan/Home Plan.md" personal home-plan
for folder in Tasks Notes Resources Artifacts Specs "Dev Log"; do
  mkdir -p "$VAULT/Personal/2. Projects/Home Plan/$folder"
done
make_hub "Personal/Legacy Trip/PROJECT.md" personal legacy-trip

mkdir -p "$VAULT/2. Projects/7. Studio/Tasks" \
  "$VAULT/Personal/Tasks" \
  "$VAULT/5. Resources/7. Studio" \
  "$VAULT/5. Resources/Personal/Journal/Morning Entries"
cat > "$VAULT/2. Projects/7. Studio/Tasks/Area Task.md" <<'EOF'
---
date: 2026-09-06
type: task
status: todo
area: studio
priority: p2
---
# Area Task
EOF
cat > "$VAULT/Personal/Tasks/Wrong Business Route.md" <<'EOF'
---
date: 2026-09-06
type: task
status: todo
area: studio
priority: p2
---
# Wrong Business Route
EOF
cat > "$VAULT/2. Projects/7. Studio/Collection/Launch Space/Tasks/Launch Task.md" <<'EOF'
---
date: 2026-09-06
type: task
status: todo
area: studio
project: launch
priority: p2
---
# Launch Task

> **Project**: [[Launch Space]]
EOF
cat > "$VAULT/5. Resources/7. Studio/Reference.md" <<'EOF'
---
date: 2026-09-06
type: resource
area: studio
---
# Reference
EOF
cat > "$VAULT/5. Resources/Personal/Journal/Morning Entries/2026-09-06.md" <<'EOF'
---
date: 2026-09-06
type: journal
area: personal
---
# Morning Brief
EOF

AUDIT_JSON="$TMP/audit.json"
python3 "$AUDIT" "$VAULT" --no-fail > "$AUDIT_JSON" 2> "$TMP/banner"
assert_eq "candidate body profile is advisory" \
  "$(jq -r '.contract_coverage.families.body.candidate | join(",")' "$AUDIT_JSON")" "project"
assert_eq "candidate project headings are not enforced" \
  "$(jq '[.issues[] | select(.check | startswith("structure.section"))] | length' "$AUDIT_JSON")" "0"
assert_eq "audit reports zero machine-profile checks as implemented" \
  "$(jq '[.contract_coverage.implemented_audit[] | .[]] | length' "$AUDIT_JSON")" "0"
assert_eq "missing template contract is reported" \
  "$(jq '[.contract_coverage.missing_files[] | select(contains("template-contract.json"))] | length' "$AUDIT_JSON")" "1"
assert_eq "business task under Personal is rejected" \
  "$(jq '[.issues[] | select(.file == "Personal/Tasks/Wrong Business Route.md" and .check == "routing.task")] | length' "$AUDIT_JSON")" "1"
assert_eq "all missing project containers are counted" \
  "$(jq '.by_check["structure.project_container_missing"]' "$AUDIT_JSON")" "11"

mkdir -p "$VAULT/system-settings/Contracts"
printf '[]\n' > "$VAULT/system-settings/Contracts/project-structure.json"
python3 "$AUDIT" "$VAULT" --no-fail > "$TMP/audit-malformed-structure.json" 2> "$TMP/banner-malformed-structure"
assert_eq "malformed installed structure contract falls back safely" \
  "$(jq -r '.structure_contract.required_project_containers | join(",")' "$TMP/audit-malformed-structure.json")" \
  "Tasks,Notes,Resources,Artifacts,Specs,Dev Log"
rm "$VAULT/system-settings/Contracts/project-structure.json"

python3 "$LINT" "$VAULT" "$VAULT/2. Projects/7. Studio/Collection/Launch Space/Tasks/Launch Task.md" > "$TMP/lint-good.json"
assert_eq "valid customized project task passes lint" \
  "$(jq '.violations | length' "$TMP/lint-good.json")" "0"
assert_eq "lint reports candidate profile coverage" \
  "$(jq -r '.contract_coverage.families.node.candidate | join(",")' "$TMP/lint-good.json")" "project"
if python3 "$LINT" "$VAULT" "$VAULT/Personal/Tasks/Wrong Business Route.md" > "$TMP/lint-bad.json"; then
  bad "writer lint rejects a business task under Personal"
else
  assert_eq "writer lint rejects a business task under Personal" \
    "$(jq '[.violations[] | select(.check == "routing_contract_mismatch")] | length' "$TMP/lint-bad.json")" "1"
fi

cat > "$VAULT/2. Projects/7. Studio/Collection/Launch Space/Tasks/Missing Anchor.md" <<'EOF'
---
date: 2026-09-06
type: task
status: todo
area: studio
project: launch
priority: p2
---
# Missing Anchor
EOF
python3 - "$VAULT/system-settings/Contracts/body-contract.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
profile = {
    "state": "ratified",
    "enforcement_scope": "writer_only",
    "anchors": [{
        "label": "Project",
        "min_count": 1,
        "required_when": {"frontmatter_field": "project", "operator": "nonempty"},
    }],
}
digest = hashlib.sha256(
    json.dumps(profile, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
path.write_text(json.dumps({
    "schema_version": 1,
    "profiles": {"task": profile},
    "approvals": {"task": {"profile_digest": f"sha256:{digest}"}},
}, indent=2) + "\n")
PY
python3 "$LINT" "$VAULT" "$VAULT/2. Projects/7. Studio/Collection/Launch Space/Tasks/Launch Task.md" > "$TMP/lint-ratified-good.json"
assert_eq "ratified writer body contract accepts rendered anchor" \
  "$(jq '.violations | length' "$TMP/lint-ratified-good.json")" "0"
assert_eq "lint names its implemented ratified writer profile" \
  "$(jq -r '.contract_coverage.implemented_writer.body | join(",")' "$TMP/lint-ratified-good.json")" "task"
if python3 "$LINT" "$VAULT" "$VAULT/2. Projects/7. Studio/Collection/Launch Space/Tasks/Missing Anchor.md" > "$TMP/lint-anchor-bad.json"; then
  bad "ratified writer body contract rejects a missing required anchor"
else
  assert_eq "ratified writer body contract rejects missing required anchor" \
    "$(jq '[.violations[] | select(.check == "missing_body_anchor")] | length' "$TMP/lint-anchor-bad.json")" "1"
fi

JOURNAL_HASH_BEFORE="$(shasum -a 256 "$VAULT/5. Resources/Personal/Journal/Morning Entries/2026-09-06.md" | awk '{print $1}')"
HUB_HASH_BEFORE="$(shasum -a 256 "$VAULT/Personal/Legacy Trip/PROJECT.md" | awk '{print $1}')"
python3 "$REPAIR" "$VAULT" > "$TMP/repair-dry.txt"
[[ ! -d "$VAULT/Personal/Legacy Trip/Artifacts" ]] && ok "repair dry run makes no folders" || bad "repair dry run mutated fixture"
grep -q "11 project containers need creation" "$TMP/repair-dry.txt" && ok "repair previews exact container count" || bad "repair preview count"
python3 "$REPAIR" "$VAULT" --apply > "$TMP/repair-apply.txt"
missing=0
for root in \
  "$VAULT/2. Projects/7. Studio/Collection/Launch Space" \
  "$VAULT/Personal/2. Projects/Home Plan" \
  "$VAULT/Personal/Legacy Trip"; do
  for folder in Tasks Notes Resources Artifacts Specs "Dev Log"; do
    [[ -d "$root/$folder" ]] || missing=$((missing + 1))
  done
done
assert_eq "repair creates all six containers at supported and legacy roots" "$missing" "0"
assert_eq "repair preserves legacy hub content" \
  "$(shasum -a 256 "$VAULT/Personal/Legacy Trip/PROJECT.md" | awk '{print $1}')" "$HUB_HASH_BEFORE"
assert_eq "repair preserves journal behavior and content" \
  "$(shasum -a 256 "$VAULT/5. Resources/Personal/Journal/Morning Entries/2026-09-06.md" | awk '{print $1}')" "$JOURNAL_HASH_BEFORE"
[[ -f "$VAULT/Personal/Legacy Trip/PROJECT.md" && ! -e "$VAULT/Personal/2. Projects/Legacy Trip" ]] \
  && ok "Lite repair leaves legacy path moves to Kit approval" \
  || bad "Lite repair moved a legacy project"
python3 "$REPAIR" "$VAULT" > "$TMP/repair-repeat.txt"
grep -q "0 project containers need creation" "$TMP/repair-repeat.txt" && ok "repair repeat run is a no-op" || bad "repair repeat run changed structure"

NEW_PERSONAL_JSON="$(bash "$PROJECT_CONTEXT" home-plan "$VAULT" 2026-09-06)"
LEGACY_PERSONAL_JSON="$(bash "$PROJECT_CONTEXT" legacy-trip "$VAULT" 2026-09-06)"
BUSINESS_JSON="$(bash "$PROJECT_CONTEXT" launch "$VAULT" 2026-09-06)"
assert_eq "project-sync preserves explicit slug through a business grouping" \
  "$(jq -r '.project.hub_path' <<< "$BUSINESS_JSON")" \
  "2. Projects/7. Studio/Collection/Launch Space/Launch Space.md"
assert_eq "project-sync resolves numbered Personal hub" \
  "$(jq -r '.project.hub_path' <<< "$NEW_PERSONAL_JSON")" \
  "Personal/2. Projects/Home Plan/Home Plan.md"
assert_eq "project-sync retains legacy Personal read compatibility" \
  "$(jq -r '.project.hub_path' <<< "$LEGACY_PERSONAL_JSON")" \
  "Personal/Legacy Trip/PROJECT.md"

printf '\npassed=%s failed_any=%s\n' "$pass" "$fail"
exit "$fail"
