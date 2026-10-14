#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/lite-local-morning.XXXXXX")"
trap 'rm -rf "$TASK_TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 - "$ROOT" "$TASK_TMP" <<'PY'
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

root, tmp = map(Path, sys.argv[1:])
vault = tmp / "vault"
vault.mkdir()
# A disposable review fixture does not represent a real person's agreement.
sys.path.insert(0, str(root / "setup/tools"))
from license_consent import load_policy, make_receipt, save_receipt
policy = load_policy(root)
save_receipt(vault.resolve(), policy, make_receipt(policy, "Synthetic Test User", "personal"))
shutil.copyfile(root / "fixtures/write-note/AGENTS.md", vault / "AGENTS.md")
def note(rel, fields, body=""):
    path = vault / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("---\n" + fields + "\n---\n" + body)

note("Personal/2. Projects/Quiet/Quiet.md", "type: project\nstatus: active\narea: personal\nproject: quiet\nprivate: true")
note("Personal/2. Projects/Quiet/Tasks/Secret.md", "type: task\nstatus: active\narea: personal\nproject: quiet\npriority: p1")
note("Personal/2. Projects/Quiet/Tasks/Shareable.md", "type: task\nstatus: todo\narea: personal\nproject: quiet\nprivate: false\ntags: [ai-handoff]")
note("Personal/Tasks/Prepare outline.md", "type: task\nstatus: active\narea: personal\npriority: p1\ntags:\n  - ai-handoff")
note("Personal/Tasks/Choose venue.md", "type: task\nstatus: todo\narea: personal\nblocked_reason: Awaiting a choice\ntags: [ai-handoff]")
note("Personal/Tasks/Add my first project.md", "type: task\nstatus: todo\narea: personal\npriority: p2\ntags: [onboarding]")
note("Personal/Tasks/Wait for approval.md", 'type: task\nstatus: on-hold\narea: personal\nblocked_by:\n  - "[[Choose venue]]"')
note("Personal/Tasks/Closed.md", "type: task\nstatus: done\narea: personal")
note("Personal/Tasks/Private.md", "type: task\nstatus: todo\narea: personal\nprivate: true")
note("Personal/2. Projects/Quiet/Artifacts/Tasks/Copied.md", "type: task\nstatus: active\narea: personal")
note("Personal/2. Projects/Quiet/Notes/Private reflection.md", "date: 2026-10-12\ntype: note\nstatus: capture\narea: personal\nproject: quiet", "Private content must not appear or get stamped in a local-only run.")
note("Personal/2. Projects/Quiet/Artifacts/Copy.md", "date: 2026-10-12\ntype: note\nstatus: capture\narea: personal", "An artifact is not a canonical note.")
before = {p.relative_to(vault): p.read_bytes() for p in vault.rglob("*.md")}

scripts = root / "plugins/ai-os-lite/skills/start-day/scripts"
result = json.loads(subprocess.check_output(["python3", str(scripts / "gather_task_notes.py"), str(vault)], text=True))
assert result["count"] == 5, result
assert result["source"] == "filesystem"
assert {Path(t["path"]).stem for t in result["tasks"]} == {"Shareable", "Prepare outline", "Choose venue", "Wait for approval", "Add my first project"}
assert next(t for t in result["tasks"] if t["path"].endswith("Prepare outline.md"))["tags"] == ["ai-handoff"]
assert next(t for t in result["tasks"] if t["path"].endswith("Wait for approval.md"))["blocked_by"] == ["[[Choose venue]]"]
assert all((vault / path).read_bytes() == data for path, data in before.items())
print("PASS: filesystem tasks include queue metadata, preserve privacy overrides and exclude terminal/artifact copies")
print("PASS: task discovery does not mutate note contents or privacy flags")

# A local-only run must never call either account adapter, even if installed.
bin_dir = tmp / "bin"
bin_dir.mkdir()
marker = tmp / "connector-called"
for tool in ("td", "obsidian"):
    stub = bin_dir / tool
    stub.write_text('#!/bin/sh\ntouch "$TASK_CONNECTOR_MARKER"\nexit 99\n')
    stub.chmod(0o755)
