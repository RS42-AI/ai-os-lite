# Capture Schema — workflow.yaml and the package contract

The canonical artifact of a captured workflow is a **package directory**:

    <slug>/
    ├── SKILL.md            # skill frontmatter + intent/judgment rules, ≤150 lines (cap validator-enforced)
    ├── workflow.yaml       # CANONICAL manifest — steps, roles, gates, mutation classes
    ├── agents/
    │   └── openai.yaml     # OpenAI runtime adapter; Claude ignores it (optional — nothing generates it in v1)
    └── evidence/
        └── capture-01.md   # provenance: session id, date, what was demonstrated

The package SKILL.md opens with skill frontmatter — `name: <slug>` (equal to
the directory), a trigger-shaped `description:`, `user-invocable: true` —
without which neither runtime loads it as a skill. The validator enforces
the fence, `name` = directory, a non-empty `description`, and the line cap.

Raw screenshots, page payloads, and binaries NEVER enter the package — the
source session is referenced by opaque id. Private source data stays in its
originating runtime. The validator deterministically rejects credential
patterns, email addresses, common phone-number shapes, machine-specific home
paths, binaries, and terms supplied through `AI_OS_PRIVATE_PATTERN_FILE`.
Names, private URLs, customer facts, and uncommon identifiers still require a
manual full-package review because no deterministic scanner can recognize all
private context.

## workflow.yaml — strict block-style subset

Parsed by a deterministic stdlib parser. Rules: no tabs; no flow style
(`{...}` / `[...]`); top-level `key: value` pairs; `steps:` opens the list;
each step starts `- ` at 2-space indent; continuation keys at 4-space indent;
values are plain scalars (surrounding quotes optional). Unquoted values
treat ` #` (space-then-hash) as the start of a trailing comment, matching
YAML — quote any value that must contain ` #`.

    workflow: ecom-morning-queue        # slug — must match the directory name
    description: One-line purpose
    version: 1
    steps:
      - id: open-dashboards             # unique kebab-case id
        role: ai                        # ai | human (closed vocabulary)
        mutation: read                  # ai steps only — see classes below
        action: Open the signed-in Etsy seller dashboard
      - id: judge-edge-cases
        role: human                     # human steps carry prompt, nothing else
        prompt: Rank or dismiss the items that match no urgency rule
      - id: send-replies
        role: ai
        mutation: send
        gate: approval                  # REQUIRED for every mutation beyond read/draft
        action: Preview each drafted reply and send only what is approved

## Field reference

| Field | Applies to | Rule |
|---|---|---|
| `id` | every step | unique, kebab-case |
| `role` | every step | `ai` or `human` — nothing else |
| `action` | `ai` steps | required; semantic anchors only ("the oldest unfulfilled order's unread message"), never screen coordinates |
| `prompt` | `human` steps | required; the question the agent asks, whose answer feeds the next step |
| `mutation` | `ai` steps | required; one of: `read`, `draft`, `send`, `publish`, `purchase`, `refund`, `delete`, `permission-change` |
| `gate` | `ai` steps | only value: `approval`; REQUIRED when mutation is beyond `read`/`draft` — a hard STOP with exact preview before the side effect |
| `anchor` | `ai` steps | optional note on how to find the target semantically |

Human steps must NOT carry `action`, `mutation`, `gate`, or `anchor` (the
human's own actions are outside the agent's mutation ledger).

### Top-level fields

`workflow` is required: a lowercase-hyphen slug; a mismatch with the
directory name is a warning, not a violation. `description` is expected —
a one-line purpose (unvalidated free text). `version` is an informational
integer, unvalidated in v1.

## Step patterns

Two role values yield three step patterns:
1. `role: ai` (read/draft) — agent executes alone.
2. `role: ai` + `gate: approval` — agent prepares; hard STOP + exact preview before the side effect.
3. `role: human` — agent prompts, waits, feeds the answer forward.

All-`ai` workflows are schedulable in principle (post-v1); workflows with
`human` rows run interactively and pause at those rows. This is what the
vault playbook's `ai_executable: true | partial` summarizes.

## evidence/capture-NN.md

Markdown only. Must name: source session id, capture date, what was
demonstrated, and (for replays) the outcome vs the success criteria.
