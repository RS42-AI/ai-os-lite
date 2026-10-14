#!/usr/bin/env python3
"""Deterministic validator for capture-workflow packages.

Usage: validate_workflow_manifest.py <package_dir>

Exit codes: 0 = clean (warnings allowed), 1 = violations, 2 = usage error.
Output: JSON {"violations": [...], "warnings": [...]} on stdout.

workflow.yaml must use the strict block-style subset defined in
references/capture-schema.md; flow style is rejected so this stdlib-only
parser stays deterministic (repo convention: no external deps). Plain
(unquoted) scalar values may carry a trailing ` # comment` — everything
from the first space-hash onward is stripped before validation; quoted
values are left untouched.
"""
import json
import os
import re
import sys
from pathlib import Path

ROLES = {"ai", "human"}
MUTATIONS = {"read", "draft", "send", "publish", "purchase",
             "refund", "delete", "permission-change"}
GATED = MUTATIONS - {"read", "draft"}
STEP_KEYS = {"id", "role", "action", "prompt", "mutation", "gate", "anchor"}
TOP_KEYS = {"workflow", "description", "version"}
SKILL_MD_MAX_LINES = 150
BINARY_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf",
               ".mp4", ".mov", ".zip", ".heic"}
SECRET_PATTERNS = [
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"ghp_[A-Za-z0-9]{36}"),
    re.compile(r"xox[bpars]-[A-Za-z0-9-]+"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)(?:password|token|secret|api[_-]?key)\s*[:=]\s*\S+"),
    re.compile(r"(?i)\bbearer\s+[a-z0-9_\-.]{16,}"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),  # catches sk-proj-… project keys
    re.compile(r"(?i)\bpasswd\s*[:=]\s*\S+"),
]
DATA_URI_RE = re.compile(r"data:(image|video|application)/[^;]{1,30};base64,")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
PHONE_RE = re.compile(r"(?:\(\d{3}\)\s?|\b\d{3}[-.\s])\d{3}[-.\s]\d{4}\b")
LOCAL_PATH_RE = re.compile(
    r"(?:/" + r"Users/[^/\s]+|/home/[^/\s]+|[A-Za-z]:\\" +
    r"Users\\[^\\\s]+)"
)
_COORD_CLICK = re.compile(r"(?i)\b(click|tap|move|drag)\b[^.]{0,40}\b\d{2,4}\s*,\s*\d{2,4}")
_COORD_KEYWORD = re.compile(r"(?i)\b(coordinate|pixel)s?\b")
_COORD_XY = re.compile(r"(?i)\bx\s*=\s*\d{2,4}\D{0,6}y\s*=\s*\d{2,4}")
# Full set — used on ai-step action/anchor fields, which are short and
# purpose-written, so the bare keyword pattern doesn't false-positive there.
COORD_PATTERNS = [_COORD_CLICK, _COORD_KEYWORD, _COORD_XY]
# Positional-only — used on SKILL.md prose, where the bare keyword pattern
# would flag legitimate sentences like "Coordinate the reply queue...".
SKILL_MD_COORD_PATTERNS = [_COORD_CLICK, _COORD_XY]


