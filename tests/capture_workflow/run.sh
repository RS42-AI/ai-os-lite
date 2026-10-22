#!/bin/bash
# Asserts capture-workflow's deterministic layer: the manifest validator
# (gates, roles, anchors, privacy, secrets, caps), session lister, and installer.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/../.."
SK="$REPO/plugins/ai-os-lite/skills/capture-workflow/scripts"
FX="$REPO/fixtures/capture-workflow"

fail=0; pass=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=1; }

val() { python3 "$SK/validate_workflow_manifest.py" "$FX/$1" 2>/dev/null; }

has_v() { # <pkg> <check>
  local out; out="$(val "$1")"
  local n; n=$(jq --arg c "$2" '[.violations[]? | select(.check==$c)] | length' <<<"$out" 2>/dev/null)
  if [[ "${n:-0}" -ge 1 ]]; then ok "$2 flags $1"; else bad "$2 did NOT flag $1 (got: $out)"; fi
}

out="$(val valid-pkg)"; rc=$?
if [[ $rc -eq 0 && "$(jq '.violations|length' <<<"$out")" == "0" && "$(jq '.warnings|length' <<<"$out")" == "0" ]]; then
  ok "valid-pkg passes (exit 0, no violations, no warnings)"
else bad "valid-pkg flagged: rc=$rc $out"; fi

has_v missing-gate-pkg    ungated_mutation
has_v bad-role-pkg        invalid_role
has_v coords-pkg          coordinate_action
has_v secret-pkg          embedded_secret
has_v flow-style-pkg      manifest_parse
has_v human-extra-pkg     human_step_extra_field
has_v no-skillmd-pkg      skill_md_missing
has_v no-frontmatter-pkg  skill_md_missing_frontmatter

# Public packages reject common PII shapes and machine-specific home paths.
PII="$(mktemp -d "${TMPDIR:-/tmp}/cw-pii.XXXXXX")" || exit 1
mkdir -p "$PII/pkg"; cp -R "$FX/valid-pkg/." "$PII/pkg/"
printf 'Contact: sample.user@example.com\n' >> "$PII/pkg/evidence/capture-01.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$PII/pkg")"
[[ "$(jq '[.violations[]|select(.check=="embedded_pii")]|length' <<<"$out")" -ge 1 ]] \
  && ok "embedded_pii flags an email address" || bad "email PII not caught (got: $out)"
rm -rf "$PII"

LOCALPATH="$(mktemp -d "${TMPDIR:-/tmp}/cw-localpath.XXXXXX")" || exit 1
mkdir -p "$LOCALPATH/pkg"; cp -R "$FX/valid-pkg/." "$LOCALPATH/pkg/"
printf 'Source lived under /%s/example/private-workspace.\n' 'Users' >> "$LOCALPATH/pkg/evidence/capture-01.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$LOCALPATH/pkg")"
[[ "$(jq '[.violations[]|select(.check=="machine_specific_path")]|length' <<<"$out")" -ge 1 ]] \
  && ok "machine_specific_path flags a user-home path" || bad "local path not caught (got: $out)"
rm -rf "$LOCALPATH"

DENY="$(mktemp -d "${TMPDIR:-/tmp}/cw-deny.XXXXXX")" || exit 1
mkdir -p "$DENY/pkg"; cp -R "$FX/valid-pkg/." "$DENY/pkg/"
printf 'Confidential Example Organization\n' > "$DENY/private-patterns.txt"
printf 'This process belongs to Confidential Example Organization.\n' >> "$DENY/pkg/evidence/capture-01.md"
out="$(AI_OS_PRIVATE_PATTERN_FILE="$DENY/private-patterns.txt" python3 "$SK/validate_workflow_manifest.py" "$DENY/pkg")"
[[ "$(jq '[.violations[]|select(.check=="private_pattern")]|length' <<<"$out")" -ge 1 ]] \
  && ok "private_pattern flags a user-configured private term" || bad "private term not caught (got: $out)"
