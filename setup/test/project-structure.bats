#!/usr/bin/env bats

load test_helper

CONTAINERS=("Tasks" "Notes" "Resources" "Artifacts" "Specs" "Dev Log")

make_project_hub() {
  local directory="$1" name="$2" area="$3" slug="$4"
  mkdir -p "$directory"
  cat > "$directory/$name.md" <<EOF
---
date: 2026-09-06
type: project
status: draft
area: $area
project: $slug
goal:
---

# $name
EOF
}

assert_project_shape() {
  local directory="$1" container
  for container in "${CONTAINERS[@]}"; do
    [ -d "$directory/$container" ] || {
      echo "missing $directory/$container"
      return 1
    }
  done
}

json_value() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

@test "structure profile declares the reviewed portable destinations" {
  run python3 - "$KIT_ROOT/structure/project-structure.json" <<'PY'
import json, sys
profile = json.load(open(sys.argv[1]))
assert profile["required_project_containers"] == ["Tasks", "Notes", "Resources", "Artifacts", "Specs", "Dev Log"]
assert profile["business"]["area_tasks"] == "2. Projects/{area}/Tasks"
assert profile["business"]["area_resources"] == "5. Resources/{area}"
assert profile["personal"]["goals_root"] == "Personal/1. Goals"
assert profile["personal"]["projects_root"] == "Personal/2. Projects"
assert profile["personal"]["area_tasks"] == "Personal/Tasks"
assert profile["personal"]["area_resources"] == "5. Resources/Personal"
PY
  [ "$status" -eq 0 ]
}

@test "fresh personal install creates numbered roots and all starter-project containers" {
  setup_test_vault
  run bash "$KIT_ROOT/setup-vault.sh" "$TEST_VAULT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_VAULT/Personal/Personal.md" ]
  [ -d "$TEST_VAULT/Personal/1. Goals" ]
  [ -d "$TEST_VAULT/Personal/2. Projects" ]
  [ -d "$TEST_VAULT/Personal/Tasks" ]
  [ -d "$TEST_VAULT/5. Resources/Personal" ]
  [ ! -e "$TEST_VAULT/Personal/Vault-Setup" ]
  [ ! -e "$TEST_VAULT/3. Areas/Personal" ]
  assert_project_shape "$TEST_VAULT/Personal/2. Projects/Vault-Setup"
}

@test "update mode does not duplicate legacy starter project or Personal dashboard before migration" {
  setup_test_vault
  mkdir -p "$TEST_VAULT/Personal/Vault-Setup" "$TEST_VAULT/3. Areas/Personal"
  printf '%s\n' '---' 'type: project' 'status: active' 'area: personal' 'project: vault-setup' '---' > "$TEST_VAULT/Personal/Vault-Setup/Vault-Setup.md"
  printf '%s\n' '---' 'type: area-dashboard' 'status: active' 'area: personal' '---' > "$TEST_VAULT/3. Areas/Personal/Personal.md"
  local project_before area_before
  project_before="$(shasum -a 256 "$TEST_VAULT/Personal/Vault-Setup/Vault-Setup.md" | awk '{print $1}')"
  area_before="$(shasum -a 256 "$TEST_VAULT/3. Areas/Personal/Personal.md" | awk '{print $1}')"

  run bash "$KIT_ROOT/setup-vault.sh" --update "$TEST_VAULT"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_VAULT/Personal/2. Projects/Vault-Setup" ]
  [ ! -e "$TEST_VAULT/Personal/Personal.md" ]
  [ "$(shasum -a 256 "$TEST_VAULT/Personal/Vault-Setup/Vault-Setup.md" | awk '{print $1}')" = "$project_before" ]
  [ "$(shasum -a 256 "$TEST_VAULT/3. Areas/Personal/Personal.md" | awk '{print $1}')" = "$area_before" ]
}

