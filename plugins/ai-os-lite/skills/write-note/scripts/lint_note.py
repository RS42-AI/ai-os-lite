#!/usr/bin/env python3
"""Per-note ontology lint for the write-note skill.

Usage: lint_note.py <vault> <note> [<note> ...]

Validates each note's frontmatter against the closed enums parsed live from
{vault}/AGENTS.md by vault-audit's contract loader (single source of truth —
zero embedded schema, per the spec's anti-rot constraint).

Checks (violations → exit 1):
  invalid_type          type not in the closed type enum
  missing_type          no type in frontmatter
  invalid_status        status not allowed for this type
  missing_status        type requires a status and none is set
  unexpected_status     status on a status-free type (person, client, offer, …)
  invalid_area          area not one of the six slugs
  malformed_verb_value  a T-box verb field whose value isn't wikilink(s)
  forbidden_verb_field  part_of written as a field (expressed by project:/area:)
  missing_file          a note argument doesn't exist on disk
Warnings (never fail the exit code):
  routing_mismatch      note's folder doesn't match the type's declared home
  outside_vault         note argument isn't under the vault root (routing check skipped)

Exit: 0 clean, 1 violations, 2 contract/parse failure (mirrors audit_vault.py).
"""
import importlib.util
import json
import re
import sys
from fnmatch import fnmatch
from pathlib import Path

# write-note and vault-audit are shipped as siblings in the same plugin; this
# relative path assumes that packaging and breaks if they're ever split apart.
AUDIT = Path(__file__).resolve().parents[2] / "vault-audit" / "scripts" / "audit_vault.py"
WIKILINK_RE = re.compile(r"\[\[[^\]]+\]\]")


def _load_audit():
    spec = importlib.util.spec_from_file_location("audit_vault", AUDIT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _type_homes(vault: Path, av) -> dict:
    """type -> list of home glob patterns, from the type table's third column."""
    text = (vault / "AGENTS.md").read_text(encoding="utf-8", errors="replace")
    homes: dict = {}
    for t in av._parse_tables(text):
        header = " ".join(t[0]).lower()
        if "value" in header and "where it lives" in header:
            for r in t[1:]:
                if len(r) < 3:
                    continue
                vals = [v for v in av.BACKTICK_RE.findall(r[0]) if av.VALUE_RE.match(v)]
                pats = []
                for cell in av.BACKTICK_RE.findall(r[2]):
                    p = cell.replace("{Area}", "*").replace("{Project}", "*").replace("...", "*")
                    p = p.rstrip("/")
                    pats.append(p + "/*" if not p.endswith("*") else p)
                for v in vals:
                    homes[v] = pats
    return homes


def lint_one(vault: Path, note: Path, contract: dict, homes: dict, av) -> dict:
    violations, warnings = [], []

    def v(check, detail):
        violations.append({"check": check, "file": str(note), "detail": detail})

    def w(check, detail):
        warnings.append({"check": check, "file": str(note), "detail": detail})

    text = note.read_text(encoding="utf-8", errors="replace")
    fm_lines, _ = av.split_frontmatter(text)
    fm = av.parse_frontmatter(fm_lines) if fm_lines else {}

    t = av.normalize_scalar(str(fm.get("type", "") or ""))
    status = av.normalize_scalar(str(fm.get("status", "") or ""))
    area = av.normalize_scalar(str(fm.get("area", "") or ""))

    if not t:
        v("missing_type", "no type in frontmatter")
    elif t not in contract["types"]:
        v("invalid_type", f"type '{t}' is not in the closed list")

    if t in contract["status_by_type"]:
        if not status:
            v("missing_status", f"type '{t}' requires a status")
        elif status not in contract["status_by_type"][t]:
            v("invalid_status", f"status '{status}' not allowed for type '{t}'")
    elif t and t in contract["types"] and status:
        v("unexpected_status", f"type '{t}' carries no status field (got '{status}')")

    if area and area not in contract["areas"]:
        v("invalid_area", f"area '{area}' is not one of the area slugs")

    if "part_of" in fm:
        v("forbidden_verb_field",
          "part_of is expressed by project:/area: + folder placement, never a field")

    for field in sorted(contract.get("verb_fields", set())):
        if field not in fm or field in ("project", "area"):
            continue
        vals = fm[field] if isinstance(fm[field], list) else [fm[field]]
        for val in vals:
            if not str(val).strip():
                continue  # empty scaffold residue (e.g. blocked_by: "") isn't a malformed link
            if not WIKILINK_RE.search(str(val)):
                v("malformed_verb_value",
                  f"{field}: '{val}' is not a [[wikilink]]")

    if t in homes:
        try:
            rel = str(note.relative_to(vault))
        except ValueError:
            w("outside_vault", f"note is not under the vault root {vault}")
        else:
            if not any(fnmatch(rel, pat) for pat in homes[t]):
                w("routing_mismatch",
                  f"type '{t}' lives in {homes[t]}, note is at '{rel}'")

    return {"violations": violations, "warnings": warnings}


def main() -> int:
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: lint_note.py <vault> <note> [...]"}))
        return 2
    vault = Path(sys.argv[1]).resolve()
    av = _load_audit()
    contract, errors, _ = av.load_agents_contract(vault)
    if contract is None:
        print(json.dumps({"error": "contract parse failure", "details": errors}))
        return 2
    homes = _type_homes(vault, av)
    result = {"violations": [], "warnings": []}
    for arg in sys.argv[2:]:
        note = Path(arg).resolve()
        if not note.is_file():
            result["violations"].append(
                {"check": "missing_file", "file": arg, "detail": "note not found"})
            continue
        one = lint_one(vault, note, contract, homes, av)
        result["violations"] += one["violations"]
        result["warnings"] += one["warnings"]
    print(json.dumps(result, indent=2))
    return 1 if result["violations"] else 0


if __name__ == "__main__":
    sys.exit(main())
