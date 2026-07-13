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
  structure.{section_renamed,required_section_missing,optional_section_missing,
             mistyped_hub,platform_candidate,unknown_section,section_order}
  hygiene.{oversized,superseded_no_pointer,duplicate_heading}
  privacy.unstamped_child

Severity model (decision point 1 in the build task — tune the sets below):
  violation = a hard contract breach that makes data wrong/unparseable/unchained
  smell     = a confidence-lowering signal, not an error (per the orphan-note doctrine)

Closed enums are parsed from {vault}/AGENTS.md at runtime — see load_agents_contract.
"""

from __future__ import annotations

import argparse
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
                  ".claude", "setup-kit", "Vault-Setup-Artifact"}

# a project's own content subfolders. A project hub nested one level deeper than
# `2. Projects/{Area}/{Project}/` because its parent is one of THESE is normal (it's
# the hub sitting in its project folder); nested under anything else means a
# grouping/platform folder (e.g. Managed-AI/) sits between Area and Project.
CONTENT_SUBFOLDERS = {"Notes", "Tasks", "Dev Log", "Specs", "Resources", "Meetings"}

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
    "connectivity.devlog_no_task", "connectivity.task_link_unresolved",
    "connectivity.task_project_unresolved", "connectivity.goal_link_unresolved",
    "structure.section_renamed", "structure.mistyped_hub",
    "structure.required_section_missing",
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
    rows = rows_for("area folder", "slug")
    if rows is None:
        errors.append("AGENTS.md: areas table not found (need header '| Area folder | `area` slug |')")
    else:
        for r in rows:
            if len(r) >= 2:
                areas.update(ticked(r[1]))
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

    m = AMNESTY_RE.search(text)
    amnesty = m.group(1) if m else ""

    if errors:
        return None, errors, warnings
    return ({"types": types, "status_by_type": status_by_type, "areas": areas,
             "amnesty_date": amnesty}, [], warnings)


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


def load_docs(vault: Path) -> list[Doc]:
    docs: list[Doc] = []
    for path in sorted(vault.rglob("*.md"), key=lambda p: str(p).lower()):
        rel = str(path.relative_to(vault))
        if any(part in SKIP_DIR_PARTS for part in rel.split("/")):
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


def load_template_sections(vault: Path) -> tuple[dict[str, list[str]], list[str]]:
    """Derive each audited type's canonical `##` sections from its template.

    Returns (sections_by_type, warnings). A missing template is a loud warning: we
    cannot grade a type's structure without its source of truth, so we skip it and
    say so rather than silently passing.
    """
    sections: dict[str, list[str]] = {}
    warnings: list[str] = []
    tdir = vault / "system-settings" / "Templates"
    for typ, fname in TYPE_TEMPLATE.items():
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
    template_sections, template_warnings = load_template_sections(vault)
    issues: list[dict[str, str]] = []

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
    for d in docs:
        if d.type == "project":
            slug = slugify(str(d.get("project") or d.title))
            projects_by_slug.setdefault(slug, d)

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

        # ---- goal wiring (active project hubs only) ----
        if t == "project" and d.status == "active":
            goal = wiki_target(d.get("goal"))
            gstatus = str(d.get("goal_status") or "").strip()
            qgoal = wiki_target(d.get("quarter_goal"))
            kr = str(d.get("kr") or "").strip()
            if not goal and gstatus not in {"discovery", "unscored"}:
                flag(d, "goal_wiring.no_goal", "no_goal",
                     "active project hub has no goal: and no goal_status discovery|unscored")
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

        # ---- platform/container candidate (a project hub nested under a grouping
        # folder, e.g. Managed-AI/ — Area's taxonomy is 2-level, so this is an
        # ambiguity to settle, not a hard breach). Surfaces Copilot-Studio-shaped
        # cases as a class; excludes hubs nested merely under a content subfolder
        # (those are mistyped notes, caught by mistyped_hub). ----
        if t == "project" and "2. Projects" in d.parts:
            i = d.parts.index("2. Projects")
            extra = (len(d.parts) - 1) - (i + 3)  # folders beyond Area/Project/file
            parent = d.parts[-2] if len(d.parts) >= 2 else ""
            if extra >= 1 and parent not in CONTENT_SUBFOLDERS:
                group = d.parts[i + 2]
                flag(d, "structure.platform_candidate", "platform_candidate",
                     f"project hub nested under grouping folder '{group}/' — is this a "
                     "platform/program over sibling projects? settle its type/level")

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

    by_check: dict[str, int] = {}
    by_severity = {"violation": 0, "smell": 0}
    for it in issues:
        by_check[it["check"]] = by_check.get(it["check"], 0) + 1
        by_severity[it["severity"]] += 1

    issues.sort(key=lambda i: (i["severity"] != "violation", i["check"], i["file"]))
    return {
        "vault": str(vault),
        "amnesty_date": amnesty_date or None,
        "totals": {
            "docs_scanned": len(docs),
            "issues": len(issues),
            "violations": by_severity["violation"],
            "smells": by_severity["smell"],
        },
        "by_severity": by_severity,
        "by_check": dict(sorted(by_check.items())),
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
    for w in result.get("template_warnings", []):
        lines.append(f"  ⚠ TEMPLATE MISSING (cannot grade structure): {w}")
    for w in result.get("contract", {}).get("warnings", []):
        lines.append(f"  ⚠ CONTRACT: {w}")
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