@test "scaffold preserves custom area and nested project identity and is repeat-safe" {
  setup_test_vault
  local project="$TEST_VAULT/2. Projects/Client Work/Portfolio/Launch"
  make_project_hub "$project" "Launch" "client-work" "launch"
  printf 'keep-this-byte-for-byte\n' > "$project/evidence.bin"
  local before
  before="$(shasum -a 256 "$project/evidence.bin" | awk '{print $1}')"

  run python3 "$KIT_ROOT/tools/project_structure.py" scaffold --vault "$TEST_VAULT"
  [ "$status" -eq 0 ]
  assert_project_shape "$project"
  [ -d "$TEST_VAULT/2. Projects/Client Work/Tasks" ]
  [ -d "$TEST_VAULT/5. Resources/Client Work" ]
  [ "$(shasum -a 256 "$project/evidence.bin" | awk '{print $1}')" = "$before" ]

  run python3 "$KIT_ROOT/tools/project_structure.py" scaffold --vault "$TEST_VAULT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"created_count": 0'* ]]
}

@test "legacy Personal migration preserves content, rewrites exact consumers, repeats cleanly, and rolls back" {
  setup_test_vault
  local source="$TEST_VAULT/Personal/Legacy Project"
  make_project_hub "$source" "Legacy Project" "personal" "legacy-project"
  mkdir -p "$source/Notes" "$TEST_VAULT/Personal/Goals" "$TEST_VAULT/6. Main Notes"
  printf 'opaque payload\n' > "$source/Notes/payload.bin"
  printf 'goal payload\n' > "$TEST_VAULT/Personal/Goals/Goal.md"
  printf 'See [[Personal/Legacy Project/Legacy Project]] and Personal/Goals/Goal.md\n' > "$TEST_VAULT/6. Main Notes/Index.md"
  local payload_before plan token receipt second
  payload_before="$(shasum -a 256 "$source/Notes/payload.bin" | awk '{print $1}')"
  plan="$BATS_TEST_TMPDIR/plan.json"

  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  [ -n "$token" ]

  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 0 ]
  receipt="$TEST_VAULT/.vault-structure-migrations/$token.json"
  [ -f "$receipt" ]
  [ ! -e "$source" ]
  [ -f "$TEST_VAULT/Personal/2. Projects/Legacy Project/Legacy Project.md" ]
  [ -f "$TEST_VAULT/Personal/1. Goals/Goal.md" ]
  assert_project_shape "$TEST_VAULT/Personal/2. Projects/Legacy Project"
  [ "$(shasum -a 256 "$TEST_VAULT/Personal/2. Projects/Legacy Project/Notes/payload.bin" | awk '{print $1}')" = "$payload_before" ]
  run grep -F '[[Personal/2. Projects/Legacy Project/Legacy Project]]' "$TEST_VAULT/6. Main Notes/Index.md"
  [ "$status" -eq 0 ]
  run grep -F 'Personal/1. Goals/Goal.md' "$TEST_VAULT/6. Main Notes/Index.md"
  [ "$status" -eq 0 ]

  second="$BATS_TEST_TMPDIR/second.json"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$second"
  [ "$status" -eq 0 ]
  run python3 - "$second" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
assert plan["moves"] == []
assert plan["mkdirs"] == []
assert plan["consumers"] == []
PY
  [ "$status" -eq 0 ]

  run python3 "$KIT_ROOT/tools/project_structure.py" rollback --vault "$TEST_VAULT" --receipt "$receipt"
  [ "$status" -eq 0 ]
  [ -f "$source/Legacy Project.md" ]
  [ -f "$TEST_VAULT/Personal/Goals/Goal.md" ]
  [ ! -e "$TEST_VAULT/Personal/2. Projects/Legacy Project" ]
  [ "$(shasum -a 256 "$source/Notes/payload.bin" | awk '{print $1}')" = "$payload_before" ]
  run grep -F '[[Personal/Legacy Project/Legacy Project]]' "$TEST_VAULT/6. Main Notes/Index.md"
  [ "$status" -eq 0 ]
  run grep -F 'Personal/Goals/Goal.md' "$TEST_VAULT/6. Main Notes/Index.md"
  [ "$status" -eq 0 ]
}

