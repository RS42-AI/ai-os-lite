#!/usr/bin/env python3
"""Read-only vault conformance auditor for AI-OS.

Grades the LIVE vault against the contracts already written in AGENTS.md and
emits a categorized health report. Deterministic — no LLM in the loop. The
thin AI layer (a skill) ranks/interprets the JSON this produces.

It NEVER mutates the vault and NEVER writes `status: done` (human-only).

Checks (see AGENTS.md):
  taxonomy.{type,status,area}  routing.{task,devlog,spec,goal,meeting}
  goal_wiring.{no_goal,broad_goal_only}
  connectivity.{devlog_no_task,task_link_unresolved,task_project_unresolved,
                goal_link_unresolved,broken_wikilink}
  structure.{project_container_missing,section_renamed,
             required_section_missing,optional_section_missing,mistyped_hub,
             unknown_section,section_order}
  hygiene.{oversized,superseded_no_pointer,duplicate_heading}
  privacy.unstamped_child

Severity model (decision point 1 in the build task — tune the sets below):
  violation = a hard contract breach that makes data wrong/unparseable/unchained
  smell     = a confidence-lowering signal, not an error (per the orphan-note doctrine)

Closed enums are parsed from {vault}/AGENTS.md at runtime — see load_agents_contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Auditor policy (judgment calls, not AGENTS.md content). The closed enums
# (types, per-type statuses, areas) are NOT here — they're parsed at runtime
# from the vault's own AGENTS.md; see load_agents_contract below.
# ---------------------------------------------------------------------------

# type -> required path segment (segment match, not substring — handles numeric
# prefixes like "3. Areas/" correctly: we look for an exact path part).
ROUTING_SEGMENT = {
    "task": "Tasks",
    "devlog": "Dev Log",
    "spec": "Specs",
    "goal": "Goals",
    "meeting": "Meetings",
}

# doc-example placeholders that legitimately appear unresolved in prose.
PLACEHOLDERS = {
    "goal note", "hub note", "task", "full name", "note name", "source",
    "section", "parent hub", "their-name", "name", "previous note",
    "goal hub", "project hub", "full source name", "short name", "replacement",
}

# directories that are not live vault content. `.claude` holds memory + commands
# and is off-limits per AGENTS.md; templates carry intentional placeholder values;
# `setup-kit` + `Vault-Setup-Artifact` are vault-setup kit fixtures, not live notes.
SKIP_DIR_PARTS = {"system-settings", ".obsidian", ".trash", ".git", "node_modules",
                  ".claude", ".ai-os", "Artifacts", "setup-kit", "Vault-Setup-Artifact"}

# a project's own content subfolders. A project hub nested one level deeper than
# `2. Projects/{Area}/{Project}/` because its parent is one of THESE is normal (it's
# the hub sitting in its project folder); nested under anything else means a
# grouping/platform folder (e.g. Managed-AI/) sits between Area and Project.
CONTENT_SUBFOLDERS = {
    "Notes", "Tasks", "Dev Log", "Specs", "Resources", "Artifacts", "Meetings",
}

# The portable project structure shared with Vault Setup Kit. These are empty
# capable containers: their existence is structural and never implies that
# human-authored content should be fabricated inside them.
REQUIRED_PROJECT_CONTAINERS = (
    "Tasks", "Notes", "Resources", "Artifacts", "Specs", "Dev Log",
)
PACKAGED_STRUCTURE_CONTRACT = (
    Path(__file__).resolve().parent.parent / "references" / "project-structure.json"
)


def load_project_structure_contract(vault: Path) -> tuple[dict[str, Any], str, list[str]]:
    """Load the portable Kit/Lite structure definition.

    An installed vault may carry a newer reviewed copy; otherwise the definition
    paired with this Lite release is authoritative. Invalid content degrades to
    the safe packaged defaults and is reported rather than guessed.
    """
    warnings: list[str] = []
    installed = vault / "system-settings" / "Contracts" / "project-structure.json"
    source = installed if installed.is_file() else PACKAGED_STRUCTURE_CONTRACT
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        warnings.append(f"project structure contract cannot be parsed ({exc})")
        return ({"schema_version": 1,
                 "required_project_containers": list(REQUIRED_PROJECT_CONTAINERS)},
                "built-in safe fallback", warnings)
    if not isinstance(data, dict):
        warnings.append("project structure contract root must be an object")
        data = {"schema_version": 1}
    containers = data.get("required_project_containers")
    if not isinstance(containers, list) or not containers or any(
        not isinstance(item, str) or not item or "/" in item or item in {".", ".."}
        for item in containers
    ):
        warnings.append("project structure contract has invalid required_project_containers")
        data["required_project_containers"] = list(REQUIRED_PROJECT_CONTAINERS)
    try:
        source_label = str(source.relative_to(vault))
    except ValueError:
        source_label = "AI-OS Lite packaged project-structure.json"
    return data, source_label, warnings

# Structural headings rendered by skills/templates that must appear at most once
# per note. Repeated *content* headings (Symptoms, Root Cause, The Fix...) across
# multi-incident notes are legitimate and are NOT flagged.
STRUCTURAL_HEADINGS = {
    "morning brief", "morning journal", "ai summary", "current status", "overview", "control queue",
    "today's plan", "work anchor", "routing exceptions", "overall read",
    "threads to keep visible", "execution report", "today's accomplishments",
    "tomorrow preview", "wind down", "objective", "key results",
}

# --- Structural conformance: templates are the SECTION source of truth ----------
# A hub's body should carry the `##` sections its TYPE's template defines. Skills
# read/patch those headings (e.g. /project-sync writes `## Current Status`; many
# sections are `base` queries a skill can run directly), so a hub that drops or
# renames them silently breaks automation. We DERIVE the canonical section list by
# reading the template at runtime (see load_template_sections) — never hardcode it,
# so the template stays the single source of truth (AGENTS.md: shape lives in
# templates). Add a type here + its REQUIRED set below to bring it under audit.
TYPE_TEMPLATE = {
    "project": "Project Hub Template.md",
    "area-dashboard": "Area Dashboard Template.md",
    "goal": "Goal Hub Template.md",
}

# POLICY (severity), not shape: which template sections are load-bearing. Missing a
# required section is a violation; missing any other template section is a smell.
# This is a judgement call (patch targets + core queries) so it lives here, not in
# the template. Keys must be a subset of the template's actual sections.
REQUIRED_SECTIONS = {
    "project": {"overview", "current status", "active tasks", "dev log"},
    "area-dashboard": {"goals", "projects", "active tasks"},
    "goal": {"objective", "key results", "linked projects — how each contributes",
             "quarterly checkpoints"},
}

# Which status values make a note a structural-audit subject, per type. "" covers
# hubs that legitimately carry no status field.
STRUCTURE_STATUS = {
    "project": {"active"},
    "area-dashboard": {"active", ""},
    "goal": {"active"},
}

# Template sections that are illustrative prose, not a slot every instance must
# fill — their absence is not drift. Still recognized as canonical (so a present
# one isn't counted an 'extra'); we just don't flag them when missing.
IGNORE_MISSING = {
    "goal": {"why this objective and not another", "why these krs",
             "what's intentionally not in this goal", "open", "related",
             "open tasks (cross-project, this area)", "recent dev logs",
             "frontmatter reference"},
    # promoted 2026-07-04 (Species D): canonical when present, never demanded
    "project": {"bug queue", "specs", "predecessor projects"},
    # journal is the personal dashboard's section; meetings isn't universal
    "area-dashboard": {"journal", "meetings"},
}

# Known rename drift -> canonical section name. A remediation hint (how people
# misspell the canonical heading), not template content. Applied only when the
# heading is NOT itself canonical for the note's type (so "## Notes" is fine on an
# area-dashboard but a rename of "Knowledge Notes" on a project).
SECTION_ALIASES = {
    "related": "related projects",
    "notes": "knowledge notes",
    "development log": "dev log",
    "dev logs": "dev log",
    # goal-note variants observed in the 2026-07-04 alignment map (Species B):
    # pre-consensus headings -> May-consensus canon
    "why this goal exists": "why this objective and not another",
    "why these krs (not other ones)": "why these krs",
    "why these krs and not others": "why these krs",
    "quarterly slices": "quarterly checkpoints",
    "linked projects": "linked projects — how each contributes",
    "linked projects — q2 contribution": "linked projects — how each contributes",
    "out of scope for q2": "what's intentionally not in this goal",
    "out of scope for 2026": "what's intentionally not in this goal",
    # dashboard/hub variants (alignment map Species B, second pass 2026-07-05):
    "2026 goals": "goals",
    "active projects": "projects",
    "open tasks": "active tasks",
    "tasks": "active tasks",
    "recent dev logs": "dev logs",
    "recent devlogs": "dev logs",
}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
NUM_PREFIX_RE = re.compile(r"^\d+\.\s*")  # "1. Goals" / "3. Areas" ordering prefix

VIOLATION_CHECKS = {
    "taxonomy.type", "taxonomy.status", "taxonomy.area",
    "routing.task", "routing.devlog", "routing.spec", "routing.goal", "routing.meeting",
    "routing.resource", "goal_wiring.goal_status_retired",
    "connectivity.devlog_no_task", "connectivity.task_link_unresolved",
    "connectivity.task_project_unresolved", "connectivity.goal_link_unresolved",
    "structure.section_renamed", "structure.mistyped_hub",
    "structure.required_section_missing",
    "structure.project_container_missing",
}

WIKI_RE = re.compile(r"\[\[([^\]]+)\]\]")
FENCED_RE = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE_RE = re.compile(r"`[^`]*`")
HEADING_RE = re.compile(r"^#{1,6}\s+(.*\S)\s*$")
H2_RE = re.compile(r"^##\s+(.+?)\s*$")  # exactly level-2 (## but not ### …)


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def normalize_scalar(value: str) -> str:
    value = value.strip()
    if value in {"", '""', "''"}:
        return ""
    return value.strip('"').strip("'")


def split_frontmatter(text: str) -> tuple[list[str], str]:
    """Return (frontmatter_lines, body_text)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return [], text
    fm: list[str] = []
    body_start = len(lines)
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            body_start = i + 1
            break
        fm.append(line)
    return fm, "\n".join(lines[body_start:])


