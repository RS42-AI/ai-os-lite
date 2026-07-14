#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

if [[ -n "$(git ls-files 'docs/superpowers/**')" ]]; then
  fail "internal implementation plans are tracked"
else
  pass "no tracked internal implementation plans"
fi

if git rev-parse --verify main >/dev/null 2>&1 \
  && [[ -n "$(git log --format= --name-only main..HEAD -- 'docs/superpowers/**')" ]]; then
  fail "the release branch history contains an internal implementation plan"
else
  pass "release history excludes internal implementation plans"
fi

path_hits="$(git grep -n -E "/Users/|\\\$HOME/RS42" -- plugins README.md .claude-plugin .agents 2>/dev/null || true)"
if [[ -n "$path_hits" ]]; then
  printf '%s\n' "$path_hits" >&2
  fail "local machine paths appear in public artifacts"
else
  pass "no local machine paths in public artifacts"
fi

if [[ -n "${AI_OS_PRIVATE_PATTERN_FILE:-}" ]]; then
  if [[ ! -f "$AI_OS_PRIVATE_PATTERN_FILE" ]]; then
    fail "AI_OS_PRIVATE_PATTERN_FILE does not exist"
  else
    private_hits=""
    while IFS= read -r pattern; do
      [[ -z "$pattern" || "$pattern" == \#* ]] && continue
      hits="$(git grep -n -i -F "$pattern" -- plugins README.md .claude-plugin .agents 2>/dev/null \
        | grep -v -E '^README\.md:[0-9]+:> Copyright © 2026 Yandi Farinango / RandomStateLabs\.' \
        || true)"
      if [[ -n "$hits" ]]; then
        private_hits+="${private_hits:+$'\n'}$hits"
      fi
    done < "$AI_OS_PRIVATE_PATTERN_FILE"
    if [[ -n "$private_hits" ]]; then
      printf '%s\n' "$private_hits" >&2
      fail "private release patterns appear in public artifacts"
    else
      pass "private release-pattern scan"
    fi
  fi
else
  printf 'NOTE: AI_OS_PRIVATE_PATTERN_FILE not set; token-specific private scan skipped\n'
fi

placeholder_hits="$(git grep -n -E '\{(WorkArea|SideArea|Project|Area)\}' -- 'plugins/**/*.sh' 2>/dev/null \
  | awk '{ line=$0; sub(/^[^:]+:[0-9]+:/, "", line); if (line !~ /^[[:space:]]*#/) print $0 }' || true)"
if [[ -n "$placeholder_hits" ]]; then
  printf '%s\n' "$placeholder_hits" >&2
  fail "placeholder tokens appear in executable shell lines"
else
  pass "no placeholder tokens in executable shell lines"
fi

if git grep -n -F 'RandomStateLabs/ai-os-lite' -- README.md >/dev/null 2>&1; then
  fail "README points at the obsolete marketplace repository"
elif ! git grep -q -F 'RS42-AI/ai-os-lite' -- README.md; then
  fail "README does not contain the canonical marketplace repository"
else
  pass "README marketplace path"
fi

if git grep -n -E 'scheduled Morning Brief|scheduled executive Morning Brief' -- README.md .claude-plugin .agents >/dev/null 2>&1; then
  fail "release metadata promises a scheduler that the plugin does not install"
else
  pass "release metadata describes scheduling accurately"
fi

if python3 - <<'PY'
import json
from pathlib import Path

root = Path.cwd()
claude_marketplace = json.loads((root / ".claude-plugin/marketplace.json").read_text())
claude_plugin = json.loads((root / "plugins/ai-os-lite/.claude-plugin/plugin.json").read_text())
codex_marketplace = json.loads((root / ".agents/plugins/marketplace.json").read_text())
codex_plugin = json.loads((root / "plugins/ai-os-lite/.codex-plugin/plugin.json").read_text())

versions = {
    "claude marketplace": claude_marketplace["metadata"]["version"],
    "claude plugin": claude_plugin["version"],
    "codex plugin": codex_plugin["version"],
}
if len(set(versions.values())) != 1:
    raise SystemExit(f"version mismatch: {versions}")

if codex_marketplace["name"] != "ai-os-lite-marketplace":
    raise SystemExit("Codex marketplace name must be ai-os-lite-marketplace")
entries = [entry for entry in codex_marketplace["plugins"] if entry.get("name") == "ai-os-lite"]
if len(entries) != 1:
    raise SystemExit("Codex marketplace must expose exactly one ai-os-lite entry")
entry = entries[0]
if entry.get("source") != {"source": "local", "path": "./plugins/ai-os-lite"}:
    raise SystemExit(f"unexpected Codex marketplace source: {entry.get('source')}")
if entry.get("policy") != {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}:
    raise SystemExit(f"unexpected Codex marketplace policy: {entry.get('policy')}")

plugin_root = root / "plugins/ai-os-lite"
if claude_plugin["name"] != codex_plugin["name"] or claude_plugin["name"] != "ai-os-lite":
    raise SystemExit("Claude/Codex plugin names do not match ai-os-lite")
missing = [skill for skill in claude_plugin["skills"] if not (plugin_root / skill).is_dir()]
if missing:
    raise SystemExit(f"registered skill directories missing: {missing}")

listed = {Path(skill).name for skill in claude_plugin["skills"]}
present = {path.name for path in (plugin_root / "skills").iterdir() if path.is_dir()}
if listed != present:
    raise SystemExit(
        f"manifest/skill-directory mismatch: unregistered={sorted(present-listed)}, "
        f"missing={sorted(listed-present)}"
    )

codex_skill_root = plugin_root / codex_plugin["skills"]
if codex_plugin["skills"] != "./skills/" or not codex_skill_root.is_dir():
    raise SystemExit(f"invalid Codex skills path: {codex_plugin['skills']}")
PY
then
  pass "Claude/Codex JSON, version, marketplace, and skill consistency"
else
  fail "Claude/Codex packaging consistency"
fi

syntax_failures=0
while IFS= read -r script; do
  if ! bash -n "$script"; then
    syntax_failures=$((syntax_failures + 1))
  fi
done < <(find plugins tests scripts -type f -name '*.sh' -print | sort)
if (( syntax_failures > 0 )); then
  fail "$syntax_failures shell scripts failed bash -n"
else
  pass "shell syntax"
fi

test_failures=0
while IFS= read -r test_script; do
  if ! bash "$test_script"; then
    test_failures=$((test_failures + 1))
  fi
done < <(find tests -mindepth 2 -maxdepth 2 -type f -name 'run.sh' -print | sort)
if (( test_failures > 0 )); then
  fail "$test_failures release tests failed"
else
  pass "release tests"
fi

if (( failures > 0 )); then
  printf '\nPublic release verification failed: %d check(s)\n' "$failures" >&2
  exit 1
fi

printf '\nPublic release verification passed.\n'