@test "collision blocks the whole exact plan and leaves both project trees unchanged" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Same" "Same" "personal" "same"
  make_project_hub "$TEST_VAULT/Personal/2. Projects/Same" "Same" "personal" "same"
  printf 'source\n' > "$TEST_VAULT/Personal/Same/source.txt"
  printf 'target\n' > "$TEST_VAULT/Personal/2. Projects/Same/target.txt"
  local plan="$BATS_TEST_TMPDIR/collision.json" token

  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"collision"* ]]
  [ -f "$TEST_VAULT/Personal/Same/source.txt" ]
  [ -f "$TEST_VAULT/Personal/2. Projects/Same/target.txt" ]
}

@test "changed preview token or changed consumer blocks apply" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Move Me" "Move Me" "personal" "move-me"
  mkdir -p "$TEST_VAULT/6. Main Notes"
  printf 'Personal/Move Me/Move Me.md\n' > "$TEST_VAULT/6. Main Notes/Index.md"
  local plan="$BATS_TEST_TMPDIR/stale.json" token
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"

  printf 'changed after preview\n' >> "$TEST_VAULT/6. Main Notes/Index.md"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"consumer changed"* ]]
  [ -d "$TEST_VAULT/Personal/Move Me" ]

  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "wrong-token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"approval token"* ]]
}

@test "unknown Personal roots are inventoried and never moved" {
  setup_test_vault
  mkdir -p "$TEST_VAULT/Personal/Private Archive"
  printf 'untouched\n' > "$TEST_VAULT/Personal/Private Archive/file.txt"
  local plan="$BATS_TEST_TMPDIR/unknown.json"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  run python3 - "$plan" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
assert "Personal/Private Archive" in plan["unknown_legacy_roots"]
assert all(move["source"] != "Personal/Private Archive" for move in plan["moves"])
PY
  [ "$status" -eq 0 ]
  [ -f "$TEST_VAULT/Personal/Private Archive/file.txt" ]
}

@test "instruction-file consumers block apply and are never rewritten" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Guarded" "Guarded" "personal" "guarded"
  printf 'Route to Personal/Guarded/Tasks only.\n' > "$TEST_VAULT/AGENTS.md"
  local plan="$BATS_TEST_TMPDIR/instruction.json" token before
  before="$(shasum -a 256 "$TEST_VAULT/AGENTS.md" | awk '{print $1}')"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 - "$plan" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
assert len(plan["blocked_instruction_consumers"]) == 1
assert plan["blocked_instruction_consumers"][0]["path"] == "AGENTS.md"
assert all(item["path"] != "AGENTS.md" for item in plan["consumers"])
PY
  [ "$status" -eq 0 ]
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"human review"* ]]
  [ "$(shasum -a 256 "$TEST_VAULT/AGENTS.md" | awk '{print $1}')" = "$before" ]
  [ -d "$TEST_VAULT/Personal/Guarded" ]
}

@test "binary path consumers are reported as blockers and left byte-identical" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Binary" "Binary" "personal" "binary"
  mkdir -p "$TEST_VAULT/Artifacts"
  printf '\377Personal/Binary/Binary.md\000' > "$TEST_VAULT/Artifacts/index.bin"
  local plan="$BATS_TEST_TMPDIR/binary.json" token before
  before="$(shasum -a 256 "$TEST_VAULT/Artifacts/index.bin" | awk '{print $1}')"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 - "$plan" <<'PY'