def parse_frontmatter(fm_lines: list[str]) -> dict[str, Any]:
    data: dict[str, Any] = {}
    current: str | None = None
    for line in fm_lines:
        if not line.strip():
            continue
        if line.lstrip().startswith("- "):
            if current:
                data.setdefault(current, [])
                if not isinstance(data[current], list):
                    data[current] = []
                item = normalize_scalar(line.split("-", 1)[1])
                if item:
                    data[current].append(item)
            continue
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        key = key.strip()
        raw = raw.strip()
        current = key
        if raw == "":
            data[key] = []
        elif raw.startswith("[") and raw.endswith("]"):
            inner = raw[1:-1].strip()
            data[key] = [normalize_scalar(p) for p in re.split(r",\s*", inner) if normalize_scalar(p)] if inner else []
        else:
            data[key] = normalize_scalar(raw)
    return data


def wiki_target(value: Any) -> str:
    if isinstance(value, list):
        value = value[0] if value else ""
    if not value:
        return ""
    s = str(value)
    m = WIKI_RE.search(s)
    target = m.group(1) if m else s
    return target.split("|", 1)[0].split("#", 1)[0].strip()


def slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def as_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return value
    if value in (None, ""):
        return []
    return [str(value)]


# ---------------------------------------------------------------------------
# Contract loading — AGENTS.md is the single source of truth for the closed
# enums. There is deliberately NO baked-in fallback: silently auditing against
# stale constants is the exact drift this tool exists to catch, so a missing
# or unparseable contract is a loud exit-2.
# ---------------------------------------------------------------------------

VALUE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
AMNESTY_RE = re.compile(r"on/after\s+`(\d{4}-\d{2}-\d{2})`")
BACKTICK_RE = re.compile(r"`([^`]+)`")
SEP_CELL_RE = re.compile(r"^:?-{3,}:?$")
VERB_FIELD_RE = re.compile(r"^[a-z][a-z0-9_]*:$")


