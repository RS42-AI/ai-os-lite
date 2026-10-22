#!/usr/bin/env bats

load test_helper

make_codex_stub() {
  local bin_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CODEX_LOG"
if [ "${CODEX_FAIL_ON:-}" = "marketplace" ] && [[ "$*" == "plugin marketplace add "* ]]; then
  exit 1
fi
if [ "${CODEX_FAIL_ON:-}" = "plugin" ] && [[ "$*" == "plugin add "* ]]; then
  exit 1
fi
STUB
  chmod +x "$bin_dir/codex"
  export CODEX_TEST_PATH="$bin_dir:/usr/bin:/bin"
}

make_setup_fixture() {
  export SETUP_FIXTURE="$BATS_TEST_TMPDIR/kit"
  mkdir -p "$SETUP_FIXTURE"
  cp "$KIT_ROOT/setup.sh" "$SETUP_FIXTURE/setup.sh"

  local script
  for script in setup-vault setup-plugins setup-mcp setup-claude-plugins setup-codex-plugins; do
    {
      echo '#!/usr/bin/env bash'
      echo "printf '%s\\n' '$script' >> \"\$SETUP_LOG\""
    } > "$SETUP_FIXTURE/$script.sh"
    chmod +x "$SETUP_FIXTURE/$script.sh"
  done
}

@test "setup-codex-plugins reports partial setup when Codex is unavailable" {
  setup_test_vault
  mkdir -p "$BATS_TEST_TMPDIR/empty-path"
  run env PATH="$BATS_TEST_TMPDIR/empty-path" /bin/bash "$KIT_ROOT/setup-codex-plugins.sh" "$TEST_VAULT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"SKIP: 'codex' CLI not found"* ]]
}

@test "setup-codex-plugins registers the reviewed local package and installs AI-OS Lite" {
  setup_test_vault
  make_codex_stub
  export CODEX_LOG="$BATS_TEST_TMPDIR/codex.log"

  run env PATH="$CODEX_TEST_PATH" CODEX_LOG="$CODEX_LOG" /bin/bash "$KIT_ROOT/setup-codex-plugins.sh" "$TEST_VAULT"
  [ "$status" -eq 0 ]
  grep -Fxq "plugin marketplace add $(cd "$KIT_ROOT/.." && pwd -P)" "$CODEX_LOG"
  grep -Fxq "plugin add ai-os-lite@ai-os-lite-marketplace" "$CODEX_LOG"
  [[ "$output" == *"AI-OS Lite Installed for Codex"* ]]
  [[ "$output" == *"$TEST_VAULT"* ]]
}

@test "setup-codex-plugins reports partial setup for marketplace failures" {
  setup_test_vault
  make_codex_stub
  export CODEX_LOG="$BATS_TEST_TMPDIR/codex.log"

  run env PATH="$CODEX_TEST_PATH" CODEX_LOG="$CODEX_LOG" CODEX_FAIL_ON=marketplace /bin/bash "$KIT_ROOT/setup-codex-plugins.sh" "$TEST_VAULT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"WARNING: could not add"* ]]
  ! grep -Fq "plugin add ai-os-lite@ai-os-lite-marketplace" "$CODEX_LOG"
}

@test "setup-codex-plugins accepts an override resolving to the reviewed package" {
  setup_test_vault
  make_codex_stub
  export CODEX_LOG="$BATS_TEST_TMPDIR/codex.log"

  run env PATH="$CODEX_TEST_PATH" CODEX_LOG="$CODEX_LOG" AI_OS_LITE_MARKETPLACE="$KIT_ROOT/.." /bin/bash "$KIT_ROOT/setup-codex-plugins.sh" "$TEST_VAULT"
  [ "$status" -eq 0 ]
  grep -Fxq "plugin marketplace add $(cd "$KIT_ROOT/.." && pwd -P)" "$CODEX_LOG"
}

@test "setup.sh defaults to vault and Claude skills without Obsidian prompts or integrations" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"

  run env SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" "$TEST_VAULT"
  [ "$status" -eq 0 ]
  ! grep -Fxq "setup-mcp" "$log"
  ! grep -Fxq "setup-plugins" "$log"
  [[ "$output" != *"Press Enter"* ]]
  grep -Fxq "setup-claude-plugins" "$log"
  ! grep -Fxq "setup-codex-plugins" "$log"
}

@test "setup.sh --agent=codex selects only the Codex agent integration" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"

  run env SETUP_YES=1 SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=codex "$TEST_VAULT"
  [ "$status" -eq 0 ]
  grep -Fxq "setup-codex-plugins" "$log"
  ! grep -Fxq "setup-mcp" "$log"
  ! grep -Fxq "setup-claude-plugins" "$log"
}

@test "setup.sh --agent=both installs both agent integrations" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"

  run env SETUP_YES=1 SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent both "$TEST_VAULT"
  [ "$status" -eq 0 ]
  ! grep -Fxq "setup-mcp" "$log"
  ! grep -Fxq "setup-plugins" "$log"
  [[ "$output" != *"Press Enter"* ]]
  grep -Fxq "setup-claude-plugins" "$log"
  grep -Fxq "setup-codex-plugins" "$log"
}

@test "setup.sh rejects an unknown agent" {
  setup_test_vault
  make_setup_fixture

  run env SETUP_YES=1 SETUP_LOG="$BATS_TEST_TMPDIR/setup.log" bash "$SETUP_FIXTURE/setup.sh" --agent=other "$TEST_VAULT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected: claude | codex | both"* ]]
}