import json, sys
blocked = json.load(open(sys.argv[1]))["blocked_binary_consumers"]
assert len(blocked) == 1 and blocked[0]["path"] == "Artifacts/index.bin"
PY
  [ "$status" -eq 0 ]
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-text path consumers"* ]]
  [ "$(shasum -a 256 "$TEST_VAULT/Artifacts/index.bin" | awk '{print $1}')" = "$before" ]
  [ -d "$TEST_VAULT/Personal/Binary" ]
}

@test "failure after the first consumer restores every original and source tree" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Transactional" "Transactional" "personal" "transactional"
  mkdir -p "$TEST_VAULT/6. Main Notes"
  printf 'Personal/Transactional/Transactional.md first\n' > "$TEST_VAULT/6. Main Notes/A.md"
  printf 'Personal/Transactional/Transactional.md second\n' > "$TEST_VAULT/6. Main Notes/B.md"
  local plan="$BATS_TEST_TMPDIR/transaction.json" token a_before b_before
  a_before="$(shasum -a 256 "$TEST_VAULT/6. Main Notes/A.md" | awk '{print $1}')"
  b_before="$(shasum -a 256 "$TEST_VAULT/6. Main Notes/B.md" | awk '{print $1}')"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"

  run env VAULT_STRUCTURE_TEST_FAIL_AFTER_CONSUMERS=1 python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"injected consumer rewrite failure"* ]]
  [ -d "$TEST_VAULT/Personal/Transactional" ]
  [ ! -e "$TEST_VAULT/Personal/2. Projects/Transactional" ]
  [ "$(shasum -a 256 "$TEST_VAULT/6. Main Notes/A.md" | awk '{print $1}')" = "$a_before" ]
  [ "$(shasum -a 256 "$TEST_VAULT/6. Main Notes/B.md" | awk '{print $1}')" = "$b_before" ]
  [ ! -e "$TEST_VAULT/.vault-structure-backups/$token" ]
  [ ! -e "$TEST_VAULT/.vault-structure-migrations/$token.json" ]
}

@test "configuration and script consumers are inventoried and rewritten after exact approval" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Automated" "Automated" "personal" "automated"
  mkdir -p "$TEST_VAULT/.obsidian" "$TEST_VAULT/scripts"
  printf '{"path":"Personal/Automated/Automated.md"}\n' > "$TEST_VAULT/.obsidian/state.json"
  printf 'PATH_VALUE = "Personal/Automated/Automated.md"\n' > "$TEST_VAULT/scripts/check.py"
  printf 'target="Personal/Automated/Automated.md"\r\n' > "$TEST_VAULT/scripts/check.sh"
  chmod 755 "$TEST_VAULT/scripts/check.sh"
  local plan="$BATS_TEST_TMPDIR/config.json" token mode_before
  mode_before="$(python3 -c 'import os,stat,sys; print(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$TEST_VAULT/scripts/check.sh")"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 - "$plan" <<'PY'
import json, sys
paths = {item["path"] for item in json.load(open(sys.argv[1]))["consumers"]}
assert {".obsidian/state.json", "scripts/check.py", "scripts/check.sh"} <= paths
PY
  [ "$status" -eq 0 ]
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 0 ]
  run grep -R -F 'Personal/Automated/Automated.md' "$TEST_VAULT/.obsidian" "$TEST_VAULT/scripts"
  [ "$status" -ne 0 ]
  run grep -R -F 'Personal/2. Projects/Automated/Automated.md' "$TEST_VAULT/.obsidian" "$TEST_VAULT/scripts"
  [ "$status" -eq 0 ]
  [ "$(python3 -c 'import os,stat,sys; print(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$TEST_VAULT/scripts/check.sh")" = "$mode_before" ]
  run python3 - "$TEST_VAULT/scripts/check.sh" <<'PY'
import sys
assert open(sys.argv[1], "rb").read().endswith(b"\r\n")
PY
  [ "$status" -eq 0 ]
}