env = dict(os.environ, AI_OS_LOCAL_ONLY="1", PERSONAL_OS_VAULT=str(vault),
           TASK_CONNECTOR_MARKER=str(marker), PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
gathered = json.loads(subprocess.check_output(["bash", str(scripts / "gather_morning_context.sh"), "2026-10-12", str(vault)], env=env, text=True))
assert not marker.exists()
assert gathered["task_notes"]["count"] == 5
assert gathered["todoist"]["skipped"] is True
assert gathered["source_manifest"]["todoist"].startswith("skipped:")
assert gathered["active_projects"] == []
assert gathered["source_manifest"]["calendar"].startswith("skipped:")
assert gathered["source_manifest"]["linear"].startswith("skipped:")
assert all((vault / path).read_bytes() == data for path, data in before.items())
assert "Private reflection" not in json.dumps(gathered) and "Artifacts/Copy" not in json.dumps(gathered)
print("PASS: full local-only gather keeps task data, skips adapters and excludes private project summaries")

spec = importlib.util.spec_from_file_location("render", scripts / "render_start_day.py")
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)
text = render.render(gathered)
dispatch = text.split("#### Dispatch", 1)[1].split("### Threads", 1)[0]
assert "Prepare outline" in dispatch and "Shareable" in dispatch
assert "Choose venue" not in dispatch and "Wait for approval" not in dispatch
assert "Todoist failed" not in text and "Work-item integration failed" not in text
assert "Source gaps" not in text and "Source warning" not in text
assert "Add my first project" in text.split("#### Review", 1)[1].split("#### Decide", 1)[0]
decisions = text.split("#### Decide", 1)[1].split("#### Dispatch", 1)[0]
assert "waiting on [[Choose venue]]" in decisions and "Awaiting a choice" in decisions
assert "decision-gated" not in decisions and "marked for a human decision" not in decisions
assert render.render_meeting_prep({"meetings_today": {"meetings": [{"is_prep": True, "path": "Meeting.md", "start": "2026-10-12T13:00:00", "end": "2026-10-12T14:30:00"}]}}).endswith("(1:00 PM–2:30 PM) - ready; no prep gap")
print("PASS: rendered queue respects blockers and optional-source skips; meeting times use AM/PM")

short_hub = vault / "1. Daily/2026-10-12.md"
short_hub.parent.mkdir(parents=True)
short_hub.write_text("My short human note.\n")
old_contents = short_hub.read_bytes()
kept = json.loads(subprocess.check_output(["bash", str(scripts / "ensure_daily_hub.sh"), "2026-10-12", str(vault)], text=True))
assert kept["created"] is False and short_hub.read_bytes() == old_contents
for helper, rel in (("ensure_daily_hub.sh", "1. Daily/2026-10-13.md"), ("ensure_journal.sh", "5. Resources/Personal/Journal/Morning Entries/2026-10-13.md")):
    first = json.loads(subprocess.check_output(["bash", str(scripts / helper), "2026-10-13", str(vault)], text=True))
    assert first["created"] is True and (vault / rel).is_file()
    content = (vault / rel).read_bytes()
    second = json.loads(subprocess.check_output(["bash", str(scripts / helper), "2026-10-13", str(vault)], text=True))
    assert second["created"] is False and (vault / rel).read_bytes() == content
    invalid = subprocess.run(["bash", str(scripts / helper), "2026-02-31", str(vault)], capture_output=True)
    assert invalid.returncode != 0
print("PASS: scaffold helpers preserve short human notes, create only selected-vault files, repeat without changes and reject invalid dates")
subprocess.run(["git", "init", "-q", str(tmp)], check=True)
snapshot = json.loads(subprocess.check_output(["bash", str(scripts / "commit_daily_scaffold.sh"), "2026-10-13", str(vault)], text=True))
assert snapshot["committed"] is False and snapshot["reason"] == "vault_has_no_own_git_repository"
assert subprocess.check_output(["git", "-C", str(tmp), "diff", "--cached", "--name-only"], text=True) == ""
print("PASS: scaffold snapshot never stages into a containing repository")
PY
