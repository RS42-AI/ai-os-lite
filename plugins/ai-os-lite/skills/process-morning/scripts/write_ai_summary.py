#!/usr/bin/env python3
"""Replace the Morning Brief's `### AI Summary` body and stamp completion."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from render_ai_summary import load_json, render


def replace_ai_summary(text: str, content: str) -> str:
    pattern = re.compile(
        r"(?P<head>^### AI Summary\s*$\n)(?P<body>.*?)(?=^#{1,6}\s+|\Z)",
        flags=re.M | re.S,
    )
    match = pattern.search(text)
    if not match:
        raise ValueError("### AI Summary heading not found")
    replacement = match.group("head") + content.rstrip() + "\n"
    return text[: match.start()] + replacement + text[match.end() :]


def upsert_frontmatter_bool(text: str, key: str, value: bool) -> str:
    """Set a boolean in the first YAML frontmatter block without touching the body."""
    frontmatter = re.compile(r"\A---\n(?P<body>.*?)\n---(?P<tail>\n|\Z)", flags=re.S)
    match = frontmatter.search(text)
    if not match:
        raise ValueError("YAML frontmatter not found")

    rendered = "true" if value else "false"
    body = match.group("body")
    field = re.compile(rf"^{re.escape(key)}\s*:\s*.*$", flags=re.M)
    if field.search(body):
        body = field.sub(f"{key}: {rendered}", body, count=1)
    else:
        body = f"{body}\n{key}: {rendered}"

    return text[: match.start("body")] + body + text[match.end("body") :]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("json", help="daily plan context JSON file")
    parser.add_argument("vault", help="vault root")
    args = parser.parse_args()

    context = load_json(args.json)
    journal_rel = context.get("files", {}).get("journal_path", "")
    if not journal_rel:
        raise SystemExit("context missing files.journal_path")

    path = Path(args.vault) / journal_rel
    text = path.read_text(encoding="utf-8")
    updated = replace_ai_summary(text, render(context))
    updated = upsert_frontmatter_bool(updated, "habit_morning_brief", True)
    path.write_text(updated, encoding="utf-8")
    print(journal_rel)


if __name__ == "__main__":
    main()