def parse_manifest(text):
    """Parse the strict block-style subset. Returns (doc, steps, errors);
    steps is a list of (line_no, dict)."""
    doc, errors = {}, []
    steps = None
    step = None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if "\t" in raw:
            errors.append(f"line {n}: tabs are not allowed")
            continue
        indent = len(line) - len(line.lstrip())
        body = line.strip()
        if body.startswith("- "):
            if steps is None or indent != 2:
                errors.append(f"line {n}: step item outside 'steps:' or wrong indent")
                continue
            body = body[2:].strip()
            if body and body[0] in "{[":
                errors.append(f"line {n}: flow-style YAML is not allowed (strict subset)")
                continue
            step = {}
            steps.append((n, step))
            if not body:
                continue
        key, sep, value = body.partition(":")
        if not sep:
            errors.append(f"line {n}: expected 'key: value'")
            continue
        key, value = key.strip(), value.strip()
        # NB: guard on `value` — `"" in "{["` is True in Python, so a bare
        # `steps:` line (empty value) must not be mistaken for flow style.
        if value and value[0] in "{[":
            errors.append(f"line {n}: flow-style YAML is not allowed (strict subset)")
            continue
        # Trailing ` # comment` is stripped from unquoted plain scalars only;
        # quoted values keep their content untouched. Quote-stripping (below)
        # always runs after comment-stripping.
        quoted = len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'"
        if not quoted:
            hash_idx = value.find(" #")
            if hash_idx != -1:
                value = value[:hash_idx].rstrip()
                quoted = len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'"
        if quoted:
            value = value[1:-1]
        if indent == 0:
            if key == "steps":
                if steps is not None:
                    errors.append(f"line {n}: duplicate key 'steps'")
                else:
                    steps = []
                step = None
            elif key in doc:
                errors.append(f"line {n}: duplicate key '{key}'")
            else:
                doc[key] = value
        elif indent in (2, 4) and step is not None:
            if key in step:
                errors.append(f"line {n}: duplicate step key '{key}'")
            else:
                step[key] = value
        else:
            errors.append(f"line {n}: unexpected indent {indent}")
    return doc, (steps or []), errors


