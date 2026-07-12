#!/usr/bin/env python3
"""Render the /process-journal v3 daily hub block from gathered context."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


def load_json(path: str | None) -> dict[str, Any]:
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    import sys

    return json.load(sys.stdin)


def clean_meeting_title(title: str) -> str:
    title = re.sub(r"^\d{4}-\d{2}-\d{2}\s*-\s*", "", title or "")
    title = re.sub(r"\s*\([^)]*\)", "", title)
    title = re.sub(r"\s*-\s*Meeting Prep$", " prep", title)
    return re.sub(r"\s+", " ", title).strip() or "meeting prep"


def label(item: dict[str, Any]) -> str:
    link = item.get("link")
    title = item.get("title") or item.get("text") or "Untitled"
    if link:
        return link
    return f"**{title}**"


def item_label(item: dict[str, Any]) -> str:
    base = label(item)
    text = item.get("text")
    if text and text != item.get("title"):
        return f"{base} - {text}"
    return base


def focus_action(item: dict[str, Any]) -> str:
    return "move the work visibly or leave the next action clearly queued"


def review_action(item: dict[str, Any]) -> str:
    if item.get("title") == "Source warning":
        return "treat the queue as candidate state until the source gap is restored or acknowledged"
    if item.get("link"):
        return "compare prep vs actual discussion and extract only actionable follow-ups"
    return item.get("text") or "review the evidence before acting"


def decide_action(item: dict[str, Any]) -> str:
    if item.get("source") == "transcript":
        return item.get("text") or "record the human choice before execution"
    if item.get("text") and not item.get("path"):
        return item["text"]
    return "record the human choice, blocker resolution, or fork before execution"


def dispatch_action(item: dict[str, Any]) -> str:
    return "stage the work for human review without consuming the main focus block"


def anchor_action(item: dict[str, Any]) -> str:
    title = item.get("title")
    text = item.get("text") or "body/mind reset"
    if title:
        return f"**{title}** - {text}"
    return f"**Anchor** - {text}"


def sentence(text: str) -> str:
    text = text.rstrip()
    return text if text.endswith((".", "!", "?")) else f"{text}."


def format_lane_item(name: str, item: dict[str, Any]) -> str:
    if name == "Focus":
        return f"- {label(item)} - {sentence(focus_action(item))}"
    if name == "Review":
        return f"- {label(item)} - {sentence(review_action(item))}"
    if name == "Decide":
        return f"- {label(item)} - {sentence(decide_action(item))}"
    if name == "Dispatch":
        return f"- {label(item)} - {sentence(dispatch_action(item))}"
    if name == "Anchor":
        return f"- {sentence(anchor_action(item))}"
    return f"- {item_label(item)}"


def first_link(items: list[dict[str, Any]], fallback: str) -> str:
    for item in items:
        if item.get("link"):
            return item["link"]
    return fallback


def first_target(items: list[dict[str, Any]], fallback: str) -> str:
    for item in items:
        if item.get("link"):
            return item["link"]
        if item.get("title"):
            return f"**{item['title']}**"
        if item.get("text"):
            return item["text"]
    return fallback


def focus_links(focus: list[dict[str, Any]]) -> list[str]:
    seen = set()
    links = []
    for item in focus:
        key = item.get("project") or item.get("title")
        if key in seen:
            continue
        seen.add(key)
        links.append(item.get("link") or item.get("title") or "Focus candidate")
    return links


def list_phrase(values: list[str]) -> str:
    values = [value for value in values if value]
    if not values:
        return ""
    if len(values) == 1:
        return values[0]
    if len(values) == 2:
        return f"{values[0]} and {values[1]}"
    return f"{', '.join(values[:-1])}, and {values[-1]}"


def choose_work_anchor(context: dict[str, Any]) -> tuple[str, str]:
    focus = context.get("candidates", {}).get("focus", [])
    meetings = context.get("meetings_today", [])
    if focus:
        item = focus[0]
        title = item.get("title") or "Today work"
        area = item.get("area")
        project = item.get("project")
        if area and project:
            main = f"{area.title()} / {project} - {title}"
        else:
            main = title
        start = (
            f"Start with {item.get('link') or title}. "
            "The day is successful if this work visibly moves or the next action is clearly queued in its canonical task/project note."
        )
        return main, start
    if meetings:
        item = meetings[0]
        title = item.get("title") or "today's meeting"
        return title, f"Start by reconciling {item.get('link') or title} into concrete follow-ups."
    return "No single work anchor detected", "Start by choosing one Focus candidate before opening new system work."


def render_queue(context: dict[str, Any]) -> list[str]:
    candidates = context.get("candidates", {})
    sections = [
        ("Focus", "human execution that moves the day forward", candidates.get("focus", []), "No Focus candidate found."),
        ("Review", "daily evidence check before acting", candidates.get("review", []), "No Review candidate found."),
        ("Decide", "human judgment bottleneck / fork", candidates.get("decide", []), "No Decide candidate found."),
        ("Dispatch", "AI-ready work that can move in parallel", candidates.get("dispatch", []), "No Dispatch candidate found."),
        ("Anchor", "health/life/sustainability guardrail", candidates.get("anchor", []), "No Anchor signal found."),
    ]
    limits = {"Focus": 3, "Review": 3, "Decide": 4, "Dispatch": 4, "Anchor": 2}
    lines = ["### Control Queue"]
    for name, subtitle, items, empty in sections:
        lines.append("")
        lines.append(f"**{name}** *({subtitle})*")
        if items:
            for item in items[: limits[name]]:
                lines.append(format_lane_item(name, item))
        else:
            lines.append(f"- {empty}")
    return lines


def render_plan(context: dict[str, Any]) -> list[str]:
    candidates = context.get("candidates", {})
    focus = candidates.get("focus", [])
    review = candidates.get("review", [])
    decide = candidates.get("decide", [])
    dispatch = candidates.get("dispatch", [])
    anchor = candidates.get("anchor", [])

    focus_1 = first_link(focus[:1], "top Focus candidate")
    focus_2 = first_link(focus[1:2], focus_1)
    review_1 = first_link(review[:1], "top Review candidate")
    decide_1 = first_target(decide[:1], "top Decide candidate")
    dispatch_1 = list_phrase([first_link(dispatch[:1], "top Dispatch candidate"), first_link(dispatch[1:2], "")])
    anchor_1 = anchor[0].get("text") if anchor else "body/mind reset"

    lines = [
        "### Today's Plan",
        "",
        "> Working assumption: a normal workday has about 5.5-6.5 usable focus hours after meetings, context switching, admin, food, and buffer. Since live calendar writes are not wired into this branch yet, this is a timeboxed sequence, not committed calendar events.",
        "",
        f"1. **Review - first pass** *(30 min)* -> {review_1}; choose the concrete work target.",
        f"2. **Focus - execution block 1** *(90 min)* -> {focus_1}.",
        "3. **Buffer / admin** *(30 min)* -> messages, transition, and quick capture of what changed.",
        f"4. **Focus - execution block 2** *(60-90 min)* -> {focus_2}; update the canonical project/task note.",
        f"5. **Decide - resolve today's fork** *(25 min)* -> {decide_1}.",
        f"6. **Dispatch - launch AI-ready work** *(20 min launch)* -> {dispatch_1}.",
        "7. **Optional backlog only if work anchor moved** *(20 min)* -> pick up secondary work only after the anchor advances.",
        f"8. **Anchor - body/mind reset** *(30 min)* -> {anchor_1}.",
        "",
        "**Re-plan trigger:** if the work anchor expands or a meeting creates urgent follow-up, keep Review + Focus + Decide and defer Dispatch. The system exists to support the work, not consume the workday.",
    ]
    return lines


def render_routing_exceptions(context: dict[str, Any]) -> list[str]:
    exceptions = context.get("candidates", {}).get("routing_exceptions", [])
    if not exceptions:
        return []
    lines = ["### Routing Exceptions", ""]
    for item in exceptions[:6]:
        lines.append(f"- {item.get('text')}")
    return lines


def render(context: dict[str, Any]) -> str:
    journal_path = context.get("files", {}).get("journal_path", "")
    journal_link = f"> [[{journal_path[:-3]}|Open Morning Entry]]" if journal_path.endswith(".md") else "> [[Open Morning Entry]]"
    anchor_title, anchor_start = choose_work_anchor(context)

    lines = [
        journal_link,
        "",
        "### Work Anchor",
        "",
        f"**Main work today:** {anchor_title}.",
        "",
        f"**Start here:** {anchor_start}",
        "",
    ]
    lines.extend(render_queue(context))
    lines.append("")
    lines.extend(render_plan(context))
    routing = render_routing_exceptions(context)
    if routing:
        lines.append("")
        lines.extend(routing)
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("json", nargs="?", help="daily plan context JSON file; stdin when omitted")
    args = parser.parse_args()
    print(render(load_json(args.json)), end="")


if __name__ == "__main__":
    main()
