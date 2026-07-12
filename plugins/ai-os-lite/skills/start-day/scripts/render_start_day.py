#!/usr/bin/env python3
"""Render the /start-day cockpit from gather_morning_context.sh JSON.

The gather script owns local data discovery. This renderer owns stable Markdown
shape. The model may rewrite a few synthesis sentences afterward, but the
section contract and candidate lists should come from this deterministic layer.

Area order and area-hub wikilink targets are NOT hardcoded here — they come
from `data["areas"]`, which the gather script derives at runtime from the
instance's own AGENTS.md areas table (`| Area folder | \\`area\\` slug |`,
matched by header signature, in table row order). A missing or unparseable
table degrades to an empty `areas` list; every area then falls back to rank 99
and a generic per-slug display name instead of crashing or reverting to any
one install's fixed area set.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


def load_json(path: str | None) -> dict[str, Any]:
    if path:
        return json.loads(Path(path).read_text())
    import sys

    return json.load(sys.stdin)


def md_date(date_str: str) -> str:
    try:
        _, month, day = date_str.split("-")
        return f"{int(month)}/{int(day)}"
    except Exception:
        return date_str


def stem_from_path(path: str) -> str:
    return Path(path).stem


def normalize_slug(slug: str | None) -> str:
    if not slug:
        return ""
    slug = re.sub(r"^\[\[|\]\]$", "", slug)
    if "|" in slug:
        slug = slug.rsplit("|", 1)[1]
    return slug.strip()


def display_name(value: str | None) -> str:
    """Generic Title Case fallback for a slug — no per-project alias table.

    Used only when a canonical hub/area display name isn't available; the
    project hub wikilink (Class C) and area display (from `data["areas"]`)
    both take priority over this when known.
    """
    value = normalize_slug(value)
    if not value:
        return ""
    return value.replace("-", " ").title()


def wikilink_path(path: str, alias: str | None = None) -> str:
    target = path[:-3] if path.endswith(".md") else path
    if alias:
        return f"[[{target}|{alias}]]"
    return f"[[{target}]]"


# ── Area order/display/rank — derived from gather output, never hardcoded ──


def build_area_maps(data: dict[str, Any]) -> tuple[list[str], dict[str, str], dict[str, int]]:
    order: list[str] = []
    display: dict[str, str] = {}
    ranks: dict[str, int] = {}
    for entry in data.get("areas", []):
        slug = normalize_slug(entry.get("slug") or "")
        if not slug:
            continue
        order.append(slug)
        display[slug] = entry.get("display") or display_name(slug)
        try:
            ranks[slug] = int(entry.get("rank", 99))
        except (TypeError, ValueError):
            ranks[slug] = 99
    return order, display, ranks


def area_rank(area: str | None, ranks: dict[str, int]) -> int:
    return ranks.get(area or "", 99)


def area_display(area: str | None, display_map: dict[str, str]) -> str:
    if not area:
        return "Unfiled"
    return display_map.get(area) or display_name(area) or "Unfiled"


def area_link(area: str | None, display_map: dict[str, str]) -> str:
    return f"[[{area_display(area, display_map)}]]"


def project_maps(data: dict[str, Any]) -> tuple[dict[str, str], dict[str, str]]:
    path_by_slug: dict[str, str] = {}
    area_by_slug: dict[str, str] = {}
    for project in data.get("active_projects", []):
        slug = normalize_slug(project.get("slug") or "")
        if not slug:
            continue
        path_by_slug[slug] = project.get("hub_path") or ""
        area_by_slug[slug] = project.get("area") or ""
    return path_by_slug, area_by_slug


def project_link(slug: str | None, path_by_slug: dict[str, str]) -> str:
    """Class C: wikilink comes from `hub_path`, never synthesized.

    If no active_projects[] row exists for the slug, fall back to a plain
    (non-wikilink) display label rather than guessing at a file that may not
    exist.
    """
    slug = normalize_slug(slug)
    if not slug:
        return ""
    path = path_by_slug.get(slug, "")
    if path:
        return wikilink_path(path, stem_from_path(path))
    return display_name(slug)


def compact_sentence(text: str, max_chars: int = 190) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    if not text:
        return ""
    sentence_match = re.match(r"(.+?[.!?])(?:\s|$)", text)
    sentence = sentence_match.group(1) if sentence_match else text
    if len(sentence) <= max_chars:
        return sentence
    return sentence[: max_chars - 1].rstrip() + "."


def all_recap_items(data: dict[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for day in data.get("recap_window", {}).get("days", []):
        date = day.get("date", "")
        for devlog in day.get("devlogs", []):
            items.append({"kind": "devlog", "date": date, **devlog})
        for note in day.get("notes", []):
            items.append({"kind": "note", "date": date, **note})
    return items


def area_projects(data: dict[str, Any], area: str) -> set[str]:
    projects = set()
    for item in all_recap_items(data):
        if item.get("area") == area and item.get("project"):
            projects.add(normalize_slug(item.get("project")).lower())
    return projects


def list_sentence(values: list[str]) -> str:
    values = [v for v in values if v]
    if not values:
        return ""
    if len(values) == 1:
        return values[0]
    if len(values) == 2:
        return f"{values[0]} and {values[1]}"
    return f"{', '.join(values[:-1])}, and {values[-1]}"


def synthesize_recent_trend(data: dict[str, Any], display_map: dict[str, str], ranks: dict[str, int]) -> str:
    recap = data.get("recap_window", {})
    if recap.get("beyond_lookback"):
        return f"No captured work in the local window {md_date(recap.get('from', ''))} -> {md_date(recap.get('to', ''))}."

    areas_present = sorted(
        {item.get("area") for item in all_recap_items(data) if item.get("area")},
        key=lambda a: (area_rank(a, ranks), a),
    )
    if areas_present:
        names = list_sentence([area_display(a, display_map) for a in areas_present[:3]])
        return f"{names} had fresh movement; choose one work anchor and use the rest as context."
    return "No captured work in the local window."


def meeting_alias(meeting: dict[str, Any]) -> str:
    title = meeting.get("title") or stem_from_path(meeting.get("path", ""))
    title = re.sub(r"^\d{4}-\d{2}-\d{2}\s*-\s*", "", title)
    title = re.sub(r"\s*\([^)]*\)", "", title)
    title = re.sub(r"\s*-\s*Meeting Prep$", " prep", title)
    return re.sub(r"\s+", " ", title).strip() or stem_from_path(meeting.get("path", ""))


def synthesize_key_insight(data: dict[str, Any]) -> str:
    prep = [m for m in data.get("meetings_today", {}).get("meetings", []) if m.get("is_prep")]
    if prep:
        name = meeting_alias(prep[0]).removesuffix(" prep")
        return f"Use the {name} to choose one concrete work anchor before opening new system work."
    return "Use the movement and queue evidence to choose one work anchor before opening new system work."


def extract_evening_insight(evening: dict[str, Any]) -> str:
    content = evening.get("content") or ""
    if not content:
        return ""
    wind_down = re.search(
        r"### Wind Down\s+(.*?)(?:\n---|\n## |\n### |\Z)",
        content,
        flags=re.S,
    )
    if wind_down:
        return compact_sentence(wind_down.group(1), 220)
    for line in content.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("---") and not stripped.startswith("#") and ":" not in stripped[:25]:
            return compact_sentence(stripped, 220)
    return ""


def render_meeting_prep(data: dict[str, Any]) -> str:
    meetings = data.get("meetings_today", {}).get("meetings", [])
    prep = [m for m in meetings if m.get("is_prep")]
    if not prep:
        if meetings:
            return "No prep notes found for today's meeting note(s)."
        return "No meeting notes found for today."
    parts = []
    for meeting in prep[:4]:
        link = wikilink_path(meeting.get("path", ""), meeting_alias(meeting))
        start = meeting.get("start", "")
        end = meeting.get("end", "")
        time = ""
        if "T" in start:
            time = start.split("T", 1)[1][:5]
            if "T" in end:
                time += f"-{end.split('T', 1)[1][:5]}"
        parts.append(f"{link}{f' ({time})' if time else ''} - ready; no prep gap")
    return "; ".join(parts)


def source_warnings(data: dict[str, Any]) -> list[str]:
    manifest = data.get("source_manifest", {})
    warnings = []
    for key, value in manifest.items():
        if isinstance(value, str) and value.startswith(("failed", "partial", "degraded")):
            if key == "todoist":
                warnings.append("Todoist failed")
            elif key == "workitems":
                warnings.append("Work-item integration failed")
            elif key == "areas":
                warnings.append("AGENTS.md areas table not found — area ordering/links are unranked")
            else:
                warnings.append(f"{display_name(key)} {value.split(':', 1)[0]}")
        elif key == "calendar" and isinstance(value, str) and "not implemented" in value:
            warnings.append("calendar integration is not wired into this cockpit yet")
    return warnings


def render_overall_read(data: dict[str, Any], display_map: dict[str, str], ranks: dict[str, int]) -> list[str]:
    lines = ["### Overall Read"]
    evening = data.get("evening", {})
    if evening.get("found"):
        path = evening.get("path") or ""
        link = wikilink_path(path, "Last Night's Evening") if path else "Last Night's Evening"
        lines.append(f"> **Previous Evening**: {link}")
    else:
        lines.append("> **Previous Evening**: NO EVENING ENTRY")

    lines.append(f"> **Recent trend**: {synthesize_recent_trend(data, display_map, ranks)}")
    lines.append(f"> - **Key insight for today**: {synthesize_key_insight(data)}")

    lines.append(f"> - **Meeting Prep**: {render_meeting_prep(data)}")
    warnings = source_warnings(data)
    if warnings:
        lines.append(f"> - **Source warning**: {'; '.join(warnings)}")
    return lines


def movement_entries(
    data: dict[str, Any], path_by_slug: dict[str, str], display_map: dict[str, str], ranks: dict[str, int]
) -> dict[str, list[str]]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for day in data.get("recap_window", {}).get("days", []):
        date = day.get("date", "")
        for devlog in day.get("devlogs", []):
            key = (devlog.get("area") or "", devlog.get("project") or "")
            grouped[key].append({"kind": "devlog", "date": date, **devlog})
        for note in day.get("notes", []):
            key = (note.get("area") or "", note.get("project") or "")
            grouped[key].append({"kind": "note", "date": date, **note})

    buckets: dict[str, list[str]] = defaultdict(list)
    for (area, project), items in sorted(grouped.items(), key=lambda kv: (area_rank(kv[0][0], ranks), kv[0][1])):
        buckets[area].append(render_movement_group(area, project, items, path_by_slug, display_map))
    return buckets


def render_movement_group(
    area: str | None,
    project: str | None,
    items: list[dict[str, Any]],
    path_by_slug: dict[str, str],
    display_map: dict[str, str],
) -> str:
    project = normalize_slug(project).lower()
    summary = compact_sentence(items[0].get("session_topic") or items[0].get("title") or "", 150)

    parent = project_link(project, path_by_slug) if project else "area-level"
    label = f"{area_link(area, display_map)} / {parent}" if project else f"{area_link(area, display_map)} area-level"
    line = f"- **{label}** - {summary}"
    evidence = []
    for item in sorted(items, key=lambda i: (i.get("date", ""), i.get("kind", ""), i.get("path", "")))[:2]:
        title = item.get("title") or stem_from_path(item.get("path", ""))
        evidence.append(f"\t- {wikilink_path(item.get('path', ''), title)}")
    return "\n".join([line] + evidence)


def task_title(task: dict[str, Any]) -> str:
    return stem_from_path(task.get("path", ""))


def task_link(task: dict[str, Any]) -> str:
    return wikilink_path(task.get("path", ""), task_title(task))


def priority_key(task: dict[str, Any]) -> tuple[int, str]:
    priority = task.get("priority") or "p9"
    try:
        n = int(priority.lstrip("p"))
    except ValueError:
        n = 9
    return (n, task.get("path", ""))


def task_blocked(task: dict[str, Any]) -> bool:
    blocked = task.get("blocked_by")
    if blocked in (None, "", [], "[]"):
        return False
    if isinstance(blocked, list) and all(str(v).strip().lower() in {"", "none", "[]", "null"} for v in blocked):
        return False
    if isinstance(blocked, str) and blocked.strip().lower() in {"none", "null"}:
        return False
    return True


def render_control_queue(data: dict[str, Any]) -> list[str]:
    tasks = data.get("task_notes", {}).get("tasks", [])
    meetings = data.get("meetings_today", {}).get("meetings", [])
    active = [t for t in tasks if t.get("status") == "active"]
    decisions = [t for t in tasks if "ai-pending-decision" in (t.get("tags") or []) or task_blocked(t)]
    dispatches = [
        t
        for t in tasks
        if "ai-handoff" in (t.get("tags") or [])
        and t.get("status") in ("todo", "active")
        and not task_blocked(t)
    ]

    lines = ["### Control Queue", "#### Review"]
    prep_meetings = [m for m in meetings if m.get("is_prep")]
    for meeting in prep_meetings[:3]:
        link = wikilink_path(meeting.get("path", ""), meeting_alias(meeting))
        lines.append(f"- {link} - review before the meeting and reconcile afterward with captured notes.")
    for task in sorted([t for t in active if t.get("priority") in ("p1", "p2")], key=priority_key)[:3]:
        lines.append(f"- {task_link(task)} - review current state before more work moves.")
    if len(lines) == 2:
        lines.append("- No meeting prep or high-priority active task notes found for review.")

    lines.append("")
    lines.append("#### Decide")
    for task in sorted(decisions, key=priority_key)[:5]:
        lines.append(f"- {task_link(task)} - decision-gated; record the human choice before execution.")
    if not decisions:
        lines.append("- No decision-gated task notes found.")

    lines.append("")
    lines.append("#### Dispatch")
    for task in sorted(dispatches, key=priority_key)[:5]:
        lines.append(f"- {task_link(task)} - AI-ready candidate; choose dispatch, defer, or close.")
    if not dispatches:
        lines.append("- No unblocked `ai-handoff` task notes found.")
    return lines


def render_threads(data: dict[str, Any], path_by_slug: dict[str, str], display_map: dict[str, str]) -> list[str]:
    tasks = data.get("task_notes", {}).get("tasks", [])
    thread_tasks = [
        t
        for t in tasks
        if (
            "ai-handoff" in (t.get("tags") or [])
            or "ai-pending-decision" in (t.get("tags") or [])
            or t.get("status") == "active"
        )
    ]
    lines = ["### Threads To Keep Visible"]
    if thread_tasks:
        for task in sorted(thread_tasks, key=priority_key)[:6]:
            area = task.get("area")
            project = task.get("project")
            lines.append(
                f"- **{area_link(area, display_map)} / {project_link(project, path_by_slug)} / {task_link(task)}** - keep visible until reviewed, dispatched, or closed."
            )
    else:
        lines.append("- No recurring control threads found.")
    return lines


def render_at_risk(data: dict[str, Any]) -> list[str]:
    lines = ["#### At Risk"]
    warnings = source_warnings(data)
    if warnings:
        lines.append(f"- **Source gaps** - {'; '.join(warnings)}; treat the queue as candidate state until restored.")
    if len(lines) == 1:
        lines.append("- No source or meeting-capture exceptions found in this run.")
    return lines


def render(data: dict[str, Any]) -> str:
    path_by_slug, _ = project_maps(data)
    _, display_map, ranks = build_area_maps(data)
    lines: list[str] = []
    lines.extend(render_overall_read(data, display_map, ranks))
    lines.append("")
    lines.append("### Movement From Yesterday +/- 1")
    buckets = movement_entries(data, path_by_slug, display_map, ranks)
    ordered_areas = sorted(buckets.keys(), key=lambda a: (area_rank(a, ranks), a))
    for area in ordered_areas:
        entries = buckets.get(area, [])
        if not entries:
            continue
        lines.append(f"##### {area_display(area, display_map)}")
        lines.extend(entries)
    if not any(buckets.values()):
        lines.append("- No captured work in the local window.")
    lines.append("")
    lines.append("---")
    lines.extend(render_control_queue(data))
    lines.append("")
    lines.extend(render_threads(data, path_by_slug, display_map))
    lines.append("")
    lines.extend(render_at_risk(data))
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("json", nargs="?", help="gather_morning_context JSON file; stdin when omitted")
    args = parser.parse_args()
    print(render(load_json(args.json)), end="")


if __name__ == "__main__":
    main()
