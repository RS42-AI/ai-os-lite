---
name: capture-workflow
description: Turn a just-completed browser, computer-use, or other bounded multi-step process into a sanitized, replayable workflow skill with machine-enforced approval gates. Use when the user says "turn this into a skill", "capture that as a workflow", "make this repeatable", "record this process", or "/capture-workflow"; offer it once after a suitable process, never repeatedly.
allowed-tools:
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/capture-workflow/scripts/validate_workflow_manifest.py:*)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/capture-workflow/scripts/list_sessions.py:*)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/capture-workflow/scripts/install_workflow.py:*)
  - Read
  - Write
  - Grep
  - Bash(mkdir:*)
  - Bash(jq:*)
  - Skill
---

# Capture Workflow

## Human license check

Before performing this AI-OS Lite workflow, verify the selected workspace has
a current human-response record for this installed package's exact license
version, SHA-256 and draft/release state. Follow the shared
[license review and receipt flow](../setup-context/SKILL.md#license-review-before-setup-writes).
A matching record is reused without another prompt. If missing, stale or
incomplete, show the complete bundled license through that flow and wait for
the person's actual YES, typed name, capacity and organizational authority
where applicable. Never infer assent, fabricate a record, accept for the user,
or use a terminal to impersonate human input. A draft record is nonoperative.
Read-only license orientation may continue while review is pending. Reading
this reference as part of the license review does not require prior assent.
This is an instruction-level check; it does not authenticate identity or
technically prevent direct execution of individual helper scripts.


Distill a demonstrated process into a standalone workflow package:
`workflow.yaml` (canonical steps, roles, mutations, gates), `SKILL.md`
(judgment rules), and `evidence/` (minimal provenance). Read
`references/capture-schema.md` before compiling.

## Non-negotiable contract

1. Label every AI step with its real mutation class. Every mutation beyond
   `read` or `draft` requires `gate: approval`.
2. Stop at the exact-preview gate. Do not install a skill or write an optional
   vault note until the user approves that exact batch.
3. Never use installer `--force` without separate, explicit replacement
   approval. A slug collision is a refusal, not permission to overwrite.
4. Exclude screenshots, page payloads, credentials, personal data, customer or
   employer identifiers, private URLs, message bodies, and machine-specific
   paths. Generalize examples into variables and semantic anchors.
5. Generated workflows are standalone user installs. Never add one to this or
   another plugin manifest automatically.
6. If approval is denied, keep the staged package and change nothing else.

## 1. Select the demonstrated process

Default to the current session immediately after the process finishes. A
Record & Replay draft is also valid. For a prior Codex session, run:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/capture-workflow/scripts/list_sessions.py
```

Use `--limit N` or `--root DIR` when needed. Present the returned candidates
and let the user choose; never choose a past session yourself. If no compatible
session is available, ask the user to re-demonstrate or provide a replay draft.
Read only the selected span, never an entire large rollout.

State the bounded process in one sentence and confirm it is what the user wants
captured. Stop when the source does not demonstrate a repeatable process.

## 2. Extract and interview

Recover the outcome, trigger, preconditions, invariants, variables, semantic
anchors, authority order, decisions, exceptions, mutation classes, and
completion evidence. Ask only what the trace cannot establish, in one short
batch: why a source wins, what is urgent, which values are examples, and what
"finished correctly" means.

## 3. Compile a portable package

Resolve the staging root in this order:

1. `AI_OS_WORKFLOW_ROOT`, when the user has configured it.
2. `${XDG_DATA_HOME}/ai-os-lite/workflows`, when `XDG_DATA_HOME` is set.
3. `~/.local/share/ai-os-lite/workflows`.

Create `<root>/<slug>/`, where the slug is lowercase hyphen-case. Do not put
the user's generated packages inside the installed plugin. Compile only
portable semantics: replace names, organizations, projects, account IDs,
private URLs, and local paths with clearly described variables. Reference the
source session by opaque ID in `evidence/capture-01.md`; never copy raw content.

`workflow:` and the package directory must match. The generated `SKILL.md`
must start with `name`, a trigger-shaped `description`, and
`user-invocable: true`, and remain within the validator's line cap.

## 4. Validate and sanitize

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/capture-workflow/scripts/validate_workflow_manifest.py <package_dir>
```

Exit 0 means no violations. Resolve every warning that would prevent a clean
install, including slug mismatch and missing capture evidence. The validator
checks structure, gates, credentials, common personal-data shapes, binaries,
local paths, and optional user denylist terms. It cannot recognize every name
or confidential fact: inspect the full package manually before previewing.

Users may set `AI_OS_PRIVATE_PATTERN_FILE` to a newline-delimited local file of
additional names or terms that must never enter generated packages. Do not
copy that file or its matches into the package or output.

## 5. Optionally draft vault documentation

This phase is optional and never blocks skill creation. Treat the active
workspace as a vault only when it contains an `AGENTS.md` that defines its own
routing and templates. Read that live canon; do not assume any note type,
folder, field, status, area, or project.

When the canon provides a compatible route, draft one concise workflow or
playbook note using its template and provenance conventions. If no compatible
route exists, or `write-note` is unavailable, skip the note and say why. Never
invent schema or silently fall back to a plugin-specific path.

## 6. Exact preview and hard stop

Show:

- the exact package tree;
- the full `workflow.yaml`;
- the full generated `SKILL.md`;
- every evidence file;
- the optional vault-note draft and destination, if one exists;
- the requested install targets: Codex, Claude Code, or both.

Stop and wait for explicit approval of that exact content.

## 7. Apply only the approved batch

After approval, delegate an approved vault note to `write-note`, when present,
then install only to the approved runtimes:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/capture-workflow/scripts/install_workflow.py <package_dir> --both
```

Use `--codex` or `--claude` for one runtime. Report the installer's JSON result
as the source of truth. Exit 1 is a refusal with no writes; exit 3 may be a
partial operational failure and must be reported exactly. State what installed
and how the user invokes it.
