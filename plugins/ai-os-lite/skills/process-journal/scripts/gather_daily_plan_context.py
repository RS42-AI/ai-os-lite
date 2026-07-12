#!/usr/bin/env python3
"""Gather deterministic inputs for /process-journal v3 daily planning.

This script treats Obsidian frontmatter as the local API. It does not decide the
day's meaning; it returns queryable candidates for Focus, Review, Decide,
Dispatch, and Anchor so the model's judgment is constrained to ranking and
synthesis. `routing_exceptions` is always emitted empty here — deciding that a
transcript pointer needs a new canonical home is a judgment call the model
makes at Step 5/Step 7 time, not something this deterministic gatherer can
infer generically across installs.

Area ranking is NOT hardcoded. It is parsed at runtime from this vault's own
AGENTS.md areas table (`| Area folder | \\`area\\` slug |`, matched the same
way gather_morning_context.sh's area_rank()/gather_areas() match it: rows
whose folder cell mentions "Areas/" or "Personal/"). A missing or unparseable
table degrades every area to rank 99 rather than falling back to any one
install's fixed area list.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


DEFAULT_VAULT = Path.home() / "Claude" / "ObsidianVault"

AREA_RANKS: dict[str, int] = {}


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def parse_areas(vault: Path) -> list[dict[str, Any]]:
    """Ordered [{slug, display, rank}] from AGENTS.md's areas table.

    Missing/unparseable AGENTS.md -> []. Callers must treat an unknown area
    as rank 99 rather than reverting to a hardcoded area list.
    """
    text = read_text(vault / "AGENTS.md")
    if not text:
        return []
    areas: list[dict[str, Any]] = []
    rank = 1
    for line in text.splitlines():
        line = line.strip()
        if not (line.startswith("|") and line.endswith("|") and len(line) > 1):
            continue
        cells = [c.strip() for c in line[1:-1].split("|")]
        if len(cells) < 2:
            continue
        folder_cell, slug_cell = cells[0], cells[1]
        if "Areas/" not in folder_cell and "Personal/" not in folder_cell:
            continue
        slug_match = re.search(r"`([a-z][a-z0-9-]*)`", slug_cell)
        if not slug_match:
            continue
        slug = slug_match.group(1)
        folder_match = re.search(r"`([^`]+)`", folder_cell)
        folder = folder_match.group(1) if folder_match else re.sub(r"\(.*\)", "", folder_cell).strip()
        segment = folder.rstrip("/").split("/")[-1] if folder.rstrip("/") else ""
        display = re.sub(r"^\d+\.\s*", "", segment).strip() or slug
        areas.append({"slug": slug, "display": display, "rank": rank})
        rank += 1
    return areas


def area_rank(area: str) -> int:
    return AREA_RANKS.get(area or "", 99)


def parse_frontmatter(text: str) -> dict[str, Any]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    lines = text[4:end].splitlines()
    out: dict[str, Any] = {}
    current_key: str | None = None
    for line in lines:
        if not line.strip():
            continue
        if line.startswith("  - ") and current_key:
            out.setdefault(current_key, [])
            if not isinstance(out[current_key], list):
                out[current_key] = []
            out[current_key].append(clean_scalar(line[4:]))
            continue
        if ":" not in line:
            current_key = None
            continue
        key, raw = line.split(":", 1)
        key = key.strip()
        raw = raw.strip()
        current_key = key
        if raw == "":
            out[key] = []
        elif raw == "[]":
            out[key] = []
        elif raw.startswith("[") and raw.endswith("]"):
            items = [clean_scalar(v.strip()) for v in raw[1:-1].split(",") if v.strip()]
            out[key] = items
        elif raw.lower() in {"true", "false"}:
            out[key] = raw.lower() == "true"
        else:
            out[key] = clean_scalar(raw)
    return out


def clean_scalar(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def iter_markdown(vault: Path):
    for path in vault.rglob("*.md"):
        if "Templates" in path.parts:
            continue
        text = read_text(path)
        fm = parse_frontmatter(text)
        yield path, path.relative_to(vault).as_posix(), text, fm


def heading_section(text: str, heading: str) -> str:
    pattern = re.compile(
        rf"^(?P<marks>#+)\s+{re.escape(heading)}\s*$\n(?P<body>.*?)(?=^#{{1,6}}\s+|\Z)",
        re.S | re.M,
    )
    match = pattern.search(text)
    return match.group("body").strip() if match else ""


def morning_transcript(text: str) -> str:
    body = heading_section(text, "Morning")
    if "### AI Summary" in body:
        body = body.split("### AI Summary", 1)[0]
    return body.strip()


def stem(path: str) -> str:
    return Path(path).stem


def task_title(path: str) -> str:
    return stem(path)


def wikilink(path: str, alias: str | None = None) -> str:
    target = path[:-3] if path.endswith(".md") else path
    return f"[[{target}|{alias}]]" if alias else f"[[{target}]]"


def meeting_alias(title: str) -> str:
    title = re.sub(r"^\d{4}-\d{2}-\d{2}\s*-\s*", "", title or "")
    title = re.sub(r"\s*\([^)]*\)", "", title)
    title = re.sub(r"\s*-\s*Meeting Prep$", " prep", title)
    return re.sub(r"\s+", " ", title).strip() or "meeting prep"


def norm(value: Any) -> str:
    if isinstance(value, str):
        return value.lower()
    return ""


def as_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(v) for v in value]
    if value in ("", None):
        return []
    return [str(value)]


def scalar(value: Any) -> str:
    if isinstance(value, list):
        return str(value[0]) if value else ""
    if value is None:
        return ""
    return str(value)


def clean_blockers(value: Any) -> list[str]:
    blockers = []
    for raw in as_list(value):
        cleaned = str(raw).strip()
        if cleaned.lower() in {"", "[]", "none", "null", "n/a"}:
            continue
        blockers.append(cleaned)
    return blockers


def task_obj(rel: str, fm: dict[str, Any]) -> dict[str, Any]:
    tags = as_list(fm.get("tags"))
    blocked_by = clean_blockers(fm.get("blocked_by"))
    title = task_title(rel)
    return {
        "path": rel,
        "title": title,
        "link": wikilink(rel, title),
        "type": scalar(fm.get("type")),
        "status": scalar(fm.get("status")),
        "area": scalar(fm.get("area")),
        "project": scalar(fm.get("project")),
        "priority": scalar(fm.get("priority")),
        "due_date": scalar(fm.get("due_date")),
        "scheduled_date": scalar(fm.get("scheduled_date")),
        "tags": tags,
        "blocked_by": blocked_by,
        "is_dispatch_ready": "ai-handoff" in tags and not blocked_by,
        "is_decision_gated": "ai-pending-decision" in tags or bool(blocked_by),
    }


def meeting_obj(rel: str, fm: dict[str, Any], text: str) -> dict[str, Any]:
    tags = as_list(fm.get("tags"))
    title = stem(rel)
    return {
        "path": rel,
        "title": title,
        "link": wikilink(rel, meeting_alias(title)),
        "status": scalar(fm.get("status")),
        "area": scalar(fm.get("area")),
        "project": scalar(fm.get("project")),
        "start": scalar(fm.get("start")),
        "end": scalar(fm.get("end")),
        "tags": tags,
        "is_prep": "meeting-prep" in tags or "Meeting Prep" in title,
        "decisions_needed": extract_bullets(heading_section(text, "Decisions needed")),
    }


def extract_bullets(section: str) -> list[str]:
    bullets = []
    for line in section.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            bullets.append(stripped[2:].strip())
    return bullets


STOP_TERMS = {
    "agent",
    "agents",
    "build",
    "continue",
    "deliver",
    "items",
    "meeting",
    "project",
    "review",
    "skill",
    "task",
    "work",
}


def keyword_terms(task: dict[str, Any]) -> set[str]:
    values = [task.get("project", ""), task.get("title", "")]
    terms: set[str] = set()
    for value in values:
        for term in re.split(r"[^a-z0-9]+", norm(value)):
            if len(term) >= 5 and term not in STOP_TERMS:
                terms.add(term)
    return terms


def task_mentioned(text: str, task: dict[str, Any]) -> bool:
    haystack = norm(text).replace("-", " ")
    project = norm(task.get("project")).replace("-", " ")
    if project and project in haystack:
        return True
    return any(term in haystack for term in keyword_terms(task))


def dated_on_or_before(value: str, today: str) -> bool:
    return bool(value) and re.match(r"^\d{4}-\d{2}-\d{2}$", value) is not None and value <= today


def task_due_or_scheduled(task: dict[str, Any], today: str) -> bool:
    return dated_on_or_before(str(task.get("due_date") or ""), today) or dated_on_or_before(
        str(task.get("scheduled_date") or ""), today
    )


def focus_reason(task: dict[str, Any], today: str, transcript: str, start_day_text: str) -> str:
    if task.get("scheduled_date") == today or task.get("due_date") == today:
        return "scheduled for today"
    if task_mentioned(transcript, task):
        return "named in the morning transcript"
    if task_due_or_scheduled(task, today) and task.get("project") and task_mentioned(start_day_text, task):
        return "overdue and active in the morning cockpit"
    return ""


def decide_relevant(task: dict[str, Any], today: str, transcript: str) -> bool:
    if task_due_or_scheduled(task, today):
        return True
    if task_mentioned(transcript, task):
        return True
    return False


def classify_tasks(today: str, transcript: str, start_day_text: str, tasks: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    focus = []
    decide = []
    dispatch = []
    for task in tasks:
        status = task.get("status")
        if status not in {"todo", "active", "on-hold"}:
            continue
        if task.get("is_decision_gated"):
            if decide_relevant(task, today, transcript):
                decide.append({**task, "reason": "human choice needed before execution"})
        if task.get("is_dispatch_ready") and status in {"todo", "active"}:
            dispatch.append({**task, "reason": "AI-ready and unblocked"})
        if task.get("is_decision_gated") or task.get("is_dispatch_ready"):
            continue
        reason = focus_reason(task, today, transcript, start_day_text)
        if status in {"todo", "active"} and reason:
            focus.append({**task, "reason": reason})
    return {
        "focus": sorted(focus, key=lambda item: focus_sort(item, today, transcript, start_day_text))[:6],
        "decide": sorted(decide, key=priority_sort)[:6],
        "dispatch": sorted(dispatch, key=lambda item: dispatch_sort(item, transcript))[:8],
    }


def priority_sort(item: dict[str, Any]) -> tuple[int, int, str]:
    priority = str(item.get("priority") or "p9")
    try:
        rank = int(priority.lstrip("p"))
    except ValueError:
        rank = 9
    return area_rank(str(item.get("area") or "")), rank, item.get("title", "")


def focus_sort(item: dict[str, Any], today: str, transcript: str, start_day_text: str) -> tuple[int, int, int, int, str]:
    scheduled_today = item.get("scheduled_date") == today or item.get("due_date") == today
    explicit = task_mentioned(transcript, item)
    cockpit_project = bool(item.get("project")) and task_mentioned(start_day_text, item)
    if scheduled_today:
        reason_rank = 0
    elif explicit:
        reason_rank = 2
    elif cockpit_project:
        reason_rank = 3
    else:
        reason_rank = 4
    priority = str(item.get("priority") or "p9")
    try:
        priority_rank = int(priority.lstrip("p"))
    except ValueError:
        priority_rank = 9
    return (
        reason_rank,
        area_rank(str(item.get("area") or "")),
        priority_rank,
        0 if explicit else 1,
        ("" if cockpit_project else "z") + item.get("title", ""),
    )


def dispatch_sort(item: dict[str, Any], transcript: str) -> tuple[int, int, str]:
    relevance = 0
    if task_mentioned(transcript, item):
        relevance -= 3
    priority = str(item.get("priority") or "p9")
    try:
        priority_rank = int(priority.lstrip("p"))
    except ValueError:
        priority_rank = 9
    return (relevance, priority_rank, item.get("title", ""))


def anchor_signals(journal_fm: dict[str, Any], transcript: str) -> list[dict[str, str]]:
    signals = []
    unchecked = [
        key.replace("habit_", "").replace("_", " ")
        for key, value in sorted(journal_fm.items())
        if key.startswith("habit_") and value is False
    ]
    if unchecked:
        signals.append({
            "kind": "habit",
            "title": "Health reset",
            "text": "walk/workout + meditation or shutdown buffer",
            "context": ", ".join(unchecked),
        })
    lower = transcript.lower()
    if "anxious" in lower or "anxiety" in lower:
        signals.append({"kind": "mood", "title": "Anxiety check", "text": "lower friction and avoid opening unnecessary loops"})
    return signals[:6]


def source_warnings(start_day_text: str) -> list[str]:
    warnings = []
    for line in start_day_text.splitlines():
        if "Source warning" in line:
            warnings.append(re.sub(r"^>\s*-\s*\*\*Source warning\*\*:\s*", "", line).strip())
    return warnings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("date", help="target date YYYY-MM-DD")
    parser.add_argument("vault", nargs="?", default=str(DEFAULT_VAULT))
    args = parser.parse_args()
    vault = Path(args.vault)

    global AREA_RANKS
    areas = parse_areas(vault)
    AREA_RANKS = {a["slug"]: a["rank"] for a in areas}

    journal_rel = f"5. Resources/Personal/Journal/Morning Entries/{args.date}.md"
    daily_rel = f"1. Daily/{args.date}.md"
    journal_text = read_text(vault / journal_rel)
    daily_text = read_text(vault / daily_rel)
    journal_fm = parse_frontmatter(journal_text)
    transcript = morning_transcript(journal_text)
    start_day_sections = {
        "overall_read": heading_section(journal_text, "Overall Read"),
        "movement": heading_section(journal_text, "Movement From Yesterday +/- 1"),
        "control_queue": heading_section(journal_text, "Control Queue"),
        "threads_to_keep_visible": heading_section(journal_text, "Threads To Keep Visible"),
        "at_risk": heading_section(journal_text, "At Risk"),
    }
    start_day_text = "\n\n".join(v for v in start_day_sections.values() if v)

    tasks: list[dict[str, Any]] = []
    meetings: list[dict[str, Any]] = []
    for _path, rel, text, fm in iter_markdown(vault):
        if scalar(fm.get("type")) == "task":
            tasks.append(task_obj(rel, fm))
        elif scalar(fm.get("type")) == "meeting" and scalar(fm.get("date")) == args.date:
            meetings.append(meeting_obj(rel, fm, text))

    task_buckets = classify_tasks(args.date, transcript, start_day_text, tasks)
    review = []
    for meeting in sorted(meetings, key=lambda m: str(m.get("start") or "")):
        if meeting.get("is_prep") or meeting.get("status") in {"capture", "draft"}:
            review.append({**meeting, "reason": "meeting prep/capture needs reconciliation"})
    for warning in source_warnings(start_day_text):
        review.append({"title": "Source warning", "link": "", "text": warning, "reason": "source state is degraded"})

    decisions = list(task_buckets["decide"])
    for meeting in meetings:
        for decision in meeting.get("decisions_needed", []):
            decisions.append({
                "title": f"{meeting['title']} decision",
                "link": meeting["link"],
                "text": decision,
                "reason": "meeting prep decision needed",
            })

    context = {
        "date": args.date,
        "files": {
            "journal_path": journal_rel,
            "journal_exists": bool(journal_text),
            "daily_hub_path": daily_rel,
            "daily_hub_exists": bool(daily_text),
        },
        "journal": {
            "habits": {k: v for k, v in journal_fm.items() if k.startswith("habit_")},
            "morning_transcript": transcript,
            "start_day_sections": start_day_sections,
        },
        "meetings_today": meetings,
        "tasks": tasks,
        "candidates": {
            "focus": task_buckets["focus"],
            "review": review[:8],
            "decide": decisions[:8],
            "dispatch": task_buckets["dispatch"],
            "anchor": anchor_signals(journal_fm, transcript),
            # Always empty from the deterministic gatherer — flagging a
            # transcript pointer that needs a new canonical home is a Step
            # 5/Step 7 model judgment call, not something inferable
            # generically from frontmatter across installs.
            "routing_exceptions": [],
        },
        "source_manifest": {
            "journal": "success" if journal_text else "failed: missing journal",
            "daily_hub": "success" if daily_text else "failed: missing daily hub",
            "tasks": f"success: {len(tasks)} task note(s)",
            "meetings": f"success: {len(meetings)} meeting note(s)",
            "areas": (
                f"success: {len(areas)} area(s) parsed from AGENTS.md"
                if areas
                else "degraded: no areas table found in AGENTS.md — area ordering falls back to unranked (99)"
            ),
        },
    }
    print(json.dumps(context, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
