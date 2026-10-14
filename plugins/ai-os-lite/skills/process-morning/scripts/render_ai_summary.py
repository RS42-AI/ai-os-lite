#!/usr/bin/env python3
"""Render the private Morning Brief `### AI Summary` body.

Kept deliberately generic: the paragraph shape (work signal, then an optional
emotional/gratitude/routing follow-up) is deterministic, but the wording never
names a specific project, company, or transcript phrase — those signals come
from the gathered candidates, not from pattern-matching one person's session.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: str | None) -> dict[str, Any]:
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    import sys

    return json.load(sys.stdin)


def has_text(transcript: str, *needles: str) -> bool:
    lower = transcript.lower()
    return any(needle in lower for needle in needles)


def list_phrase(values: list[str]) -> str:
    values = [value for value in values if value]
    if not values:
        return ""
    if len(values) == 1:
        return values[0]
    if len(values) == 2:
        return f"{values[0]} and {values[1]}"
    return f"{', '.join(values[:-1])}, and {values[-1]}"


def clean_route(text: str) -> str:
    text = text.strip().rstrip(".")
    for prefix in ("Route ", "Capture ", "Convert "):
        if text.startswith(prefix):
            text = text[len(prefix) :]
            break
    return text


def render(context: dict[str, Any]) -> str:
    transcript = context.get("journal", {}).get("morning_transcript", "")
    candidates = context.get("candidates", {})
    focus = candidates.get("focus", [])
    dispatch = candidates.get("dispatch", [])
    routing = candidates.get("routing_exceptions", [])

    focus_titles = [item.get("title", "") for item in focus[:3]]
    focus_phrase = list_phrase(focus_titles)

    first = "The morning entry turns into today's reconciliation and planning layer."
    if focus_phrase:
        first += f" The strongest work signal is {focus_phrase}."
    elif dispatch:
        first += " No clear Focus candidate emerged; the strongest signal is AI-ready work waiting in Dispatch."
    else:
        first += " No strong work signal was extracted from today's transcript."

    second_parts = []
    if has_text(transcript, "anxious", "anxiety", "overwhelmed", "stressed"):
        second_parts.append(
            "The emotional signal matters: today's plan should favor fewer, clearer commitments over opening new loops"
        )
    if has_text(transcript, "thankful", "grateful"):
        second_parts.append("Gratitude is present and should support a steadier day rather than become another planning loop")
    if routing:
        routed = [clean_route(item.get("text", "")) for item in routing[:4]]
        second_parts.append(f"New pointers to route: {list_phrase(routed)}")

    second = ". ".join(second_parts).strip()
    if second and not second.endswith("."):
        second += "."

    paragraphs = [first]
    if second:
        paragraphs.append(second)
    return "\n\n".join(paragraphs).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("json", nargs="?", help="daily plan context JSON file; stdin when omitted")
    args = parser.parse_args()
    print(render(load_json(args.json)), end="")


if __name__ == "__main__":
    main()