def check(pkg: Path):
    V, W = [], []
    v = lambda c, d: V.append({"check": c, "detail": d})
    w = lambda c, d: W.append({"check": c, "detail": d})

    private_terms = []
    private_pattern_arg = os.environ.get("AI_OS_PRIVATE_PATTERN_FILE")
    if private_pattern_arg:
        private_pattern_file = Path(private_pattern_arg).expanduser()
        if not private_pattern_file.is_file():
            v("private_pattern_file_missing", "AI_OS_PRIVATE_PATTERN_FILE is not a file")
        else:
            try:
                private_terms = [
                    line.strip()
                    for line in private_pattern_file.read_text(encoding="utf-8").splitlines()
                    if line.strip() and not line.lstrip().startswith("#")
                ]
            except (UnicodeDecodeError, OSError):
                v("private_pattern_file_unreadable", "AI_OS_PRIVATE_PATTERN_FILE could not be read")

    mf = pkg / "workflow.yaml"
    if not mf.is_file():
        v("manifest_missing", "workflow.yaml not found")
    else:
        doc, steps, errors = parse_manifest(mf.read_text(encoding="utf-8"))
        for e in errors:
            v("manifest_parse", e)
        slug = doc.get("workflow", "")
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", slug):
            v("bad_slug", f"workflow: '{slug}' is not a lowercase-hyphen slug")
        elif slug != pkg.name:
            w("slug_dir_mismatch", f"workflow '{slug}' != directory '{pkg.name}'")
        for key in doc:
            if key not in TOP_KEYS:
                w("unknown_top_key", key)
        if not steps:
            v("no_steps", "steps: list is missing or empty")
        seen = set()
        for n, s in steps:
            sid = s.get("id")
            label = sid if sid else f"<line {n}>"
            loc = f"step '{label}'"
            if not sid:
                v("missing_id", loc)
            elif not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", sid):
                v("bad_id", f"{loc}: id '{sid}' is not lowercase-kebab-case")
            if sid:
                if sid in seen:
                    v("duplicate_id", loc)
                seen.add(sid)
            for key in s:
                if key not in STEP_KEYS:
                    v("unknown_step_key", f"{loc}: '{key}'")
            role = s.get("role")
            if role not in ROLES:
                v("invalid_role", f"{loc}: role '{role}' (allowed: ai, human)")
                continue
            if role == "human":
                if not s.get("prompt"):
                    v("human_missing_prompt", loc)
                for bad in ("mutation", "gate", "action", "anchor"):
                    if bad in s:
                        v("human_step_extra_field",
                          f"{loc}: human steps must not carry '{bad}'")
            else:
                if not s.get("action"):
                    v("ai_missing_action", loc)
                mut = s.get("mutation")
                if mut not in MUTATIONS:
                    v("invalid_mutation", f"{loc}: mutation '{mut}'")
                elif mut in GATED and s.get("gate") != "approval":
                    v("ungated_mutation",
                      f"{loc}: mutation '{mut}' requires gate: approval -- "
                      "add 'gate: approval' -- do not change the mutation class")
                if "gate" in s and s.get("gate") != "approval":
                    v("invalid_gate", f"{loc}: gate '{s['gate']}' (only 'approval')")
                hay = " ".join(s.get(k, "") for k in ("action", "anchor"))
                if any(p.search(hay) for p in COORD_PATTERNS):
                    v("coordinate_action",
                      f"{loc}: use semantic anchors, not screen coordinates")

    skill_md = pkg / "SKILL.md"
    if not skill_md.is_file():
        v("skill_md_missing", "SKILL.md not found")
    else:
        skill_lines = skill_md.read_text(encoding="utf-8").splitlines()
        n_lines = len(skill_lines)
        if n_lines > SKILL_MD_MAX_LINES:
            v("skill_md_too_long", f"{n_lines} lines (cap {SKILL_MD_MAX_LINES})")
        # Frontmatter fence: stdlib-only, no YAML lib -- SKILL.md frontmatter
        # here is always plain unquoted `key: value` lines (repo convention).
        if not skill_lines or skill_lines[0].strip() != "---":
            v("skill_md_missing_frontmatter", "SKILL.md must open with a '---' frontmatter fence")
        else:
            close = next((i for i in range(1, len(skill_lines))
                          if skill_lines[i].strip() == "---"), None)
            if close is None:
                v("skill_md_missing_frontmatter", "opening '---' frontmatter fence is never closed")
            else:
                fm = {}
                for ln in skill_lines[1:close]:
                    if ":" in ln:
                        k, val = ln.split(":", 1)
                        fm[k.strip()] = val.strip()
                missing = [k for k in ("name", "description") if not fm.get(k)]
                if missing:
                    v("skill_md_missing_frontmatter",
                      f"frontmatter missing/empty field(s): {', '.join(missing)}")
                elif fm["name"] != pkg.name:
                    v("skill_md_name_mismatch",
                      f"SKILL.md name '{fm['name']}' != directory '{pkg.name}'")
        for i, ln in enumerate(skill_lines, 1):
            if any(p.search(ln) for p in SKILL_MD_COORD_PATTERNS):
                v("coordinate_action", f"SKILL.md:{i}")

    ev = pkg / "evidence"
    caps = list(ev.glob("capture-*.md")) if ev.is_dir() else []
    if not caps:
        w("no_capture_evidence", "evidence/capture-*.md not found")

    for f in sorted(pkg.rglob("*")):
        if f.is_symlink():
            v("symlink_in_package", str(f.relative_to(pkg)))
            continue
        if not f.is_file():
            continue
        rel = str(f.relative_to(pkg))
        if f.suffix.lower() in BINARY_EXTS:
            v("binary_payload", rel)
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            v("binary_payload", f"{rel} (undecodable)")
            continue
        if any(p.search(text) for p in SECRET_PATTERNS):
            v("embedded_secret", rel)
        if EMAIL_RE.search(text) or PHONE_RE.search(text):
            v("embedded_pii", rel)
        if LOCAL_PATH_RE.search(text):
            v("machine_specific_path", rel)
        lowered = text.casefold()
        if any(term.casefold() in lowered for term in private_terms):
            v("private_pattern", rel)
        if DATA_URI_RE.search(text):
            v("binary_payload", f"{rel} (embedded base64 data URI)")
    return V, W


def main():
    if len(sys.argv) != 2:
        print("usage: validate_workflow_manifest.py <package_dir>", file=sys.stderr)
        return 2
    pkg = Path(sys.argv[1]).expanduser()
    if not pkg.is_dir():
        print(json.dumps({"violations": [{"check": "package_missing",
                                          "detail": str(pkg)}], "warnings": []}, indent=2))
        return 1
    V, W = check(pkg)
    print(json.dumps({"violations": V, "warnings": W}, indent=2))
    return 1 if V else 0


if __name__ == "__main__":
    sys.exit(main())
