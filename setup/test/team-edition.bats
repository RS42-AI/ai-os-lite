#!/usr/bin/env bats

load test_helper

@test "retired team flag stops before creating a workspace or acceptance record" {
  local target="$BATS_TEST_TMPDIR/not-created"
  run bash "$KIT_ROOT/setup-vault.sh" --edition=team "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"team edition has been retired"* ]]
  [ ! -e "$target" ]
}

@test "retired split team flag preserves every existing workspace byte" {
  setup_test_vault
  printf 'private existing notes\n' > "$TEST_VAULT/notes.txt"
  local before after
  before="$(tree_fingerprint "$TEST_VAULT")"
  run bash "$KIT_ROOT/setup-vault.sh" --update --edition team "$TEST_VAULT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"team edition has been retired"* ]]
  after="$(tree_fingerprint "$TEST_VAULT")"
  [ "$before" = "$after" ]
}

@test "setup wrapper rejects retired team install before integrations or writes" {
  local target="$BATS_TEST_TMPDIR/not-created"
  run bash "$KIT_ROOT/setup.sh" --edition=team --agent=none "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"team edition has been retired"* ]]
  [ ! -e "$target" ]
}

@test "generalized install keeps starter content exact and creates no RS42 onboarding" {
  setup_test_vault
  run bash "$KIT_ROOT/setup-vault.sh" "$TEST_VAULT"
  [ "$status" -eq 0 ]
  [ -d "$TEST_VAULT/Personal/1. Goals" ]
  [ -d "$TEST_VAULT/Personal/2. Projects" ]
  [ ! -e "$TEST_VAULT/2. Projects/RS42/RS42-Onboarding" ]
  [ ! -e "$TEST_VAULT/3. Areas/RS42" ]
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$KIT_ROOT/vault-files/"}"
    cmp -s "$f" "$TEST_VAULT/$rel" || {
      echo "base file missing or altered in generated workspace: $rel"
      return 1
    }
  done < <(find "$KIT_ROOT/vault-files" -type f -print0)
}

@test "former personal flag remains a compatibility alias" {
  setup_test_vault
  run bash "$KIT_ROOT/setup-vault.sh" --edition personal "$TEST_VAULT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_VAULT/Personal/2. Projects/Vault-Setup/Vault-Setup.md" ]
  [ ! -e "$TEST_VAULT/3. Areas/RS42" ]
}

@test "update preserves former team content and instruction files" {
  setup_test_vault
  mkdir -p "$TEST_VAULT/2. Projects/RS42/Existing Work" "$TEST_VAULT/system-settings"
  # Copy unmodified instructions as existing-user fixtures; do not depend on retired package files.
  cp "$KIT_ROOT/vault-files/AGENTS.md" "$TEST_VAULT/AGENTS.md"
  cp "$KIT_ROOT/vault-files/CLAUDE.md" "$TEST_VAULT/CLAUDE.md"
  printf 'original team workspace structure\n' > "$TEST_VAULT/system-settings/vault-structure.md"
  printf 'my work stays here\n' > "$TEST_VAULT/2. Projects/RS42/Existing Work/Notes.md"
  local before after
  before="$(shasum -a 256 "$TEST_VAULT/AGENTS.md" "$TEST_VAULT/CLAUDE.md" "$TEST_VAULT/system-settings/vault-structure.md" "$TEST_VAULT/2. Projects/RS42/Existing Work/Notes.md")"
  run bash "$KIT_ROOT/setup-vault.sh" --update "$TEST_VAULT"
  [ "$status" -eq 0 ]
  after="$(shasum -a 256 "$TEST_VAULT/AGENTS.md" "$TEST_VAULT/CLAUDE.md" "$TEST_VAULT/system-settings/vault-structure.md" "$TEST_VAULT/2. Projects/RS42/Existing Work/Notes.md")"
  [ "$before" = "$after" ]
  [ ! -e "$TEST_VAULT/2. Projects/RS42/RS42-Onboarding" ]
}

@test "unknown edition stops before creating a workspace" {
  local target="$BATS_TEST_TMPDIR/not-created"
  run bash "$KIT_ROOT/setup-vault.sh" --edition=bogus "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown --edition"* ]]
  [ ! -e "$target" ]
}

# Include hidden files and file paths when proving rejected flags caused no writes.
tree_fingerprint() {
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted(root.rglob('*')):
    digest.update(str(path.relative_to(root)).encode())
    if path.is_file():
        digest.update(path.read_bytes())
print(digest.hexdigest())
PY
}