@test "setup.sh --agent=none installs no agent integration" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"
  run env SETUP_YES=1 SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=none "$TEST_VAULT"
  [ "$status" -eq 0 ]
  grep -Fxq "setup-vault" "$log"
  ! grep -Fxq "setup-plugins" "$log"
  ! grep -Fxq "setup-mcp" "$log"
  ! grep -Fxq "setup-claude-plugins" "$log"
  ! grep -Fxq "setup-codex-plugins" "$log"
}

@test "setup.sh reports partial integration with recovery after a failed step" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"
  printf '%s\n' 'exit 2' >> "$SETUP_FIXTURE/setup-plugins.sh"
  run env SETUP_YES=1 SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=codex --with-obsidian-plugins "$TEST_VAULT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"PARTIAL:"* ]]
  [[ "$output" == *"Retry: bash setup/setup-plugins.sh"* ]]
  grep -Fxq "setup-codex-plugins" "$log"
}

@test "setup.sh enables only explicitly requested Obsidian plugins" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"
  run env SETUP_YES=1 SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=codex --with-obsidian-plugins "$TEST_VAULT"
  [ "$status" -eq 0 ]
  grep -Fxq "setup-plugins" "$log"
  grep -Fxq "setup-codex-plugins" "$log"
  ! grep -Fxq "setup-mcp" "$log"
}

@test "setup.sh can configure requested Claude MCP against existing Obsidian plugins" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"
  cat >> "$SETUP_FIXTURE/setup-mcp.sh" <<'CHECK'
[ "${OBSIDIAN_API_KEY:-}" = "fixture-key" ] || exit 1
CHECK
  run env SETUP_YES=1 OBSIDIAN_API_KEY=fixture-key SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=both --with-obsidian-mcp "$TEST_VAULT"
  [ "$status" -eq 0 ]
  grep -Fxq "setup-mcp" "$log"
  ! grep -Fxq "setup-plugins" "$log"
  grep -Fxq "setup-claude-plugins" "$log"
  grep -Fxq "setup-codex-plugins" "$log"
  [[ "$output" != *"fixture-key"* ]]
}

@test "setup.sh rejects incompatible MCP selection before creating the vault" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log" agent
  for agent in codex none; do
    run env SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent="$agent" --with-obsidian-mcp "$TEST_VAULT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires --agent=claude or --agent=both"* ]]
    [ ! -e "$log" ]
  done
}

@test "setup.sh reports skipped requested MCP without prompting or calling its helper" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"
  run env SETUP_YES=1 OBSIDIAN_API_KEY='' SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=both --with-obsidian-mcp "$TEST_VAULT"
  [ "$status" -eq 2 ]
  grep -Fxq "setup-claude-plugins" "$log"
  grep -Fxq "setup-codex-plugins" "$log"
  ! grep -Fxq "setup-mcp" "$log"
  [[ "$output" == *"MCP setup skipped"* ]]
  [[ "$output" != *"Paste the"* ]]
}

@test "setup.sh attempts both selected agents and requested integrations after helper failures" {
  setup_test_vault
  make_setup_fixture
  local log="$BATS_TEST_TMPDIR/setup.log"
  printf '%s\n' 'exit 2' >> "$SETUP_FIXTURE/setup-claude-plugins.sh"
  printf '%s\n' 'exit 2' >> "$SETUP_FIXTURE/setup-mcp.sh"
  run env SETUP_YES=1 OBSIDIAN_API_KEY=fixture-key SETUP_LOG="$log" bash "$SETUP_FIXTURE/setup.sh" --agent=both --with-obsidian-plugins --with-obsidian-mcp "$TEST_VAULT"
  [ "$status" -eq 2 ]
  grep -Fxq "setup-claude-plugins" "$log"
  grep -Fxq "setup-codex-plugins" "$log"
  grep -Fxq "setup-plugins" "$log"
  grep -Fxq "setup-mcp" "$log"
  [[ "$output" == *"PARTIAL: 2 integration step(s)"* ]]
}

@test "setup.sh vault-only repeat preserves content without installing Obsidian plugins" {
  setup_test_vault
  run bash "$KIT_ROOT/setup.sh" --agent=none "$TEST_VAULT"
  [ "$status" -eq 0 ]
  printf '%s\n' 'Owner content stays unchanged.' > "$TEST_VAULT/6. Main Notes/Keep.md"
  run bash "$KIT_ROOT/setup.sh" --agent=none "$TEST_VAULT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_VAULT/6. Main Notes/Keep.md")" = 'Owner content stays unchanged.' ]
  [ ! -d "$TEST_VAULT/.obsidian/plugins" ]
  [[ "$output" != *"Press Enter"* ]]
}

@test "setup-codex-plugins rejects a different marketplace before any client writes" {
  setup_test_vault
  make_codex_stub
  export CODEX_LOG="$BATS_TEST_TMPDIR/codex.log"
  run env PATH="$CODEX_TEST_PATH" CODEX_LOG="$CODEX_LOG" AI_OS_LITE_MARKETPLACE=RS42-AI/ai-os-lite /bin/bash "$KIT_ROOT/setup-codex-plugins.sh" "$TEST_VAULT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"this reviewed local package"* ]]
  [ ! -e "$CODEX_LOG" ]
}