@test "consumer rewriting respects project-name boundaries and supports percent-encoded Markdown paths" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Home" "Home" "personal" "home"
  make_project_hub "$TEST_VAULT/Personal/Home Plan" "Home Plan" "personal" "home-plan"
  mkdir -p "$TEST_VAULT/6. Main Notes"
  printf '%s\n' '[[Personal/Home/Home]]' '[[Personal/Homecoming/Homecoming]]' '](Personal/Home%20Plan/Home%20Plan.md)' > "$TEST_VAULT/6. Main Notes/Paths.md"
  local plan="$BATS_TEST_TMPDIR/boundaries.json" token
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 0 ]
  run grep -F '[[Personal/2. Projects/Home/Home]]' "$TEST_VAULT/6. Main Notes/Paths.md"
  [ "$status" -eq 0 ]
  run grep -F '[[Personal/Homecoming/Homecoming]]' "$TEST_VAULT/6. Main Notes/Paths.md"
  [ "$status" -eq 0 ]
  run grep -F '](Personal/2.%20Projects/Home%20Plan/Home%20Plan.md)' "$TEST_VAULT/6. Main Notes/Paths.md"
  [ "$status" -eq 0 ]
}

@test "rollback preflights every backup before moving or restoring anything" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Backup Check" "Backup Check" "personal" "backup-check"
  mkdir -p "$TEST_VAULT/6. Main Notes"
  printf 'Personal/Backup Check/Backup Check.md\n' > "$TEST_VAULT/6. Main Notes/Index.md"
  local plan="$BATS_TEST_TMPDIR/backup.json" token receipt backup
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 0 ]
  receipt="$TEST_VAULT/.vault-structure-migrations/$token.json"
  backup="$TEST_VAULT/.vault-structure-backups/$token/6. Main Notes/Index.md"
  rm "$backup"

  run python3 "$KIT_ROOT/tools/project_structure.py" rollback --vault "$TEST_VAULT" --receipt "$receipt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing or changed backup"* ]]
  [ ! -e "$TEST_VAULT/Personal/Backup Check" ]
  [ -d "$TEST_VAULT/Personal/2. Projects/Backup Check" ]
  run grep -F 'Personal/2. Projects/Backup Check/Backup Check.md' "$TEST_VAULT/6. Main Notes/Index.md"
  [ "$status" -eq 0 ]
  [ -f "$receipt" ]
}

@test "symlinks in managed roots block scaffold and migration without following targets" {
  setup_test_vault
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside" "$TEST_VAULT/Personal"
  printf 'outside\n' > "$outside/file.txt"
  ln -s "$outside" "$TEST_VAULT/Personal/Linked"
  local before plan token
  before="$(shasum -a 256 "$outside/file.txt" | awk '{print $1}')"

  run python3 "$KIT_ROOT/tools/project_structure.py" scaffold --vault "$TEST_VAULT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  plan="$BATS_TEST_TMPDIR/symlink.json"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  [ "$(shasum -a 256 "$outside/file.txt" | awk '{print $1}')" = "$before" ]
}

@test "migration state and backup symlinks are rejected before outside writes or vault moves" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Hidden State" "Hidden State" "personal" "hidden-state"
  local plan="$BATS_TEST_TMPDIR/hidden-state.json" token
  local outside_state="$BATS_TEST_TMPDIR/outside-state" outside_backup="$BATS_TEST_TMPDIR/outside-backup"
  mkdir -p "$outside_state" "$outside_backup"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"

  ln -s "$outside_state" "$TEST_VAULT/.vault-structure-migrations"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  [ -d "$TEST_VAULT/Personal/Hidden State" ]
  [ -z "$(find "$outside_state" -mindepth 1 -print -quit)" ]

  rm "$TEST_VAULT/.vault-structure-migrations"
  mkdir "$TEST_VAULT/.vault-structure-migrations"
  ln -s "$outside_backup" "$TEST_VAULT/.vault-structure-backups"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  [ -d "$TEST_VAULT/Personal/Hidden State" ]
  [ -z "$(find "$outside_backup" -mindepth 1 -print -quit)" ]

  printf '{}\n' > "$outside_state/$token.json"
  rmdir "$TEST_VAULT/.vault-structure-migrations"
  ln -s "$outside_state" "$TEST_VAULT/.vault-structure-migrations"
  run python3 "$KIT_ROOT/tools/project_structure.py" rollback --vault "$TEST_VAULT" --receipt "$TEST_VAULT/.vault-structure-migrations/$token.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  [ -d "$TEST_VAULT/Personal/Hidden State" ]
}

