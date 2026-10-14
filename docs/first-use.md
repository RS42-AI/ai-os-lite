# Worked example: a first useful Morning Brief

This is one optional use of saved context after [workspace and skill setup](setup.md), not the definition of a successful installation. It uses only the synthetic starter content shipped in this repository. It does not need Todoist, Linear, a calendar connector or the Obsidian CLI. It shows a real run of the local evidence and rendering helpers, followed by the separate assistant step.

## Input

The fresh workspace includes three open onboarding tasks:

| Task | Starting state |
|---|---|
| Add my first project | Ready to consider |
| Set up my first goal | Waits for the first project |
| Set up my AGENTS | Waits for the first goal |

No task is marked done to prepare this example. No real project, private note or external account is used.

## Reproduce the local path

From the repository root, with Git, Bash, Python 3.10+ and `jq` available:

```bash
demo_root="$(mktemp -d)"
bash setup/setup-vault.sh "$demo_root/vault"

AI_OS_LOCAL_ONLY=1 bash plugins/ai-os-lite/skills/start-day/scripts/gather_morning_context.sh \
  2026-10-12 "$demo_root/vault" > "$demo_root/context.json"

python3 plugins/ai-os-lite/skills/start-day/scripts/render_start_day.py \
  "$demo_root/context.json" > "$demo_root/morning-brief.md"

cat "$demo_root/morning-brief.md"
```

The fixed date makes the published example reproducible. Use your current local date for everyday work. `AI_OS_LOCAL_ONLY=1` skips external adapters and suppresses privacy-stamping writes. The redirections above save the outputs beside the demo vault, not into an existing workspace.

The actual recorded run included empty daily and Morning Brief scaffolds before gathering. That affects the `files` existence flags in the JSON; it does not change the three tasks or their dependencies. The commands above intentionally keep the first inspection outside the vault.

## Actual output

The October 12 candidate run found all three tasks through the filesystem. [The complete JSON](examples/first-use/context.json) records `source: "filesystem"`, `count: 3`, `todo_count: 3` and no task-read errors. Its source manifest says Todoist, Linear and calendar were skipped in local-only mode.

The [rendered Morning Brief](examples/first-use/morning-brief.md) includes:

```text
### Control Queue
#### Review
- [[Personal/2. Projects/Vault-Setup/Tasks/Add my first project|Add my first project]] - ready to consider for your next action.

#### Decide
- [[Personal/2. Projects/Vault-Setup/Tasks/Set up my AGENTS|Set up my AGENTS]] - waiting on [[Set up my first goal]]
- [[Personal/2. Projects/Vault-Setup/Tasks/Set up my first goal|Set up my first goal]] - waiting on [[Add my first project]]

#### Dispatch
- No unblocked `ai-handoff` task notes found.
```

The excerpt shortens the two dependency explanations; the linked output preserves them in full. “Review” contains work ready for your consideration; “Decide” exposes work that still has a dependency or decision; “Dispatch” contains tasks explicitly prepared for an assistant handoff. These labels are views of the task evidence, not new task statuses.

The brief also says there is no recorded evening entry, captured work or meeting note. Missing sources are not proof that you have no external commitments. Read the JSON source manifest alongside the brief when checking the scope of its evidence.

## Ask your assistant to use it

After installing this candidate's skills and opening the demo vault in a fresh assistant session, use:

```text
Run start-day for October 12, 2026 using only this demo vault.
Show the three onboarding tasks and their dependencies, explain which sources
were available, and propose one useful next step. Do not mark tasks complete
or change external services. Save the brief only in this demo vault.
```

Check that the assistant grounds its next-step proposal in the first project task, preserves the dependency order, identifies skipped external sources and saves the result where it says it did. Use the skill's normal daily scaffolding when saving a Morning Brief; the raw renderer output is a body section, not a complete standalone vault note.

## What this proves

The recorded run verifies a fresh isolated workspace, discovery of the starter tasks without the Obsidian CLI, and deterministic Markdown rendering with no external service calls. The current Codex assistant also saved the body into the Morning Brief scaffold, preserved the human-input region, and added this evidence-based next step: “Choose one small project for ‘Add my first project’; the goal and instruction tasks depend on that choice.” All three task statuses remained `todo`. The [saved note](examples/first-use/saved-morning-brief.md) and [verification receipt](examples/first-use/first-use-receipt.json) record that bounded end-to-end run.

It does not prove a newly installed authenticated Claude Code or Codex account, a live calendar/Todoist/Linear connection, Windows/WSL first use or the quality of an assistant's synthesis. Those remain distinct checks in the [clean first-use acceptance guide](first-use-acceptance.md). The [known limitations](known-limitations.md) also explain how to review preserved instructions when adopting new workflows in an existing workspace.