def _parse_tables(text: str) -> list[list[list[str]]]:
    """Every markdown pipe table (outside fenced code) as rows of stripped
    cells — header row first, |---|-separator rows removed."""
    tables: list[list[list[str]]] = []
    cur: list[list[str]] = []
    for line in FENCED_RE.sub("", text).splitlines():
        s = line.strip()
        if s.startswith("|") and s.endswith("|") and len(s) > 1:
            cells = [c.strip() for c in s[1:-1].split("|")]
            if cells and all(SEP_CELL_RE.match(c) for c in cells if c):
                continue
            cur.append(cells)
        else:
            if len(cur) >= 2:
                tables.append(cur)
            cur = []
    if len(cur) >= 2:
        tables.append(cur)
    return tables


def load_agents_contract(vault: Path) -> tuple[dict[str, Any] | None, list[str], list[str]]:
    """Parse the closed enums out of {vault}/AGENTS.md.

    Returns (contract, errors, warnings); contract is None when errors block.
    Tables are matched by HEADER SIGNATURE, not section heading, so the founder
    vault and kit-generated instances both parse as long as they keep the
    canonical column names:
      areas:  | Area folder | `area` slug |
      types:  | Value | Description | Where it lives |
      status: | `type` | allowed `status` (progression →) | pause / terminal |
      verbs:  | Verb | Meaning (A —verb→ B) | Written as |
    """
    f = vault / "AGENTS.md"
    if not f.is_file():
        return None, [f"no AGENTS.md at {f} — the audit has no contract to grade against"], []
    text = f.read_text(encoding="utf-8", errors="replace")
    tables = _parse_tables(text)
    errors: list[str] = []
    warnings: list[str] = []

    def rows_for(*sig: str) -> list[list[str]] | None:
        for t in tables:
            header = " ".join(t[0]).lower()
            if all(s in header for s in sig):
                return t[1:]
        return None

    def ticked(cell: str) -> list[str]:
        return [v for v in BACKTICK_RE.findall(cell) if VALUE_RE.match(v)]

    areas: set[str] = set()
    area_folders: dict[str, str] = {}
    rows = rows_for("area folder", "slug")
    if rows is None:
        errors.append("AGENTS.md: areas table not found (need header '| Area folder | `area` slug |')")
    else:
        for r in rows:
            if len(r) >= 2:
                slugs = ticked(r[1])
                folders = BACKTICK_RE.findall(r[0])
                areas.update(slugs)
                if slugs and folders:
                    area_folders[slugs[0]] = folders[0].strip().rstrip("/")
        if not areas:
            errors.append("AGENTS.md: areas table has no parseable slug values")

    types: set[str] = set()
    rows = rows_for("value", "where it lives")
    if rows is None:
        errors.append("AGENTS.md: type table not found (need header '| Value | Description | Where it lives |')")
    else:
        for r in rows:
            if r:
                types.update(ticked(r[0]))
        if not types:
            errors.append("AGENTS.md: type table has no parseable values")
        elif "person" not in types:
            # Person Template + the status table use `person`; a type list without
            # it would flood every contact note with false positives.
            types.add("person")
            warnings.append("`person` missing from AGENTS.md type table — supplemented "
                            "(Person Template uses it); consider adding the row")

    status_by_type: dict[str, set[str]] = {}
    rows = rows_for("type", "status")
    if rows is None:
        errors.append("AGENTS.md: per-type status table not found "
                      "(need header '| `type` | allowed `status` … |')")
    else:
        for r in rows:
            if len(r) < 2:
                continue
            row_types = ticked(r[0])
            rest = " ".join(r[1:])
            if re.search(r"no\s+`?status`?", rest, re.IGNORECASE):
                continue  # deliberately status-free types: never validated
            vals = set(ticked(rest))
            for t in row_types:
                if vals:
                    status_by_type[t] = vals
        if not status_by_type:
            errors.append("AGENTS.md: status table has no parseable per-type values")

    verb_fields: set[str] = set()
    rows = rows_for("verb", "written as")
    if rows is None:
        warnings.append("AGENTS.md: relationship-verbs table not found "
                        "(need header '| Verb | … | Written as |') — verb lint disabled")
    else:
        for r in rows:
            if not r:
                continue
            if "never a separate field" in " ".join(r).lower():
                continue  # part_of is expressed by project:/area:, not a field
            verb_fields.update(v[:-1] for v in BACKTICK_RE.findall(r[-1])
                               if VERB_FIELD_RE.match(v))
        if not verb_fields:
            warnings.append("AGENTS.md: relationship-verbs table found but no verb fields "
                            "parsed — verb lint disabled")

    m = AMNESTY_RE.search(text)
    amnesty = m.group(1) if m else ""

    if errors:
        return None, errors, warnings
    return ({"types": types, "status_by_type": status_by_type, "areas": areas,
             "area_folders": area_folders, "amnesty_date": amnesty,
             "verb_fields": verb_fields}, [], warnings)


MACHINE_CONTRACT_FILES = {
    "node": "node-contract.json",
    "body": "body-contract.json",
    "relationship": "relationship-contract.json",
}


