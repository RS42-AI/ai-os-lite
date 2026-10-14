#!/usr/bin/env python3
"""Read open task metadata from the selected vault without an app connection.

Reuse the audit parser and canonical-note scope. Project privacy is inherited;
an explicit ``private: false`` on a task remains an owner-controlled exception.
This reader never changes task status, content, or privacy flags.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def gather(vault: Path) -> dict:
    audit_path = Path(__file__).resolve().parents[2] / "vault-audit/scripts/audit_vault.py"
    spec = importlib.util.spec_from_file_location("lite_audit", audit_path)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    docs = audit.load_docs(vault)
    private_projects = {
        str(doc.get("project")) for doc in docs
        if doc.type == "project" and str(doc.get("private")).lower() == "true"
    }
    tasks = []
    for doc in docs:
        if doc.type != "task" or "Tasks" not in doc.parts or doc.status not in {"todo", "active", "on-hold"}:
            continue
        private = str(doc.get("private") or "").lower()
        if private == "true" or (private != "false" and str(doc.get("project")) in private_projects):
            continue
        row = {"path": doc.rel, "status": doc.status}
        for field in ("priority", "due_date", "area", "project", "blocked_reason"):
            row[field] = doc.get(field) or ""
        for field in ("tags", "blocked_by"):
            row[field] = audit.as_list(doc.get(field))
        tasks.append(row)
    return {
        "available": True,
        "source": "filesystem",
        "tasks": tasks,
        "count": len(tasks),
        "todo_count": sum(t["status"] == "todo" for t in tasks),
        "active_count": sum(t["status"] == "active" for t in tasks),
        "on_hold_count": sum(t["status"] == "on-hold" for t in tasks),
        "errors": [],
    }


if __name__ == "__main__":
    try:
        result = gather(Path(sys.argv[1]).resolve())
    except (OSError, ValueError) as exc:
        result = {"available": False, "source": "filesystem", "tasks": [], "count": 0,
                  "todo_count": 0, "active_count": 0, "on_hold_count": 0, "errors": [str(exc)]}
    print(json.dumps(result, indent=2))
