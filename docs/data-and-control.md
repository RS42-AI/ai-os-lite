# Your data and control

Your AI-OS workspace is a folder of Markdown notes and supporting configuration. You can open it in Obsidian, inspect it with other editors and back it up with tools you choose. Keep it separate from the public AI-OS Lite source checkout.

## What stays on your device

Setup creates local workspace files. The local-only first-use mode reads workspace evidence without changing it and renders output to standard output. Normal Morning Brief gathering can also add one-way `private: true` stamps to files that inherit a private project setting; do not describe that normal mode as read-only. Git initialization and commits are local unless you separately configure and use a remote.

This is not a promise that all AI processing happens locally. Your selected assistant can read relevant files and send their contents or tool results to its model provider. Its settings, account terms and data policies govern that processing. External sources such as Todoist or Linear have separate accounts and policies.

## What you choose

- Which vault the assistant opens and can access.
- Which optional services and credentials you connect.
- Whether to invoke a workflow and what scope to give it.
- Whether to approve proposed task, workflow-installation or external changes.
- How to back up the workspace and where, if anywhere, to sync it.

Skill instructions provide workflow boundaries; they are not a substitute for host permissions or access controls. Configure the assistant's filesystem and tool permissions to fit the information it handles.

## Instructions and completion decisions

The workspace's `AGENTS.md` and `CLAUDE.md` are human-owned. Review their content yourself; an update must not silently replace your rules. The supplied starter reflects this candidate's structure and rules; [existing workspace instructions need a separate review](known-limitations.md) when adopting new workflows.

An assistant must not infer that a task, project or goal is complete simply because work appears finished. It can present the evidence and request your decision. A direct human completion statement is the authority to record that change.

## Captured workflows

`capture-workflow` prepares a reusable package outside the installed plugin. It shows the full package and proposed installation targets before installation. Generated packages must omit credentials, raw browser payloads, screenshots, personal information, customer identifiers and machine-specific paths.

The staging directory is selected from `AI_OS_WORKFLOW_ROOT`, `${XDG_DATA_HOME}/ai-os-lite/workflows`, or `~/.local/share/ai-os-lite/workflows`. You can provide additional private terms through the local `AI_OS_PRIVATE_PATTERN_FILE` denylist.

## Backups and issue reports

Back up your vault before applying an update or testing a migration. Git does not include ignored files automatically; preserve any needed attachments and private configuration separately.

When reporting an issue, share a minimal synthetic example, versions, the command used and redacted error output. Never attach an entire personal vault, credentials or private task descriptions. For a security-sensitive issue, use the private reporting route described in [community and support](community.md).