def load_machine_contracts(vault: Path) -> dict[str, Any]:
    """Compile reviewed machine-contract coverage without promoting drafts.

    A profile is effective only when it says ``state: ratified`` and carries a
    matching approval receipt. ``writer_only`` applies to newly written notes;
    corpus audit/repair additionally requires ``all_instances``. Candidate,
    incomplete, missing, and malformed profiles remain advisory coverage gaps.
    """
    root = vault / "system-settings" / "Contracts"
    coverage: dict[str, Any] = {
        "families": {},
        "missing_files": [],
        "warnings": [],
        "effective_writer": {},
        "effective_audit": {},
        "implemented_writer": {},
        "implemented_audit": {},
        "profiles": {},
        "template_map": {},
        "template_contract": None,
    }
    for family, filename in MACHINE_CONTRACT_FILES.items():
        path = root / filename
        coverage["effective_writer"][family] = []
        coverage["effective_audit"][family] = []
        coverage["implemented_writer"][family] = []
        coverage["implemented_audit"][family] = []
        coverage["profiles"][family] = {}
        if not path.is_file():
            coverage["missing_files"].append(str(path.relative_to(vault)))
            coverage["families"][family] = {
                "ratified": [], "candidate": [], "unreviewed": [],
            }
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            coverage["warnings"].append(f"{filename}: cannot parse ({exc})")
            coverage["families"][family] = {
                "ratified": [], "candidate": [], "unreviewed": [],
            }
            continue
        profiles = data.get("profiles") if isinstance(data, dict) else None
        approvals = data.get("approvals", {}) if isinstance(data, dict) else {}
        if not isinstance(profiles, dict):
            coverage["warnings"].append(f"{filename}: profiles object missing")
            profiles = {}
        coverage["profiles"][family] = profiles
        if not isinstance(approvals, dict):
            approvals = {}
        states = {"ratified": [], "candidate": [], "unreviewed": []}
        for name, profile in sorted(profiles.items()):
            if not isinstance(profile, dict):
                states["unreviewed"].append(name)
                continue
            state = profile.get("state")
            scope = profile.get("enforcement_scope")
            receipt = approvals.get(name)
            digest = "sha256:" + hashlib.sha256(
                json.dumps(profile, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest()
            reviewed = (
                state == "ratified"
                and isinstance(receipt, dict)
                and receipt.get("profile_digest") == digest
            )
            if reviewed:
                states["ratified"].append(name)
                if scope in {"writer_only", "all_instances"}:
                    coverage["effective_writer"][family].append(name)
                if scope == "all_instances":
                    coverage["effective_audit"][family].append(name)
            elif state == "candidate":
                states["candidate"].append(name)
            else:
                states["unreviewed"].append(name)
        coverage["families"][family] = states

    # This release's deterministic machine-profile checker implements required
    # body anchors for new notes. Node and relationship profiles are surfaced as
    # reviewed/advisory coverage but are not falsely claimed as enforced. Closed
    # enums, routes, and relationship field syntax still come from AGENTS.md.
    coverage["implemented_writer"]["body"] = list(
        coverage["effective_writer"].get("body", [])
    )

    # New kits place this manifest with the other contracts. Read the historical
    # Templates location too so existing installations stay legible during the
    # transition. Absence is reported; it never licenses a hardcoded fallback.
    candidates = [
        root / "template-contract.json",
        vault / "system-settings" / "Templates" / "template-contract.json",
    ]
    for path in candidates:
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            coverage["warnings"].append(
                f"{path.relative_to(vault)}: cannot parse ({exc})"
            )
            break
        mapping = data.get("canonical_templates", {}) if isinstance(data, dict) else {}
        if isinstance(mapping, dict):
            coverage["template_map"] = {
                str(key): str(value) for key, value in mapping.items()
                if isinstance(key, str) and isinstance(value, str)
            }
            coverage["template_contract"] = str(path.relative_to(vault))
        else:
            coverage["warnings"].append(
                f"{path.relative_to(vault)}: canonical_templates object missing"
            )
        break
    if coverage["template_contract"] is None:
        coverage["missing_files"].append(
            "system-settings/Contracts/template-contract.json"
        )
    return coverage


# ---------------------------------------------------------------------------
# Document model
# ---------------------------------------------------------------------------

class Doc:
    def __init__(self, path: Path, rel: str, text: str):
        self.path = path
        self.rel = rel
        fm_lines, self.body = split_frontmatter(text)
        self.fm = parse_frontmatter(fm_lines)
        self.title = path.stem
        self.line_count = text.count("\n") + 1
        self.parts = rel.split("/")

    def get(self, key: str) -> Any:
        return self.fm.get(key)

    @property
    def type(self) -> str:
        return str(self.fm.get("type", "")).strip()

    @property
    def status(self) -> str:
        return str(self.fm.get("status", "")).strip()


def registered_artifact_roots(vault: Path) -> list[dict[str, str]]:
    config = vault / "system-settings" / "workspace-layout.json"
    if not config.exists():
        return []
    data = json.loads(config.read_text())
    roots = data.get("artifact_roots", [])
    if not isinstance(roots, list):
        raise ValueError("workspace-layout artifact_roots must be a list")
    for row in roots:
        if not isinstance(row, dict) or not all(isinstance(row.get(k), str) and row[k] for k in ("path", "project", "reason")):
            raise ValueError("Each artifact root needs a path, project and reason")
        rel = Path(row["path"])
        if rel.is_absolute() or ".." in rel.parts or len(rel.parts) < 4 or rel.parts[0] not in {"2. Projects", "Personal"}:
            raise ValueError("Artifact root must be a project subfolder")
        if rel.name in {"Tasks", "Notes", "Specs", "Dev Log", "Resources"}:
            raise ValueError("Canonical note containers cannot be excluded as artifacts")
        path = vault / rel
        if not path.is_dir() or any(p.is_symlink() for p in (path, *path.parents) if p != vault):
            raise ValueError("Artifact root must be an existing non-symlink directory")
        # A declaration must point below its actual owning project hub.
        owners = []
        for hub in path.parent.glob("*.md"):
            fm_lines, _ = split_frontmatter(hub.read_text())
            fm = parse_frontmatter(fm_lines)
            if str(fm.get("type", "")) == "project" and str(fm.get("project", "")) == row["project"]:
                owners.append(hub)
        if len(owners) != 1:
            raise ValueError("Artifact root owner is missing or ambiguous: " + row["path"])
    return roots


def scan_scope(vault: Path) -> dict[str, Any]:
    """Disclose artifact coverage separately from canonical note validation."""
    registered = registered_artifact_roots(vault)
    artifact_markdown = 0
    for root_name in ("2. Projects", "Personal"):
        root = vault / root_name
        if root.is_dir():
            artifact_markdown += sum(1 for p in root.rglob("*.md") if ("Artifacts" in p.relative_to(vault).parts or any(p.is_relative_to(vault / r["path"]) for r in registered)) and not p.is_symlink())
    return {"canonical_notes": "routed Markdown outside runtime, templates and project Artifacts",
            "artifact_markdown_count": artifact_markdown,
            "registered_artifact_roots": registered,
            "artifact_validation": "location inventory only; contents are not certified as canonical notes",
            "misplaced_output_roots": [name for name in ("tmp", "outputs", "media-news-workspace", "Vault-Setup-Artifact", "Users") if (vault / name).exists()]}


def load_docs(vault: Path) -> list[Doc]:
    registered = registered_artifact_roots(vault)
    docs: list[Doc] = []
    for path in sorted(vault.rglob("*.md"), key=lambda p: str(p).lower()):
        rel = str(path.relative_to(vault))
        if any(part in SKIP_DIR_PARTS for part in rel.split("/")):
            continue
        if path.is_symlink() or any(path.is_relative_to(vault / row["path"]) for row in registered):
            continue
        if rel.endswith(".excalidraw.md"):
            continue  # diagram JSON, not prose
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            text = path.read_text(encoding="utf-8", errors="replace")
        if not text.lstrip().startswith("---"):
            continue  # no frontmatter -> not a routed note; skip in v1
        docs.append(Doc(path=path, rel=rel, text=text))
    return docs


def project_root(doc: Doc) -> str | None:
    """Return an established project's vault-relative root.

    Hub identity is structural (``Folder/Folder.md``), so customized area names
    and optional business grouping folders need no embedded configuration.
    Direct ``Personal/{Project}/`` hubs remain readable as legacy roots while
    the Kit previews their move to ``Personal/2. Projects/{Project}/``.
    """
    if doc.type != "project" or (
        doc.path.parent.name != doc.title and doc.path.name != "PROJECT.md"
    ):
        return None
    parts = doc.parts
    if len(parts) >= 4 and parts[0] == "2. Projects":
        return str(Path(doc.rel).parent)
    if len(parts) >= 4 and parts[:2] == ["Personal", "2. Projects"]:
        return str(Path(doc.rel).parent)
    reserved = {"1. Goals", "2. Projects", "Goals", "Tasks", "Thoughts"}
    if len(parts) == 3 and parts[0] == "Personal" and parts[1] not in reserved:
        return str(Path(doc.rel).parent)
    return None


def expected_area_root(contract: dict[str, Any], area: str, top: str) -> str | None:
    folder = contract.get("area_folders", {}).get(area)
    if not folder:
        return None
    if area == "personal" or folder == "Personal":
        return f"{top}/Personal"
    return f"{top}/{Path(folder).name}"


def allowed_route_prefixes(doc_type: str, area: str, project_slug: str,
                           project_roots_by_slug: dict[str, list[str]],
                           contract: dict[str, Any]) -> list[str]:
    if doc_type not in {"task", "resource"}:
        return []
    if project_slug and project_slug in project_roots_by_slug:
        container = "Tasks" if doc_type == "task" else "Resources"
        return [f"{root}/{container}/" for root in project_roots_by_slug[project_slug]]
    if project_slug:
        return []
    if doc_type == "task":
        if area == "personal":
            return ["Personal/Tasks/"]
        root = expected_area_root(contract, area, "2. Projects")
        return [f"{root}/Tasks/"] if root else []
    if area == "personal":
        return ["5. Resources/Personal/"]
    root = expected_area_root(contract, area, "5. Resources")
    return [f"{root}/"] if root else []


def load_template_sections(vault: Path, effective_types: set[str],
                           template_map: dict[str, str]) -> tuple[dict[str, list[str]], list[str]]:
    """Load sections only for ratified, corpus-wide body profiles.

    A template renders an effective contract; it cannot create one. Candidate
    profiles and writer-only approvals therefore never reach this function.
    """
    sections: dict[str, list[str]] = {}
    warnings: list[str] = []
    tdir = vault / "system-settings" / "Templates"
    for typ in sorted(effective_types):
        fname = template_map.get(typ)
        if not fname:
            warnings.append(
                f"ratified all-instances body profile '{typ}' has no canonical template mapping"
            )
            continue
        f = tdir / fname
        if not f.is_file():
            warnings.append(f"template missing for type '{typ}': {f} — "
                            "structural audit SKIPPED for this type")
            continue
        _, body = split_frontmatter(f.read_text(encoding="utf-8", errors="replace"))
        nocode = FENCED_RE.sub("", body)
        secs = [m.group(1).strip().lower()
                for line in nocode.splitlines() if (m := H2_RE.match(line))]
        # required-section policy must reference sections that actually exist
        for req in REQUIRED_SECTIONS.get(typ, set()):
            if req not in secs:
                warnings.append(f"REQUIRED_SECTIONS['{typ}'] names '{req}' which is "
                                f"not a section in {fname} — policy/template mismatch")
        sections[typ] = secs
    return sections, warnings


# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------

def audit(vault: Path, contract: dict[str, Any], amnesty_date: str = "") -> dict[str, Any]:
    valid_types = contract["types"]
    status_by_type = contract["status_by_type"]
    valid_areas = contract["areas"]

    docs = load_docs(vault)
    structure_contract, structure_source, structure_warnings = \
        load_project_structure_contract(vault)
    machine_contracts = load_machine_contracts(vault)
    template_sections, template_warnings = load_template_sections(
        vault,
        set(machine_contracts["implemented_audit"].get("body", [])),
        machine_contracts["template_map"],
    )
    issues: list[dict[str, str]] = []
    shape_inventory: list[dict[str, str]] = []

    def flag(doc: Doc, check: str, label: str, detail: str) -> None:
        issues.append({
            "file": doc.rel,
            "doc_type": doc.type,
            "check": check,
            "severity": "violation" if check in VIOLATION_CHECKS else "smell",
            "label": label,
            "detail": detail,
        })

    # indexes
    titles: dict[str, list[str]] = {}
    for d in docs:
        titles.setdefault(d.title.lower(), []).append(d.rel)
    tasks_by_title = {d.title.lower(): d for d in docs if d.type == "task"}
    projects_by_slug: dict[str, Doc] = {}
    project_roots_by_slug: dict[str, list[str]] = {}
    for d in docs:
        if d.type == "project":
            slug = slugify(str(d.get("project") or d.title))
            projects_by_slug.setdefault(slug, d)
            root = project_root(d)
            if root:
                project_roots_by_slug.setdefault(slug, []).append(root)

    def link_key(target: str) -> str:
        # A wikilink target -> its match key: the final path segment, WITHOUT stripping
        # a suffix. Path(...).stem mangles dotted titles — "[[Fix match-task-note.sh
        # keyword…]]" would truncate to "Fix match-task-note", and "v1.8.5" to "v1.8" —
        # so dotted task/note names never resolved. Only a literal trailing ".md" (rare
        # in wikilinks) is stripped, to mirror the file-side title (path.stem of "X.md").
        name = Path(target).name
        return name[:-3] if name.lower().endswith(".md") else name

    def resolves(target: str) -> bool:
        return link_key(target).lower() in titles

    for d in docs:
        t = d.type
        if not d.fm and not d.body.strip():
            flag(d, "hygiene.empty_placeholder", "empty_placeholder",
                 "Empty note placeholder: preserve its links and decide whether to fill or remove it; no content was fabricated.")
            continue

        # ---- taxonomy ----
        if t and t not in valid_types:
            if t == "combined" and d.rel.startswith("4. Contacts/Meetings/"):
                # A third-party meeting-transcription sync can write type:'combined'
                # (AGENTS.md-forbidden) ahead of its own bug fix. Parked as a smell
                # rather than a violation so it stays visible without inflating the
                # count — the fix belongs in the sync integration, not per-file retyping.
                flag(d, "taxonomy.parked_combined", "meeting_sync_combined",
                     "type 'combined' from a third-party meeting sync — parked (fix "
                     "the sync integration, not the file)")
            else:
                flag(d, "taxonomy.type", "invalid_type", f"type '{t}' is not in the closed list")
        if t in status_by_type and d.status and d.status not in status_by_type[t]:
            flag(d, "taxonomy.status", "invalid_status",
                 f"status '{d.status}' not allowed for type '{t}'")
        area = str(d.get("area") or "").strip()
        if area and area not in valid_areas:
            flag(d, "taxonomy.area", "invalid_area", f"area '{area}' is not in AGENTS.md's areas table")

        # ---- routing ---- (tolerate numeric ordering prefixes: "1. Goals" == "Goals")
        seg = ROUTING_SEGMENT.get(t)
        if seg:
            norm_parts = {NUM_PREFIX_RE.sub("", p) for p in d.parts}
            if seg not in norm_parts:
                flag(d, f"routing.{t}", "misrouted",
                     f"type '{t}' must live under a '{seg}/' folder")

        # Resolve task/resource destinations from the installed area's folder
        # mapping and established hub roots. This distinguishes a business-area
        # task accidentally filed under Personal from a valid personal task.
        rel = d.rel
        project_slug = slugify(str(d.get("project") or ""))
        if t == "task" and area in valid_areas:
            allowed = allowed_route_prefixes(
                t, area, project_slug, project_roots_by_slug, contract
            )
            if allowed and not any(rel.startswith(prefix) for prefix in allowed):
                flag(d, "routing.task", "misrouted",
                     f"task route does not match its area/project; expected one of {allowed}")
        if t == "resource" and area in valid_areas:
            allowed = allowed_route_prefixes(
                t, area, project_slug, project_roots_by_slug, contract
            )
            if allowed and not any(rel.startswith(prefix) for prefix in allowed):
                flag(d, "routing.resource", "misrouted",
                     f"resource route does not match its area/project; expected one of {allowed}")

        # ---- goal wiring (active project hubs only) ----
        if t == "project" and d.status == "active":
            goal = wiki_target(d.get("goal"))
            gstatus = str(d.get("goal_status") or "").strip()
            qgoal = wiki_target(d.get("quarter_goal"))
            kr = str(d.get("kr") or "").strip()
            if gstatus:
                flag(d, "goal_wiring.goal_status_retired", "goal_status_retired",
                     "goal_status is retired migration debt; it cannot replace goal:")
            if not goal:
                flag(d, "goal_wiring.no_goal", "no_goal",
                     "active project hub has no resolving goal candidate")
            elif goal and "annual" in goal.lower() and not qgoal and not kr:
                flag(d, "goal_wiring.broad_goal_only", "broad_goal_only",
                     "goal points only to an annual goal; add quarter_goal:/kr:")

        # ---- structure (hub body vs its TYPE's template sections — derived) ----
        canon = template_sections.get(t)
        if canon and d.status in STRUCTURE_STATUS.get(t, set()):
            canon_set = set(canon)
            required = REQUIRED_SECTIONS.get(t, set())
            ignore = IGNORE_MISSING.get(t, set())
            nocode = FENCED_RE.sub("", d.body)  # ## inside ```base``` blocks aren't sections
            heads = [m.group(1).strip().lower()
                     for line in nocode.splitlines() if (m := H2_RE.match(line))]
            present = {h for h in heads if h in canon_set}
            extras = [h for h in heads if h not in canon_set]
            if not present and len(extras) >= 3:
                # a hub carrying its own non-template skeleton (PRD/onboarding doc
                # mistyped as this type). One flag, not ten — alarm-fatigue guard.
                flag(d, "structure.mistyped_hub", "mistyped_hub",
                     f"type: {t} but 0 of its template's sections; has {', '.join(extras[:4])} "
                     f"— likely a doc mistyped as a {t} hub")
            else:
                renamed_aliases: set[str] = set()
                for sec in canon:
                    if sec in present:
                        continue
                    # a renamed heading counts only if it isn't itself canonical here
                    alias_used = next((h for h in heads
                                       if SECTION_ALIASES.get(h) == sec and h not in canon_set), None)
                    if alias_used:
                        renamed_aliases.add(alias_used)
                        flag(d, "structure.section_renamed", "section_renamed",
                             f"'## {alias_used}' should be the canonical '## {sec}' "
                             "(patch-target heading; rename breaks skills that read it)")
                    elif sec in required:
                        flag(d, "structure.required_section_missing", "required_section_missing",
                             f"missing load-bearing section '## {sec}'")
                    elif sec in ignore:
                        continue  # illustrative prose section — absence isn't drift
                    else:
                        flag(d, "structure.optional_section_missing", "optional_section_missing",
                             f"missing section '## {sec}'")
                # additions are drift too: a ## heading the template doesn't define is
                # invisible to skills and rollups. Surface it so it gets promoted into
                # the template or folded into a canonical section. (Gap proven live
                # 2026-07-03: a '## Bug Queue' added to a hub passed silently.)
                seen_unknown: set[str] = set()
                for h in extras:
                    if h in renamed_aliases or h in seen_unknown:
                        continue
                    seen_unknown.add(h)
                    flag(d, "structure.unknown_section", "unknown_section",
                         f"'## {h}' is not in the {t} template — promote it to the "
                         "template or fold it into a canonical section")
                # canonical sections must keep template order — deterministic order is
                # what lets skills and rollups patch hubs mechanically
                first_pos: dict[str, int] = {}
                for idx, h in enumerate(heads):
                    if h in canon_set and h not in first_pos:
                        first_pos[h] = idx
                order_now = sorted(first_pos, key=lambda s: first_pos[s])
                order_tpl = [s for s in canon if s in first_pos]
                if order_now != order_tpl:
                    flag(d, "structure.section_order", "section_order",
                         f"sections out of template order: {' > '.join(order_now)}")

        # Established project roots always carry the six portable empty-capable
        # containers. Missing folders are structural gaps; missing notes are not.
        root = project_root(d)
        if root:
            for container in structure_contract["required_project_containers"]:
                if not (vault / root / container).is_dir():
                    flag(d, "structure.project_container_missing",
                         "project_container_missing",
                         f"established project is missing empty-capable container '{container}/'")

        # ---- connectivity ----
        if t == "project":
            goal = wiki_target(d.get("goal"))
            if goal and not resolves(goal):
                flag(d, "connectivity.goal_link_unresolved", "goal_link_unresolved",
                     f"goal '[[{goal}]]' does not resolve to a note")

        if t == "devlog":
            dl_date = str(d.get("date") or "").strip()
            # legacy amnesty (hardening-plan gate 5): devlog->task linking is
            # enforced forward from the amnesty date only. Undated devlogs stay
            # enforced — a missing date must not buy amnesty.
            if amnesty_date and dl_date and dl_date < amnesty_date:
                pass
            else:
                links = [wt for wt in (wiki_target(x) for x in as_list(d.get("tasks"))) if wt]
                if not links:
                    flag(d, "connectivity.devlog_no_task", "devlog_no_task",
                         "devlog links no task (the devlog->task->hub->goal chain breaks here)")
                else:
                    for link in links:
                        if link_key(link).lower() not in tasks_by_title:
                            flag(d, "connectivity.task_link_unresolved", "task_link_unresolved",
                                 f"tasks: link '[[{link}]]' does not resolve to a task note")

        if t == "task":
            proj = str(d.get("project") or "").strip()
            if proj and slugify(proj) not in projects_by_slug:
                flag(d, "connectivity.task_project_unresolved", "task_project_unresolved",
                     f"project '{proj}' has no matching project hub")

        # broken body wikilinks (skip fenced/inline code + doc placeholders)
        clean = INLINE_CODE_RE.sub("", FENCED_RE.sub("", d.body))
        for m in WIKI_RE.finditer(clean):
            target = m.group(1).split("|", 1)[0].split("#", 1)[0].strip()
            if not target or target.lower() in PLACEHOLDERS:
                continue
            if DATE_RE.match(Path(target).stem):
                continue  # daily-note links are often forward/intentional
            if not resolves(target):
                flag(d, "connectivity.broken_wikilink", "broken_wikilink",
                     f"body link '[[{target}]]' does not resolve")

        # ---- hygiene ----
        if d.line_count > 500:
            flag(d, "hygiene.oversized", "oversized",
                 f"{d.line_count} lines (>500; split with pipe-alias sub-pages)")
        if d.status == "superseded" and "[[" not in d.body:
            flag(d, "hygiene.superseded_no_pointer", "superseded_no_pointer",
                 "status: superseded but body has no pointer link to the replacement")
        seen: dict[str, int] = {}
        for line in d.body.splitlines():
            hm = HEADING_RE.match(line)
            if hm:
                key = hm.group(1).strip().lower()
                seen[key] = seen.get(key, 0) + 1
        dups = sorted(h for h, c in seen.items() if c > 1 and h in STRUCTURAL_HEADINGS)
        if dups:
            flag(d, "hygiene.duplicate_heading", "duplicate_heading",
                 f"repeated structural heading(s): {', '.join(dups)}")

    # ---- privacy cascade (second pass: needs project privacy map) ----
    private_slugs = {
        slug for slug, hub in projects_by_slug.items()
        if str(hub.get("private") or "").lower() == "true"
    }
    for d in docs:
        if d.type == "project":
            continue
        proj = slugify(str(d.get("project") or ""))
        if proj in private_slugs and str(d.get("private") or "").lower() != "true":
            flag(d, "privacy.unstamped_child", "unstamped_child",
                 f"project '{proj}' is private:true but this child is not stamped")

    for misplaced in scan_scope(vault)["misplaced_output_roots"]:
        issues.append({"file": misplaced, "doc_type": "artifact",
                       "check": "artifact_location.root_output", "severity": "smell",
                       "label": "misplaced_output",
                       "detail": "Working output at the vault root; resolve its owning project, preserve receipts and fix the producer before filing."})

    by_check: dict[str, int] = {}
    by_severity = {"violation": 0, "smell": 0}
    for it in issues:
        by_check[it["check"]] = by_check.get(it["check"], 0) + 1
        by_severity[it["severity"]] += 1

    issues.sort(key=lambda i: (i["severity"] != "violation", i["check"], i["file"]))
    return {
        "vault": str(vault),
        "scan_scope": scan_scope(vault),
        "shape_inventory": shape_inventory,
        "amnesty_date": amnesty_date or None,
        "totals": {
            "docs_scanned": len(docs),
            "issues": len(issues),
            "violations": by_severity["violation"],
            "smells": by_severity["smell"],
        },
        "by_severity": by_severity,
        "by_check": dict(sorted(by_check.items())),
        "contract_coverage": {
            "families": machine_contracts["families"],
            "effective_writer": machine_contracts["effective_writer"],
            "effective_audit": machine_contracts["effective_audit"],
            "implemented_writer": machine_contracts["implemented_writer"],
            "implemented_audit": machine_contracts["implemented_audit"],
            "template_contract": machine_contracts["template_contract"],
            "missing_files": machine_contracts["missing_files"],
            "warnings": machine_contracts["warnings"],
        },
        "structure_contract": {
            "source": structure_source,
            "schema_version": structure_contract.get("schema_version"),
            "required_project_containers": structure_contract["required_project_containers"],
            "warnings": structure_warnings,
        },
        "template_warnings": template_warnings,
        "contract": {
            "areas": sorted(valid_areas),
            "types": sorted(valid_types),
            "status_types": sorted(status_by_type),
            "warnings": contract.get("warnings", []),
        },
        "issues": issues,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# checks whose volume is high and priority is low — sampled in the report, not listed in full.
HIGH_VOLUME = {"connectivity.broken_wikilink", "hygiene.oversized"}


def health_status(totals: dict[str, int]) -> str:
    """Loud one-glance verdict. Violations = FAIL; smells only = degraded; clean."""
    if totals["violations"]:
        return "🔴 FAIL"
    if totals["smells"]:
        return "🟠 SMELLS"
    return "🟢 CLEAN"


def banner(result: dict[str, Any]) -> str:
    """The loud line. Printed to stderr on every run so a scheduled job can't hide
    a failing vault in silent output."""
    t = result["totals"]
    lines = [f"VAULT HEALTH: {health_status(t)} — {t['violations']} violations · "
             f"{t['smells']} smells · {t['docs_scanned']} notes scanned"]
    coverage = result.get("contract_coverage", {})
    candidates = sum(
        len(family.get("candidate", []))
        for family in coverage.get("families", {}).values()
    )
    missing = len(coverage.get("missing_files", []))
    lines.append(
        f"  Contract coverage: {candidates} candidate profiles (advisory, not enforced) · "
        f"{missing} missing contract files"
    )
    for w in result.get("template_warnings", []):
        lines.append(f"  ⚠ TEMPLATE MISSING (cannot grade structure): {w}")
    for w in result.get("contract", {}).get("warnings", []):
        lines.append(f"  ⚠ CONTRACT: {w}")
    for w in coverage.get("warnings", []):
        lines.append(f"  ⚠ CONTRACT: {w}")
    for w in result.get("structure_contract", {}).get("warnings", []):
        lines.append(f"  ⚠ STRUCTURE CONTRACT: {w}")
    return "\n".join(lines)


def render_report(result: dict[str, Any]) -> str:
    t = result["totals"]
    issues = result["issues"]

    def by_check(check: str) -> list[dict[str, str]]:
        return [i for i in issues if i["check"] == check]

    out = [
        f"# Vault Conformance Audit — {health_status(t)}",
        "",
        f"**{t['violations']}** violations · **{t['smells']}** smells · "
        f"scanned **{t['docs_scanned']}** notes.",
        "",
    ]
    coverage = result.get("contract_coverage", {})
    candidates = sum(
        len(family.get("candidate", []))
        for family in coverage.get("families", {}).values()
    )
    out += [
        f"> Contract coverage: **{candidates} candidate profiles** are advisory and "
        f"**{len(coverage.get('missing_files', []))} contract files** are missing.",
        "",
    ]
    for w in result.get("template_warnings", []):
        out += [f"> ⚠ **template missing** — {w}", ""]
    out += [
        "| check | count |",
        "|---|---|",
    ]
    for check, n in sorted(result["by_check"].items(), key=lambda kv: -kv[1]):
        out.append(f"| `{check}` | {n} |")

    # actionable tier: everything except the high-volume hygiene checks, grouped by check.
    out += ["", "## Actionable findings", ""]
    actionable = sorted(
        {i["check"] for i in issues} - HIGH_VOLUME,
        key=lambda c: (c not in VIOLATION_CHECKS, c),
    )
    for check in actionable:
        rows = by_check(check)
        tier = "violation" if check in VIOLATION_CHECKS else "smell"
        out.append(f"### `{check}` — {len(rows)} ({tier})")
        out.append("")
        for i in rows[:60]:
            out.append(f"- `{i['file']}` — {i['detail']}")
        if len(rows) > 60:
            out.append(f"- …and {len(rows) - 60} more")
        out.append("")

    # high-volume tier: count + top files only.
    out += ["## High-volume hygiene (sampled — backlog, not urgent)", ""]
    for check in sorted(HIGH_VOLUME):
        rows = by_check(check)
        if not rows:
            continue
        freq: dict[str, int] = {}
        for i in rows:
            freq[i["file"]] = freq.get(i["file"], 0) + 1
        top = sorted(freq.items(), key=lambda kv: -kv[1])[:10]
        out.append(f"### `{check}` — {len(rows)} across {len(freq)} files")
        out.append("")
        for f, n in top:
            out.append(f"- `{f}` ({n})")
        out.append("")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only vault conformance auditor")
    ap.add_argument("vault", nargs="?", default=None,
                    help="vault root (default: current directory, if it contains AGENTS.md)")
    ap.add_argument("--report", action="store_true", help="human-readable markdown instead of JSON")
    ap.add_argument("--no-fail", action="store_true",
                    help="always exit 0 (default: exit 1 when violations exist — fail loudly)")
    ap.add_argument("--amnesty-date", default=None, metavar="YYYY-MM-DD",
                    help="devlog->task checks enforced only for devlogs dated on/after this date "
                         "(default: parsed from AGENTS.md's legacy-amnesty line; pass '' to disable)")
    args = ap.parse_args()

    if args.vault:
        vault = Path(args.vault).expanduser()
    else:
        vault = Path.cwd()
        if not (vault / "AGENTS.md").is_file():
            print(f"no vault given and {vault} has no AGENTS.md — "
                  "pass the vault path explicitly", file=sys.stderr)
            return 2
    if not vault.is_dir():
        print(f"vault not found: {vault}", file=sys.stderr)
        return 2

    contract, errors, contract_warnings = load_agents_contract(vault)
    if contract is None:
        for e in errors:
            print(f"CONTRACT ERROR: {e}", file=sys.stderr)
        print("Fix AGENTS.md (or run the kit's /update-structure) and re-run.", file=sys.stderr)
        return 2
    contract["warnings"] = contract_warnings

    amnesty = args.amnesty_date if args.amnesty_date is not None else contract["amnesty_date"]
    if amnesty and not DATE_RE.match(amnesty):
        print(f"invalid --amnesty-date '{amnesty}' (want YYYY-MM-DD)", file=sys.stderr)
        return 2

    result = audit(vault, contract, amnesty_date=amnesty)
    if args.report:
        print(render_report(result))
    else:
        print(json.dumps(result, indent=2, sort_keys=True))
    # the loud line goes to stderr (keeps stdout clean JSON for the skill layer)
    print(banner(result), file=sys.stderr)
    if args.no_fail:
        return 0
    return 1 if result["totals"]["violations"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