rm -rf "$DENY"

# SKILL.md length cap — long file generated at test time, not stored as fixture
LONG="$(mktemp -d "${TMPDIR:-/tmp}/cw-long.XXXXXX")" || exit 1
mkdir -p "$LONG/long-pkg"; cp -R "$FX/valid-pkg/." "$LONG/long-pkg/"
python3 -c "open('$LONG/long-pkg/SKILL.md','w').write('x\n'*151)"
out="$(python3 "$SK/validate_workflow_manifest.py" "$LONG/long-pkg")"
[[ "$(jq '[.violations[]|select(.check=="skill_md_too_long")]|length' <<<"$out")" -ge 1 ]] \
  && ok "skill_md_too_long flags a 151-line SKILL.md" || bad "concision cap not enforced"
rm -rf "$LONG"

# --- review fixes ---

has_v dup-steps-pkg manifest_parse

# I2 — shared credential lib should also catch sk-proj-… style project keys
SKPROJ="$(mktemp -d "${TMPDIR:-/tmp}/cw-skproj.XXXXXX")" || exit 1
mkdir -p "$SKPROJ/pkg"; cp -R "$FX/valid-pkg/." "$SKPROJ/pkg/"
printf 'Session notes.\nLeaked key: sk-proj-abcd1234abcd1234abcd1234\n' > "$SKPROJ/pkg/evidence/capture-01.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$SKPROJ/pkg")"
[[ "$(jq '[.violations[]|select(.check=="embedded_secret")]|length' <<<"$out")" -ge 1 ]] \
  && ok "embedded_secret flags an sk-proj- style key in evidence" || bad "sk-proj- key not caught (got: $out)"
rm -rf "$SKPROJ"

# I3 — coordinate scan must also cover SKILL.md, not just workflow.yaml actions
COORDSKILL="$(mktemp -d "${TMPDIR:-/tmp}/cw-coordskill.XXXXXX")" || exit 1
mkdir -p "$COORDSKILL/pkg"; cp -R "$FX/valid-pkg/." "$COORDSKILL/pkg/"
printf '\nClick x=640, y=315 to open the inbox.\n' >> "$COORDSKILL/pkg/SKILL.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$COORDSKILL/pkg")"
[[ "$(jq '[.violations[]|select(.check=="coordinate_action" and (.detail|contains("SKILL.md")))]|length' <<<"$out")" -ge 1 ]] \
  && ok "coordinate_action flags a coordinate line in SKILL.md" || bad "SKILL.md coordinate scan missing (got: $out)"
rm -rf "$COORDSKILL"

# I4 — symlinks must not evade the package file scan
SYMLINK="$(mktemp -d "${TMPDIR:-/tmp}/cw-symlink.XXXXXX")" || exit 1
mkdir -p "$SYMLINK/outside" "$SYMLINK/pkg"; cp -R "$FX/valid-pkg/." "$SYMLINK/pkg/"
ln -s "$SYMLINK/outside" "$SYMLINK/pkg/escape"
out="$(python3 "$SK/validate_workflow_manifest.py" "$SYMLINK/pkg")"
[[ "$(jq '[.violations[]|select(.check=="symlink_in_package")]|length' <<<"$out")" -ge 1 ]] \
  && ok "symlink_in_package flags a symlinked dir in the package" || bad "symlink not caught (got: $out)"
rm -rf "$SYMLINK"

# I5 — step id presence/format
MISSID="$(mktemp -d "${TMPDIR:-/tmp}/cw-missid.XXXXXX")" || exit 1
mkdir -p "$MISSID/pkg"
cat > "$MISSID/pkg/workflow.yaml" <<'YAML'
workflow: missid-pkg
description: Fixture isolating a step with no id
version: 1
steps:
  - role: ai
    mutation: read
    action: Open the signed-in Etsy seller dashboard
