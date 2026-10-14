# How the kit's update channel works

How `setup-vault.sh --update` and `/update-structure` cooperate to keep an installed vault in sync with the kit's canonical shape, without forcing reinstalls or clobbering customizations.

This doc covers the *operational mental model* — what files go where, what happens when you run things.

## The two delivery moments

The kit has two distinct moments it interacts with a user's vault:

**Moment 1 — Fresh install.** User runs `bash setup.sh ~/AIOS` (or just `bash setup-vault.sh ~/AIOS`). This creates folder structure, copies starter content, initializes git. The kit's job is done; the vault is theirs to live in.

The fresh default is `~/AIOS`; explicit destinations override it. Existing vaults keep their current paths. Neither setup mode searches for or moves an older vault. For update commands below, replace the example with the actual existing path; `--update` refuses an omitted path.

**Moment 2 — Update channel** (v0.2+). Months later the kit ships improvements — a renamed file, a new template, a structural convention change. The user runs `bash setup-vault.sh --update ~/AIOS`. This is the entry point to the update channel. It performs four bounded, additive actions and then steps aside.

## What `setup-vault.sh --update` actually does

Four steps, in order, idempotent on every re-run:

1. **Writes `~/AIOS/.vault-kit-path`** — a one-line file containing the absolute path to the kit repo on this machine (e.g. `~/ai-os-lite/setup`). This is how the slash command finds the kit later.

2. **Copies the slash-command runner** into `~/AIOS/.claude/commands/update-structure.md`. An existing runner is preserved. If it differs, setup prints the current source path so the owner can review and replace it.

3. **Re-runs the non-clobber copy of supported `vault-files/*`** — the same base content used by a fresh install, while preserving every existing file. Update mode excludes `AGENTS.md` and `CLAUDE.md`; those instruction files are human-owned and any proposed wording change goes through owner review.

4. **Completes established project containers** — reads the public `structure/project-structure.json` profile, discovers supported project hubs, and creates any missing `Tasks/`, `Notes/`, `Resources/`, `Artifacts/`, `Specs/`, and `Dev Log/` directories. It also ensures area-level Tasks and Resources destinations. This creates directories only: it does not move files, rewrite consumers, or infer projects from ordinary folders.

After these four steps the script prints `Next steps:` directing the user to run `/update-structure` in Claude Code.

The September 6 Personal-layout migration is a separate previewed operation in `/update-structure`. Its helper inventories exact moves, collisions, symlinks, instruction/configuration consumers, and unknown roots. Application requires the preview's exact token and writes a rollback receipt plus local backups.

## What `/update-structure` does at runtime

The user opens Claude Code in their vault and types `/update-structure`. Claude Code finds `<vault>/.claude/commands/update-structure.md`, loads it as instructions, and the body walks Claude through:

1. **Locate vault root** — verify we're in a vault by checking for `CLAUDE.md` or `AGENTS.md`.
2. **Read `.vault-kit-path`** — locate the kit repo on disk. If this file is missing, stop and tell the user to run `setup-vault.sh --update <vault>` first.
3. **Check git state** — warn if uncommitted changes exist; the user can mix kit-added files with pending work, but it should be a conscious choice.
4. **List structure updates** — read `<kit>/structure-updates/*.md`, sort by filename (dated `YYYY-MM-DD-*`), cross-reference against `.vault-structure-updates-applied` to find which are still pending.
5. **For each pending update** — read the prose doc's `## Detection` section, evaluate it against the user's actual vault state.
6. **If detection matches** — walk the user through the `## Changes` section, propose each edit, ask for confirmation before writing. Run the `## Verification` checks. Record outcome.
7. **If detection does not match** — record as `vacuously-applied`. The update is checked off; no files were changed because nothing needed changing.
8. **Append to `.vault-structure-updates-applied`** — one tab-delimited line per update: `<id>    <timestamp>    <status>` where status is `applied` or `vacuously-applied`.

The runner respects flags: `--list` prints the inventory and exits; `--dry-run` walks all steps but skips the write phase and the log append.

## Disk layout (after `setup-vault.sh --update` has run)

```
[Reviewed AI-OS Lite source checkout; bundled setup component]
~/code/ai-os-lite/setup/
├── structure-updates/
│   └── 2026-05-16-agents-md-adoption.md     (one per shape change; sorted by date)
├── commands/
│   └── update-structure.md                  (the runner; shipped into vaults)
├── setup-vault.sh                           (entry point; --update is the new mode)
└── vault-files/                             (canonical content; copied non-clobber)
    ├── AGENTS.md, CLAUDE.md, ...             (fresh-install sources; excluded from update writes)

[User's vault — receives the bottom three additions]
~/AIOS/
├── AGENTS.md, CLAUDE.md, ...                (human-owned; preserved by --update)
├── 1. Daily/, 2. Projects/, ...             (user content is never overwritten; missing project containers may be added)
├── .vault-kit-path                          NEW — points to the kit repo
├── .claude/commands/update-structure.md     NEW — copied from kit/commands/
└── .vault-structure-updates-applied         NEW — appended by /update-structure runs
```

The new dotfiles and command are operational state, not user content. The vault's `.gitignore` can list them so they don't pollute commits.

## Why running it against an already-current vault is safe

Already-current files are preserved by the copy step, directory creation is idempotent, and each structure update has an explicit detection rule. The historical automatic instruction rewrite is now vacuously applied because instruction files are human-owned. Moves and consumer rewrites use an exact preview, stop on collisions or stale inputs, and create a rollback receipt. The user sees the full change before any move happens.

## Existing-vault upgrade flow

This is the supported path:

1. Select the reviewed AI-OS Lite package in a separate local source checkout. For a replacement with fresh history, obtain a new checkout from the announced destination; do not pull or merge it into an old checkout.
2. From that checkout's root, run `bash setup/setup-vault.sh --update "/absolute/path/to/Existing Vault"`. The explicit existing path is required. After any required human license review, this records the bundled setup path, installs a missing command, non-clobber-copies supported files, and creates missing containers at already-supported project paths.
3. Open Claude Code in the vault and run `/update-structure`. The runner evaluates pending updates and produces an exact preview for any Personal-path migration.
4. Resolve collisions, symlinks, binary consumers, or instruction-file consumers before application. Unknown roots remain untouched.
5. Approve the exact preview. The helper applies it only if the preview token and all source/consumer fingerprints still match.
6. Verify the second preview is empty and retain the receipt until rollback is no longer needed. Future runs are no-ops until the Kit ships another update.

The whole flow assumes the reviewed AI-OS Lite package is available locally. The slash command reads its bundled setup files without fetching another source. Selecting a newer package is separate from applying workspace updates. Assistant plugin installation uses the same reviewed local checkout through the gated wrappers described in [the transition procedure](../existing-vault-transition.md).

## What you don't need to do

- **No separate Kit checkout for the new package.** AI-OS Lite includes setup. A replacement source history still requires a fresh source checkout; the workspace stays in its existing location.
- **No reinstall of the vault.** The update channel uses non-clobber copies, additive scaffolding, and separately previewed moves.
- **No manual reading of `structure-updates/` prose.** The slash command reads them for you and walks you through changes interactively.
- **No remembering which updates you applied.** `.vault-structure-updates-applied` is the durable record; `/update-structure --list` prints it on demand.

## Where each piece is documented

| Concept | Location |
|---|---|
| Operational mental model (this doc) | `docs/architecture/update-channel.md` |
| The runner itself | `commands/update-structure.md` |
| The first structure update | `structure-updates/2026-05-16-agents-md-adoption.md` |
| Setup-script behavior | `setup-vault.sh` header comment |
