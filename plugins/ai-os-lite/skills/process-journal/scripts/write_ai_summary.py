#!/usr/bin/env python3
"""Replace the morning journal's `### AI Summary` body from a v3 context JSON."""

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
    path.write_text(updated, encoding="utf-8")
    print(journal_rel)


if __name__ == "__main__":
    main()