YAML
cp "$FX/valid-pkg/SKILL.md" "$MISSID/pkg/SKILL.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$MISSID/pkg")"
[[ "$(jq '[.violations[]|select(.check=="missing_id")]|length' <<<"$out")" -ge 1 ]] \
  && ok "missing_id flags a step with no id" || bad "missing id not caught (got: $out)"
rm -rf "$MISSID"

# I6 — embedded base64 data URIs and real binary files must both be caught
DATAURI="$(mktemp -d "${TMPDIR:-/tmp}/cw-datauri.XXXXXX")" || exit 1
mkdir -p "$DATAURI/pkg"; cp -R "$FX/valid-pkg/." "$DATAURI/pkg/"
printf 'data:image/png;base64,AAAAAAAAAAAAAAAAAAAAAAAA\n' >> "$DATAURI/pkg/evidence/capture-01.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$DATAURI/pkg")"
[[ "$(jq '[.violations[]|select(.check=="binary_payload")]|length' <<<"$out")" -ge 1 ]] \
  && ok "binary_payload flags an embedded base64 data URI" || bad "data-URI not caught (got: $out)"
rm -rf "$DATAURI"

REALBIN="$(mktemp -d "${TMPDIR:-/tmp}/cw-realbin.XXXXXX")" || exit 1
mkdir -p "$REALBIN/pkg"; cp -R "$FX/valid-pkg/." "$REALBIN/pkg/"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00' > "$REALBIN/pkg/evidence/screenshot.png"
out="$(python3 "$SK/validate_workflow_manifest.py" "$REALBIN/pkg")"
[[ "$(jq '[.violations[]|select(.check=="binary_payload")]|length' <<<"$out")" -ge 1 ]] \
  && ok "binary_payload flags a real .png file" || bad "binary file not caught (got: $out)"
rm -rf "$REALBIN"

# I7 — the schema doc's own canonical example (trailing comments) must parse clean
COMMENT="$(mktemp -d "${TMPDIR:-/tmp}/cw-comment.XXXXXX")" || exit 1
mkdir -p "$COMMENT/pkg/evidence"
cat > "$COMMENT/pkg/workflow.yaml" <<'YAML'
workflow: ecom-morning-queue        # slug — must match the directory name
description: One-line purpose
version: 1
steps:
  - id: open-dashboards             # unique kebab-case id
    role: ai                        # ai | human (closed vocabulary)
    mutation: read                  # ai steps only — see classes below
    action: Open the signed-in Etsy seller dashboard
  - id: judge-edge-cases
    role: human                     # human steps carry prompt, nothing else
    prompt: Rank or dismiss the items that match no urgency rule
  - id: send-replies
    role: ai
    mutation: send
    gate: approval                  # REQUIRED for every mutation beyond read/draft
    action: Preview each drafted reply and send only what is approved
YAML
sed 's/^name: valid-pkg$/name: pkg/' "$FX/valid-pkg/SKILL.md" > "$COMMENT/pkg/SKILL.md"
cp "$FX/valid-pkg/evidence/capture-01.md" "$COMMENT/pkg/evidence/capture-01.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$COMMENT/pkg")"
[[ "$(jq '.violations|length' <<<"$out")" == "0" ]] \
  && ok "trailing-comment workflow.yaml (schema doc's example) parses with zero violations" \
  || bad "trailing comments broke parsing (got: $out)"
rm -rf "$COMMENT"

# --- re-review fixes ---

# N1 — bare "coordinate"/"pixel" prose in SKILL.md must not false-positive;
# only positional patterns (click+digits, x=..y=..) apply to SKILL.md.
PROSECOORD="$(mktemp -d "${TMPDIR:-/tmp}/cw-prosecoord.XXXXXX")" || exit 1
mkdir -p "$PROSECOORD/pkg"; cp -R "$FX/valid-pkg/." "$PROSECOORD/pkg/"
sed -i.bak 's/^name: valid-pkg$/name: pkg/' "$PROSECOORD/pkg/SKILL.md" && rm -f "$PROSECOORD/pkg/SKILL.md.bak"
printf '\n- Coordinate the reply queue with the shipping cutoff before drafting.\n' \
  >> "$PROSECOORD/pkg/SKILL.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$PROSECOORD/pkg")"
