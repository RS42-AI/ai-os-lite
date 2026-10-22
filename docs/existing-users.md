# Existing users: one public package, the same vault

Vault Setup Kit is being consolidated into `RS42-AI/ai-os-lite`. The setup source now lives in `setup/`; the assistant package keeps its `ai-os-lite` identity. Your notes stay in your existing vault. New installs default to `~/AIOS`; that default does not move, copy or discover an older vault.

This private candidate does not migrate any real user or change public repositories. Keep a private backup of your existing checkout and workspace until you have verified the replacement. If you already have AI-OS Lite, do not install a second active copy alongside it. Review and explicitly accept the license supplied with any replacement; older acceptance or a family relationship does not supply consent to new terms.

## Choose the change you need

| Your situation | Next step |
|---|---|
| You only use the Lite plugin | Follow the final release's installation instructions, verify the selected source and license, and replace the old active plugin registration after backing it up. Reopen the workspace in a fresh session. |
| You have a vault created by Vault Setup Kit | Back up the vault, select the reviewed Lite source, then run additive setup in update mode. |
| You customized templates or instructions | Compare proposed changes manually. Existing files remain yours; a package update does not replace them. |
| You use an older Personal project layout | Preview the structure migration. Moving files and repairing references is a separate, approved action. |
| You have a custom HTML workspace | Preserve it. This candidate does not install or refresh the separate HTML workspace family. |

From the selected Lite source checkout:

```bash
bash setup/setup-vault.sh --update "/absolute/path/to/MyVault"
```

The existing path is required: omitting it stops before writes. Use the same explicit path for optional integration helpers. Setup and update scripts use that path argument; they do not use `PERSONAL_OS_VAULT`.

Workflow helpers also default to `~/AIOS`. To keep working in an existing vault, pass its path to the helper or set `PERSONAL_OS_VAULT` to that location for the assistant session. No old vault is selected automatically and no files are moved. Assistant configuration stays in the client's own `~/.claude` or `~/.codex` locations, separate from your vault.

The update records the new `setup/` location, adds missing supported files and project containers, and preserves existing content. It does not silently replace `AGENTS.md`, `CLAUDE.md`, customized templates or a customized update command. It also does not mark tasks, projects or goals done.

Use the [canonical transition procedure](../setup/docs/existing-vault-transition.md) for the exact migration preview, approval, verification and rollback commands. Do not apply a migration just because additive setup succeeded.

## Package updates and vault updates are different

A newer checkout or assistant plugin changes the tools you run. Your vault may still contain older instructions, templates and structure. Review the [update channel](../setup/docs/architecture/update-channel.md) and applicable [structure updates](../setup/structure-updates/) before changing those files.

The supplied starter instructions reflect the candidate's structure and rules. Your existing instructions remain unchanged; [compare them with the new defaults](known-limitations.md) and resolve conflicts before using affected workflows.

## A replacement source is a fresh checkout

The planned release uses a fresh source history. Once its final destination is announced, obtain a new checkout from that official destination rather than pulling or merging it into an old source checkout. Do not push old branches or tags into the replacement. This changes package history, not the contents of your workspace, and does not cancel licenses on copies obtained earlier.

The old Kit no longer needs to be maintained as a second product. Any repository deletion, replacement or relocation notice is a separate human release action. Preserve recovery copies privately. Follow the [legacy team-workspace guidance](../setup/docs/switching-to-team-edition.md) for an existing team workspace; setup does not transform it into a personal workspace.
