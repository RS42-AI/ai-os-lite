#!/usr/bin/env python3
"""Install a validated workflow package for replay.

Usage: install_workflow.py <package_dir> (--codex | --claude | --both) [--force]

Two phases: pre-flight validates the package and every target with zero
filesystem mutation, then (only if every check passes) the commit phase
copies. Targets are HOME-relative (~/.codex/skills/<slug>/,
~/.claude/skills/<slug>/) so tests can sandbox with HOME=<tmp>. Never
overwrites without --force.

Exit code / stdout contract:

  exit | meaning                        | stdout
  -----|--------------------------------|---------------------------------
  0    | success                        | {"installed": [...]}
  1    | refused (pre-flight)           | {"error": "...", "violations"?:
       |                                 |  [...]} -- nothing was written
  2    | usage error                    | (argparse default, or no target
       |                                 |  flag) -- stderr only
  3    | operational failure mid-commit | {"error": "...", "installed":
       |                                 |  [...]} -- partial state
       |                                 |  possible, explicitly reported

Human-readable detail may also go to stderr; stdout on exits 0, 1, and 3
is always exactly one JSON object -- its own contract, distinct from
list_sessions.py's (which emits a JSON array on success).
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from validate_workflow_manifest import parse_manifest  # noqa: E402

VALIDATOR = Path(__file__).with_name("validate_workflow_manifest.py")


def refuse(msg, violations=None):
    payload = {"error": msg}
    if violations is not None:
        payload["violations"] = violations
    print(json.dumps(payload))
    print(f"refused: {msg}", file=sys.stderr)
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("package")
    ap.add_argument("--codex", action="store_true")
    ap.add_argument("--claude", action="store_true")
    ap.add_argument("--both", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    pkg = Path(args.package).expanduser().resolve()
    targets = []
    if args.both or args.codex:
        targets.append(Path.home() / ".codex" / "skills")
    if args.both or args.claude:
        targets.append(Path.home() / ".claude" / "skills")
    if not targets:
        print("error: choose --codex, --claude, or --both", file=sys.stderr)
        return 2

    # --- pre-flight: no filesystem mutation until every check passes ---

    if not pkg.name:
        # A resolved root path has an empty name; `t / ""` silently
        # collapses onto the skills root and --force would rmtree every
        # installed skill under it.
        return refuse(f"'{pkg}' has no directory name to install under")

    res = subprocess.run([sys.executable, str(VALIDATOR), str(pkg)],
                         capture_output=True, text=True)
    if res.returncode != 0:
        violations = None
        try:
            violations = json.loads(res.stdout).get("violations")
        except (json.JSONDecodeError, AttributeError):
            pass
        return refuse(f"{pkg} does not validate", violations=violations)

    manifest = pkg / "workflow.yaml"
    doc, _steps, _errors = parse_manifest(manifest.read_text(encoding="utf-8"))
    slug = doc.get("workflow")
    if slug != pkg.name:
        return refuse(
            f"workflow slug '{slug}' does not match directory name "
            f"'{pkg.name}' -- rename the directory or fix workflow: in "
            "workflow.yaml (the install dir name IS the skill's identity)"
        )

    dests = []
    for t in targets:
        dest = t / pkg.name
        if dest.resolve() == pkg:
            # --force on the installed path itself would rmtree the source
            # and then crash in copytree, destroying the skill irrecoverably.
            return refuse(f"refusing to install {pkg} onto itself")
        if dest.exists() and not args.force:
            return refuse(f"{dest} exists (use --force to replace)")
        dests.append((t, dest))
    # Every target cleared pre-flight above before any copy below -- a
    # later target refusing must not leave an earlier one half-installed.

    # --- commit: pre-flight passed for every target, now copy ---

    installed = []
    try:
        for t, dest in dests:
            if dest.exists():
                shutil.rmtree(dest)
            # symlinks=True is defense-in-depth: the validator already
            # rejects symlinks inside packages, but if one ever slipped
            # through, the default dereferencing copy would pull external
            # file content into the installed skill.
            shutil.copytree(pkg, dest, symlinks=True)
            installed.append(str(dest))
    except OSError as e:
        print(json.dumps({"error": str(e), "installed": installed}))
        print(f"operational failure mid-commit: {e}", file=sys.stderr)
        return 3

    print(json.dumps({"installed": installed}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
