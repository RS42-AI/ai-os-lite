#!/usr/bin/env bash
# Parse the Recent Accomplishments / Needs Attention section that /start-day
# wrote into today's Morning Brief. Emit a JSON list of warm + cold
# project slugs with annotations for /process-morning to cross-reference.
# Usage: parse_startday_recap.sh YYYY-MM-DD
set -euo pipefail
source "$(dirname "$0")/lib.sh"

today="$1"
journal_path="$(obs_path "5. Resources/Personal/Journal/Morning Entries/$today.md")"

if [[ ! -f "$journal_path" ]]; then
  echo "[]"
  exit 0
fi

python3 - "$journal_path" <<'PY'
import sys, re, json

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()

# Locate the Needs Attention section (between H3 and next H3 or H2 or EOF).
m = re.search(r"### Needs Attention\b.*?(?=^### |\n## |\Z)", text, re.S | re.M)
if not m:
    print("[]"); sys.exit(0)
section = m.group(0)

# Graceful degradation: if no H4 sub-bands (#### Warm / #### Cold),
# this is a pre-banded journal — return empty rather than error.
if not re.search(r"^#### (Warm|Cold)", section, re.M):
    print("[]"); sys.exit(0)

def parse_band(block):
    """
    Parse bullet lines of the form:
      - **[[Area]] / [[Project Hub|Alias]]** — <rest>
    or
      - **[[Area]] / [[Full/Path/To/Project|Alias]]** — <rest>

    Days silent: first integer before 'd ' (handles 'Nd since', 'Nd via',
    'Nd (hub-level', '(project tree)', etc.)
    Last-activity link: first wikilink in the rest portion.
    Annotation: text after the first '. ' (period-space) in rest.
    Cold-band lines often use '`status: active` but...' with no days counter.
    """
    bullets = []
    # Match the bold wikilink pair: **[[Area]] / [[Project...]]**
    # The project half may have a full path and/or a pipe alias.
    BULLET = re.compile(
        r"^- \*\*\[\[(?P<area>[^\]]+)\]\] / "
        r"\[\[(?P<project_raw>[^\]]+)\]\]\*\*"
        r" — (?P<rest>.+)$",
        re.M,
    )
    for mm in BULLET.finditer(block):
        project_raw = mm.group("project_raw")
        rest = mm.group("rest").strip()

        # Resolve project display name: use alias if pipe-separated, else raw.
        if "|" in project_raw:
            project_link = project_raw.split("|", 1)[0].strip()
            project_display = project_raw.split("|", 1)[1].strip()
        else:
            project_link = project_raw.strip()
            project_display = project_raw.strip()

        # Days silent: integer immediately before 'd ' (permissive suffix).
        days = None
        days_m = re.match(r"(\d+)d\b", rest)
        if days_m:
            days = int(days_m.group(1))

        # First wikilink in rest is the last-activity / plan link.
        link_m = re.search(r"\[\[([^\|\]]+?)(?:\|[^\]]+)?\]\]", rest)
        last_link = link_m.group(1) if link_m else None

        # Annotation: remainder after first '. ' in rest.
        ann = ""
        if ". " in rest:
            ann = rest.split(". ", 1)[1].rstrip()

        bullets.append({
            "area": mm.group("area"),
            "project_link": project_link,
            "project_display": project_display,
            "days_silent": days,
            "last_activity_link": last_link,
            "annotation": ann,
        })
    return bullets

out = []

# H4 sub-bands: #### Warm ... / #### Cold ...
# Capture everything from the H4 line up to the next #### or ### or H2 or EOF.
warm_m = re.search(
    r"^#### Warm[^\n]*\n(.*?)(?=^#### |^### |\n## |\Z)",
    section, re.S | re.M
)
cold_m = re.search(
    r"^#### Cold[^\n]*\n(.*?)(?=^#### |^### |\n## |\Z)",
    section, re.S | re.M
)

for b in parse_band(warm_m.group(1) if warm_m else ""):
    b["band"] = "warm"
    out.append(b)
for b in parse_band(cold_m.group(1) if cold_m else ""):
    b["band"] = "cold"
    out.append(b)

print(json.dumps(out, indent=2))
PY