[[ "$(jq '.violations|length' <<<"$out")" == "0" ]] \
  && ok "SKILL.md prose using the word 'coordinate' does not false-positive" \
  || bad "SKILL.md coordinate keyword false-positive not fixed (got: $out)"
rm -rf "$PROSECOORD"

# N2 — passwd coverage (dropped when SECRET_PATTERNS switched to the shared lib)
PASSWD="$(mktemp -d "${TMPDIR:-/tmp}/cw-passwd.XXXXXX")" || exit 1
mkdir -p "$PASSWD/pkg"; cp -R "$FX/valid-pkg/." "$PASSWD/pkg/"
printf 'passwd = hunter2SuperSecretValue\n' >> "$PASSWD/pkg/evidence/capture-01.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$PASSWD/pkg")"
[[ "$(jq '[.violations[]|select(.check=="embedded_secret")]|length' <<<"$out")" -ge 1 ]] \
  && ok "embedded_secret flags a passwd= line in evidence" || bad "passwd not caught (got: $out)"
rm -rf "$PASSWD"

# anchor is now prohibited on human steps too (schema doc scopes it to ai steps)
HUMANANCHOR="$(mktemp -d "${TMPDIR:-/tmp}/cw-humananchor.XXXXXX")" || exit 1
mkdir -p "$HUMANANCHOR/pkg"
cat > "$HUMANANCHOR/pkg/workflow.yaml" <<'YAML'
workflow: humananchor-pkg
description: Fixture isolating anchor on a human step
version: 1
steps:
  - id: judge-edge-cases
    role: human
    prompt: Rank or dismiss the unmatched items
    anchor: the flagged items list
YAML
cp "$FX/valid-pkg/SKILL.md" "$HUMANANCHOR/pkg/SKILL.md"
out="$(python3 "$SK/validate_workflow_manifest.py" "$HUMANANCHOR/pkg")"
[[ "$(jq '[.violations[]|select(.check=="human_step_extra_field")]|length' <<<"$out")" -ge 1 ]] \
  && ok "human_step_extra_field flags anchor on a human step" || bad "human anchor not caught (got: $out)"
rm -rf "$HUMANANCHOR"

val missing-gate-pkg >/dev/null; [[ $? -eq 1 ]] && ok "violation exit code is 1" || bad "violation exit code not 1"

# --- session lister ---
out="$(python3 "$SK/list_sessions.py" --root "$FX/sessions" --limit 5)"
[[ "$(jq -e 'type=="array"' <<<"$out" 2>/dev/null)" == "true" ]] && ok "lister returns an array" || bad "lister shape: $out"
[[ "$(jq 'length' <<<"$out")" == "1" ]] && ok "lister skips subagent rollouts" || bad "lister: $out"
[[ "$(jq -r '.[0].originator' <<<"$out")" == "Codex Desktop" ]] && ok "lister surfaces originator" || bad "lister meta: $out"
out="$(python3 "$SK/list_sessions.py" --root "$FX/sessions" --include-subagents)"
[[ "$(jq 'length' <<<"$out")" == "2" ]] && ok "--include-subagents includes both" || bad "include-subagents: $out"

