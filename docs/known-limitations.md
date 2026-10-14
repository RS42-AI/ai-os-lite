# Troubleshooting and remaining gaps

This is a consolidated public-package candidate. It joins setup and workflows and exercises local helpers; it is not yet a claim of verified first use across every assistant and operating system.

## Human-owned instructions in existing workspaces

The supplied starter instructions reflect this candidate's Personal project routing, lifecycle vocabulary and contract rules. Existing workspaces keep their human-owned `AGENTS.md` and `CLAUDE.md`; setup does not replace customized instructions with the new defaults.

Review an existing workspace's instructions against the supplied defaults before using new workflows. If they conflict, the guided workflow pauses affected writes for a human decision. The writer and audit helpers cover selected structural rules; they do not make an unratified contract or stale instruction valid.

## Platform and assistant coverage

| Path | Current boundary |
|---|---|
| macOS local workspace setup | Isolated synthetic setup, rerun and update checks are the candidate's verification path |
| Guided context setup | `setup-context` is a conversation skill; it does not install software or bypass unresolved instruction conflicts |
| Local Morning Brief helpers | Filesystem gathering and Markdown rendering can run without external services; see the [worked example](first-use.md) |
| Claude Code or Codex marketplace installation | Scripts are included; a test double or local command check is not a live authenticated install |
| Obsidian GUI and community plugins | File installation and settings preservation do not prove GUI activation or every plugin's behavior |
| Windows/WSL | Included path; actual Windows-device acceptance remains outstanding |
| Native Windows helpers | No native PowerShell rewrite of the Bash workflow helpers is claimed |
| External integrations | Each needs its own configuration and live verification |
| Existing real-user vaults | No real-user migration is performed or implied by synthetic tests |

The [clean first-use acceptance guide](first-use-acceptance.md) separates core workspace/skill installation from optional personalization, a Morning Brief and Obsidian. Use the [Windows/WSL checklist](../setup/docs/windows-pilot-checklist.md) on an actual Windows device; passing a parser check or mocked installer phase on macOS does not change that platform boundary.

## Common recovery steps

**A vault exists but an integration failed.** Read the component status and rerun the named script. Exit code `2` means partial setup. Keep the existing workspace; do not delete it just to restart.

**The assistant cannot find the skills.** Confirm the CLI/plugin installation succeeded, the expected marketplace is registered and the plugin is enabled. Start a fresh session. Candidate verification must load the selected candidate, not a prior public release.

**The brief has no external tasks or meetings.** Missing connected sources are not the same as an empty workload. Confirm the integration and permissions, or use local-only mode and interpret only the local evidence.

**The starter tasks do not appear.** Check the vault argument and its `Tasks/` files. Run the local context command in [the worked example](first-use.md) and inspect `task_notes`; the Obsidian CLI is not required for this scan.

**An update reports a collision or refuses a move.** Inspect the migration preview. A refusal protects conflicting content, stale plans and instruction-file references. Do not remove the guard or overwrite the destination to force an update.

**Custom settings remain old after an update.** Existing settings and templates are preserved deliberately. Compare the new defaults and apply only the changes you want. Do not replace a customized file wholesale.

**Todoist is installed but commands fail.** The expected executable is `td` from `@doist/todoist-cli`; another CLI with a similar name may have a different command interface. Authentication and account access are separate checks.

## Other open items

- The contributor license agreement process is not published.
- A dedicated AI-OS website and recorded walkthroughs will follow later; none is required to inspect this candidate.
- Production merge, release and old-repository relocation remain human decisions.
