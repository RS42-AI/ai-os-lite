#!/usr/bin/env python3
"""Normalize hub section headings to template canon and restore template order.

Repair step 2 of the 2026-07-04 alignment map (Species B): rename aliased
headings to their canonical names, then reorder canonical sections to template
order. Dry-run by default — prints the per-file plan; --apply writes.

Canon and policy are IMPORTED from audit_vault.py (single source of truth):
templates define the sections, SECTION_ALIASES defines rename targets,
STRUCTURE_STATUS defines which notes are subjects. Guarantees:

- unknown sections are never renamed, dropped, or detached — they travel
  with the canonical section they follow (their anchor);
- mistyped hubs (0 canonical sections) are skipped, same as the auditor;
- missing sections are NOT inserted (that is repair step 3, human-gated);
- frontmatter and all section content are preserved byte-for-byte.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import audit_vault as av  # noqa: E402  (canon source of truth)


def split_raw(text: str) -> tuple[str, str]:
    """Lossless frontmatter split on the raw file text -> (fm_block, body)."""
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            nl = text.find("\n", end + 1)
            if nl == -1:
                return text, ""
            return text[: nl + 1], text[nl + 1 :]
    return "", text


def parse_sections(body: str) -> tuple[list[str], list[dict]]:
    """Fence-aware split into (preamble_lines, sections). Each section is
    {'heading': str, 'lines': [str]} with the heading line included."""
    pre: list[str] = []
    sections: list[dict] = []
    cur: dict | None = None
    fence = False
    for ln in body.splitlines():
        if ln.lstrip().startswith("```"):
            fence = not fence
        m = None if fence else av.H2_RE.match(ln)
        if m:
            cur = {"heading": m.group(1).strip(), "lines": [ln]}
            sections.append(cur)
        elif cur is None:
            pre.append(ln)
        else:
            cur["lines"].append(ln)
    return pre, sections


def load_canon_display(vault: Path) -> dict[str, list[str]]:
    """Ordered template section names per type, ORIGINAL case (the auditor's
    load_template_sections lowercases; renames must write display case)."""
    canon: dict[str, list[str]] = {}
    tdir = vault / "system-settings" / "Templates"
    for typ, fname in av.TYPE_TEMPLATE.items():
        f = tdir / fname
        if not f.is_file():
            continue
        _, body = av.split_frontmatter(f.read_text(encoding="utf-8", errors="replace"))
        nocode = av.FENCED_RE.sub("", body)
        canon[typ] = [m.group(1).strip()
                      for line in nocode.splitlines() if (m := av.H2_RE.match(line))]
    return canon


DATED_RE = re.compile(r"^(.*?)\s*\((\d{4}-\d{2}-\d{2})\)$")


def plan_doc(doc, canon_names: list[str]) -> tuple[list[str], str] | None:
    """Return (ops, new_body) if the doc needs repair, else None."""
    canon_lower = [c.lower() for c in canon_names]
    canon_set = set(canon_lower)
    display = dict(zip(canon_lower, canon_names))
    order_idx = {c: i for i, c in enumerate(canon_lower)}

    _, raw_body = split_raw(doc.path.read_text(encoding="utf-8"))
    pre, secs = parse_sections(raw_body)
    if not secs:
        return None
    # mistyped-hub guard — mirror the auditor: never "repair" a doc that shares
    # no sections with its type's template
    if not any(s["heading"].lower() in canon_set for s in secs):
        return None

    ops: list[str] = []

    # pass 1 — renames (alias -> canonical, only if the canonical isn't present).
    # A "Section (YYYY-MM-DD)" heading normalizes to its base; the date moves
    # into the section body (staleness info is content, not API surface).
    present = {s["heading"].lower() for s in secs}
    for s in secs:
        h = s["heading"].lower()
        if h in canon_set:
            continue
        target = av.SECTION_ALIASES.get(h)
        date_note = None
        if not target:
            m = DATED_RE.match(h)
            if m:
                base = m.group(1).strip()
                base_canon = base if base in canon_set else av.SECTION_ALIASES.get(base)
                if base_canon and base_canon in canon_set:
                    target, date_note = base_canon, m.group(2)
        if target and target in canon_set and target not in present:
            ops.append(f"rename: '## {s['heading']}' -> '## {display[target]}'"
                       + (f" (date kept in body: {date_note})" if date_note else ""))
            s["heading"] = display[target]
            s["lines"][0] = f"## {display[target]}"
            if date_note:
                s["lines"][1:1] = ["", f"*(as of {date_note})*"]
            present.discard(h)
            present.add(target)

    # pass 2 — reorder canonical sections to template order; unknown sections
    # travel with the canonical section they follow (chain anchoring)
    chains: list[dict] = []  # {'idx': template index or None, 'secs': [section]}
    cur_chain: dict | None = None
    for s in secs:
        h = s["heading"].lower()
        if h in canon_set:
            cur_chain = {"idx": order_idx[h], "secs": [s]}
            chains.append(cur_chain)
        elif cur_chain is None:
            chains.append({"idx": None, "secs": [s]})  # leading unknowns stay put
            cur_chain = None
        else:
            cur_chain["secs"].append(s)

    head = [c for c in chains if c["idx"] is None]
    tail = sorted((c for c in chains if c["idx"] is not None), key=lambda c: c["idx"])
    new_secs = [s for c in head + tail for s in c["secs"]]
    if [s["heading"] for s in new_secs] != [s["heading"] for s in secs]:
        ops.append("reorder: "
                   + " > ".join(s["heading"].lower() for s in secs)
                   + "  ->  "
                   + " > ".join(s["heading"].lower() for s in new_secs))

    if not ops:
        return None
    new_body = "\n".join(pre + [ln for s in new_secs for ln in s["lines"]])
    if raw_body.endswith("\n"):
        new_body += "\n"
    return ops, new_body


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("vault", type=Path)
    ap.add_argument("--apply", action="store_true",
                    help="write repairs (default is a dry-run report)")
    args = ap.parse_args()

    vault = args.vault.resolve()
    canon = load_canon_display(vault)
    subjects = [d for d in av.load_docs(vault)
                if d.type in canon
                and d.status in av.STRUCTURE_STATUS.get(d.type, set())
                and "system-settings/Templates" not in d.rel]

    n_files = n_ops = 0
    for doc in subjects:
        planned = plan_doc(doc, canon[doc.type])
        if not planned:
            continue
        ops, new_body = planned
        n_files += 1
        n_ops += len(ops)
        print(f"== {doc.rel}")
        for op in ops:
            print(f"  {op}")
        if args.apply:
            fm, _ = split_raw(doc.path.read_text(encoding="utf-8"))
            doc.path.write_text(fm + new_body, encoding="utf-8")

    verb = "repaired" if args.apply else "need repair"
    print(f"\n{n_files} files {verb} ({n_ops} operations)."
          + ("" if args.apply else " Dry run — nothing written. Use --apply to write."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
