#!/usr/bin/env python3
"""List recent Codex session rollouts — capture-workflow's fallback source.

Usage: list_sessions.py [--root DIR] [--limit N] [--include-subagents]

Exit code / stdout contract:

  exit | meaning              | stdout
  -----|----------------------|-----------------------------------------
  0    | success               | JSON array, newest first by last activity
       |                       | (file mtime); each element {path,
       |                       | timestamp, cwd, originator, subagent,
       |                       | mtime}. `timestamp` is the session start
       |                       | time reported in the payload -- it can
       |                       | differ from `mtime`.
  1    | root directory missing | a single JSON object {"error": "..."}

Subagent rollouts (guardian etc.) are skipped unless --include-subagents.
"""
import argparse
import json
import sys
from pathlib import Path


def _mtime(f, default=float("-inf")):
    try:
        return f.stat().st_mtime
    except OSError:
        return default


def meta(path: Path):
    try:
        with path.open(encoding="utf-8") as fh:
            rec = json.loads(fh.readline())
    except (UnicodeDecodeError, OSError, json.JSONDecodeError):
        return None
    if not isinstance(rec, dict):
        return None
    if rec.get("type") != "session_meta":
        return None
    p = rec.get("payload")
    if not isinstance(p, dict):
        return None
    source = p.get("source")
    is_sub = (isinstance(source, dict) and "subagent" in source) \
        or p.get("thread_source") == "subagent"
    return {
        "path": str(path),
        "timestamp": p.get("timestamp") or rec.get("timestamp"),
        "cwd": p.get("cwd"),
        "originator": p.get("originator"),
        "subagent": bool(is_sub),
        "mtime": _mtime(path, default=None),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="~/.codex/sessions")
    ap.add_argument("--limit", type=int, default=10)
    ap.add_argument("--include-subagents", action="store_true")
    args = ap.parse_args()
    root = Path(args.root).expanduser()
    if not root.is_dir():
        print(json.dumps({"error": f"no session root at {root}"}))
        return 1
    if args.limit <= 0:
        print(json.dumps([]))
        return 0
    files = sorted(root.rglob("rollout-*.jsonl"),
                   key=_mtime, reverse=True)
    out = []
    for f in files:
        m = meta(f)
        if m is None or (m["subagent"] and not args.include_subagents):
            continue
        out.append(m)
        if len(out) >= args.limit:
            break
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