# --- session lister: messy tree robustness ---
# dangling symlink, a JSON array first line (not a dict), a session_meta record
# whose payload is JSON null, invalid-UTF-8 bytes, plus two well-formed sessions
# whose mtimes are pinned via touch -t (the older-mtime one carries a NEWER
# payload timestamp, to prove sorting follows mtime — last activity — not the
# payload's self-reported session-start time).
MESSY="$(mktemp -d "${TMPDIR:-/tmp}/cw-messy.XXXXXX")" || exit 1
ln -s "$MESSY/does-not-exist-target" "$MESSY/rollout-x.jsonl"
printf '[1,2,3]\n' > "$MESSY/rollout-y.jsonl"
printf '{"type":"session_meta","payload":null}\n' > "$MESSY/rollout-z.jsonl"
printf '\xff\xfe{"type":"session_meta"}\n' > "$MESSY/rollout-w.jsonl"
cat > "$MESSY/rollout-2015-old-mtime.jsonl" <<'JSON'
{"timestamp":"2040-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"old-mtime","timestamp":"2040-01-01T00:00:00.000Z","cwd":"/workspace/test/messy-old-mtime","originator":"Codex Desktop"}}
JSON
cat > "$MESSY/rollout-2035-new-mtime.jsonl" <<'JSON'
{"timestamp":"2000-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"new-mtime","timestamp":"2000-01-01T00:00:00.000Z","cwd":"/workspace/test/messy-new-mtime","originator":"Codex Desktop"}}
JSON
touch -t 201501010000 "$MESSY/rollout-2015-old-mtime.jsonl"
touch -t 203501010000 "$MESSY/rollout-2035-new-mtime.jsonl"
out="$(python3 "$SK/list_sessions.py" --root "$MESSY")"; rc=$?
[[ $rc -eq 0 ]] \
  && ok "lister survives a messy tree (dangling symlink, non-dict/null-payload/invalid-utf8 rollouts) without crashing" \
  || bad "lister crashed on messy tree (rc=$rc): $out"
[[ "$(jq -e 'type=="array"' <<<"$out" 2>/dev/null)" == "true" ]] && ok "messy-tree output is an array" || bad "messy-tree shape: $out"
# The null-payload session_meta record (z) is dropped outright — a non-dict
# payload is as degenerate as a non-dict rec or a mismatched type. Raw length
# proves nothing degenerate leaked into the picker (it would push real
# sessions off the default --limit 10 if it did).
[[ "$(jq 'length' <<<"$out" 2>/dev/null)" == "2" ]] \
  && ok "messy tree: exactly the 2 valid sessions, degenerate rows dropped" || bad "messy tree count: $out"
[[ "$(jq -r '.[0].cwd' <<<"$out" 2>/dev/null)" == "/workspace/test/messy-new-mtime" ]] \
  && ok "messy tree: first element is the mtime-newest file, not the payload-timestamp-newest" \
  || bad "messy tree order: $out"
[[ "$(jq '[.[] | has("mtime")] | all' <<<"$out" 2>/dev/null)" == "true" ]] \
  && ok "messy tree: every element carries an mtime field" || bad "messy tree mtime field: $out"
rm -rf "$MESSY"

# --- installer (HOME sandbox) ---
H="$(mktemp -d "${TMPDIR:-/tmp}/cw-home.XXXXXX")" || exit 1
out="$(HOME="$H" python3 "$SK/install_workflow.py" "$FX/valid-pkg" --both)"; rc=$?
[[ $rc -eq 0 && -f "$H/.codex/skills/valid-pkg/workflow.yaml" && -f "$H/.claude/skills/valid-pkg/workflow.yaml" ]] \
  && ok "installer installs to both HOME targets" || bad "install --both failed (rc=$rc): $out"
[[ $rc -eq 0 ]] && ok "success exit code is 0" || bad "success exit code is $rc, want 0"
[[ "$(jq -e '.installed | length == 2' <<<"$out" 2>/dev/null)" == "true" ]] \
  && ok "success JSON reports both installed targets" || bad "success JSON shape: $out"

HOME="$H" python3 "$SK/install_workflow.py" "$FX/valid-pkg" --both >/dev/null 2>&1 \
  && bad "reinstall without --force should refuse" || ok "reinstall refused without --force"
HOME="$H" python3 "$SK/install_workflow.py" "$FX/missing-gate-pkg" --codex >/dev/null 2>&1 \
  && bad "invalid package must be refused" || ok "invalid package refused"

# --force must replace stale contents, not merge with them
touch "$H/.claude/skills/valid-pkg/STALE_MARKER"
HOME="$H" python3 "$SK/install_workflow.py" "$FX/valid-pkg" --both --force >/dev/null; rc=$?
[[ $rc -eq 0 && ! -f "$H/.claude/skills/valid-pkg/STALE_MARKER" ]] \
  && ok "--force replaces stale install contents" || bad "--force did not clear stale file (rc=$rc)"

# self-install (dest == src) must be refused, never rmtree the installed copy
out="$(HOME="$H" python3 "$SK/install_workflow.py" "$H/.claude/skills/valid-pkg" --claude --force 2>&1)"; rc=$?
[[ $rc -ne 0 && -f "$H/.claude/skills/valid-pkg/workflow.yaml" ]] \
  && ok "self-install (dest==src) refused, installed copy intact" || bad "self-install guard failed (rc=$rc): $out"

# usage error: no target flag
HOME="$H" python3 "$SK/install_workflow.py" "$FX/valid-pkg" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "no-target-flag exit code is 2" || bad "no-target-flag exit code is $rc, want 2"
rm -rf "$H"

# fail-closed: a refused install must leave zero filesystem trace
FAILCLOSED="$(mktemp -d "${TMPDIR:-/tmp}/cw-failclosed.XXXXXX")" || exit 1
out="$(HOME="$FAILCLOSED" python3 "$SK/install_workflow.py" "$FX/missing-gate-pkg" --codex 2>/dev/null)"; rc=$?
[[ $rc -eq 1 ]] && ok "fail-closed install exits 1" || bad "fail-closed exit code is $rc, want 1"
[[ "$(jq -e 'has("error")' <<<"$out" 2>/dev/null)" == "true" ]] \
  && ok "fail-closed stdout JSON has an error field" || bad "fail-closed JSON shape: $out"
[[ ! -d "$FAILCLOSED/.codex" ]] \
  && ok "fail-closed leaves no .codex directory behind" || bad "fail-closed wrote to disk: $FAILCLOSED/.codex exists"
rm -rf "$FAILCLOSED"

# all-targets-preflight-before-any-copy: with --both, a later target (.claude)
# refusing must not have let an earlier target (.codex) get written first.
ORDER="$(mktemp -d "${TMPDIR:-/tmp}/cw-order.XXXXXX")" || exit 1
mkdir -p "$ORDER/.claude/skills"; cp -R "$FX/valid-pkg" "$ORDER/.claude/skills/valid-pkg"
HOME="$ORDER" python3 "$SK/install_workflow.py" "$FX/valid-pkg" --both >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 && ! -d "$ORDER/.codex" ]] \
  && ok "partial-install pin: pre-seeded .claude refuses --both before .codex is ever created" \
  || bad "partial-install ordering invariant broken (rc=$rc, .codex exists=$([[ -d "$ORDER/.codex" ]] && echo yes || echo no))"
rm -rf "$ORDER"

# slug mismatch: install-dir name must match the manifest's workflow: slug
MISMATCH="$(mktemp -d "${TMPDIR:-/tmp}/cw-mismatch.XXXXXX")" || exit 1
mkdir -p "$MISMATCH/renamed-pkg"; cp -R "$FX/valid-pkg/." "$MISMATCH/renamed-pkg/"
MMHOME="$(mktemp -d "${TMPDIR:-/tmp}/cw-mismatch-home.XXXXXX")" || exit 1
HOME="$MMHOME" python3 "$SK/install_workflow.py" "$MISMATCH/renamed-pkg" --codex >/dev/null 2>&1 \
  && bad "slug mismatch (dir name != workflow: slug) must be refused" || ok "slug mismatch refused"
rm -rf "$MISMATCH" "$MMHOME"

echo; [[ $fail -eq 0 ]] && echo "ALL $pass CHECKS PASSED" || { echo "FAILURES above"; exit 1; }