@test "tampered traversal path and external rollback receipt are rejected" {
  setup_test_vault
  make_project_hub "$TEST_VAULT/Personal/Contained" "Contained" "personal" "contained"
  local plan="$BATS_TEST_TMPDIR/traversal.json" token external="$BATS_TEST_TMPDIR/external.json"
  run python3 "$KIT_ROOT/tools/project_structure.py" plan --vault "$TEST_VAULT" --output "$plan"
  [ "$status" -eq 0 ]
  run python3 - "$plan" "$KIT_ROOT" <<'PY'
import importlib.util, json, sys
plan_path, kit_root = sys.argv[1:]
spec = importlib.util.spec_from_file_location("project_structure", kit_root + "/tools/project_structure.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
plan = json.load(open(plan_path))
plan["moves"][0]["source"] = "../outside"
plan["approval_token"] = module.approval_token(plan)
json.dump(plan, open(plan_path, "w"))
PY
  [ "$status" -eq 0 ]
  token="$(json_value "$plan" approval_token)"
  run python3 "$KIT_ROOT/tools/project_structure.py" apply --vault "$TEST_VAULT" --plan "$plan" --approval-token "$token"
  [ "$status" -eq 2 ]
  [[ "$output" == *"escapes vault"* ]]
  printf '{}\n' > "$external"
  run python3 "$KIT_ROOT/tools/project_structure.py" rollback --vault "$TEST_VAULT" --receipt "$external"
  [ "$status" -eq 2 ]
  [[ "$output" == *"receipt must be"* ]]
  [ -d "$TEST_VAULT/Personal/Contained" ]
}

@test "project templates carry lifecycle identity and artifact contract without retired defaults" {
  local project="$KIT_ROOT/vault-files/system-settings/Templates/Project Hub Template.md"
  local spec="$KIT_ROOT/vault-files/system-settings/Templates/Spec Template.md"
  run grep -q '^status: draft$' "$project"
  [ "$status" -eq 0 ]
  run grep -q '^goal:$' "$project"
  [ "$status" -eq 0 ]
  run grep -q '^shared_id:$' "$project"
  [ "$status" -eq 0 ]
  run grep -q '^shared_hub_url:$' "$project"
  [ "$status" -eq 0 ]
  run grep -q '^## Artifacts$' "$project"
  [ "$status" -eq 0 ]
  run grep -q '^goal_status:' "$project"
  [ "$status" -ne 0 ]
  run grep -q 'in-review' "$spec"
  [ "$status" -ne 0 ]
}

@test "ratified starter instructions preserve current routing and human lifecycle decisions" {
  local instructions="$KIT_ROOT/vault-files/AGENTS.md"
  run grep -Fq 'goal_status: discovery' "$instructions"
  [ "$status" -ne 0 ]
  run grep -Fq 'Personal/{Project}/Tasks' "$instructions"
  [ "$status" -ne 0 ]
  run grep -Fq 'Personal/2. Projects/{Project}/Tasks/' "$instructions"
  [ "$status" -eq 0 ]
  run grep -Fq 'status: active' "$instructions"
  [ "$status" -eq 0 ]
  run grep -Fq 'resolving `goal:`' "$instructions"
  [ "$status" -eq 0 ]
  run grep -Fq 'Project and goal closure remain explicit human decisions.' "$instructions"
  [ "$status" -eq 0 ]
}
