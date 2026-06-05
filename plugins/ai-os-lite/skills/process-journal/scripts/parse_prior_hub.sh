#!/usr/bin/env bash
# Parse yesterday's daily hub. Emit JSON of priority bullets per lane.
# Usage: parse_prior_hub.sh YYYY-MM-DD   (the YESTERDAY date, not today)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

yesterday="$1"
hub_path="$(obs_path "1. Daily/$yesterday.md")"

if [[ ! -f "$hub_path" ]]; then
  echo "[]"
  exit 0
fi

# Extract the Morning Journal section's priority block. The block starts at
# `**Today's priorities` and runs until the next `---` separator.
python3 - "$hub_path" <<'PY'
import sys, re, json, os

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()

# Find the priorities block. Hub formats vary:
#   5/15: **Today's priorities:**          (colon inside bold)
#   5/16: **Today's priorities** *(...)    (parenthetical suffix)
#   5/18: **Today's priorities** *(...)    (parenthetical suffix)
# Use a pattern that matches all forms, stopping at the next --- separator.
m = re.search(r"\*\*Today.s priorities[^*]*\*?\*?.*?(?=^---$)", text, re.S | re.M)
if not m:
    print("[]"); sys.exit(0)
block = m.group(0)

# Lane headers: **Must do** / **Focus work** / **If time** / **Could hand off to AI**
# / **Also on the radar** / **Research questions** / **Blockers ...** / **Execution strategy**
# Plus the legacy **Yesterday's open items**.
# Lane names may contain emoji (e.g. "robot Could hand off to AI") -- [^*]+? handles Unicode fine.
# Some legacy hubs put the colon inside the bold: **Focus work:**  -- we strip trailing : below.
LANE_RE = re.compile(
    r"^\*\*(?P<lane>[^*]+?)\*\*[^:\n]*:?\s*(?:\*\([^)]*\)\*)?\s*\n",
    re.M,
)
# Split block by lane markers
lanes = []
matches = list(LANE_RE.finditer(block))
for i, mm in enumerate(matches):
    raw_name = mm.group("lane").strip()
    # Normalize: strip trailing colon (legacy hubs put colon inside bold markers)
    name = raw_name.rstrip(":")
    # Skip the section opener itself -- "Today's priorities" is not a priority lane
    if re.match(r"today.s priorities", name, re.I):
        continue
    start = mm.end()
    end = matches[i + 1].start() if i + 1 < len(matches) else len(block)
    body = block[start:end]
    bullets = []
    for line in body.splitlines():
        ls = line.lstrip()
        if not ls.startswith("- "):
            continue
        # Capture top-level bullets only (no deeper indent)
        indent = len(line) - len(ls)
        if indent > 2:
            continue
        bullets.append(ls[2:].rstrip())
    lanes.append({"lane": name, "bullets": bullets})

# Resolve wikilinks per bullet
WIKI_RE = re.compile(r"\[\[([^\|\]]+?)(?:\|[^\]]+)?\]\]")
out = []
for lane in lanes:
    for raw in lane["bullets"]:
        wl = WIKI_RE.search(raw)
        out.append({
            "lane": lane["lane"],
            "text": raw,
            "wikilink_target": wl.group(1) if wl else None,
        })

print(json.dumps(out, indent=2))
PY
