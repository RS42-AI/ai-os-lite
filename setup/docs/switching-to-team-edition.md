# Existing team-edition workspaces

AI-OS Lite now has one generalized setup for personal and internal business use. The old RS42-specific team installer has been retired. `--edition=team` stops before making changes; it does not convert or delete your workspace. The former `--edition=personal` option remains a compatibility alias, but new commands should omit it.

Keep your existing workspace private. Your notes, project names, areas and customized instructions remain yours. No organization receives access by installing or updating Lite. Collaboration uses separately connected shared destinations and the permissions you choose.

Before updating:

1. Back up your workspace and keep the old source checkout until you have verified the update.
2. Review [the existing-vault transition](existing-vault-transition.md), the new license and the structure updates that apply to your workspace.
3. From the new AI-OS Lite checkout, run the following with your existing workspace's exact path:

   ```bash
   bash setup/setup-vault.sh --update "/absolute/path/to/Existing Workspace"
   ```

4. Inspect the result. Update mode adds missing generalized starter files and project containers. It can add Personal folders alongside your existing work areas, but does not move or remove your content, rename areas/projects, or overwrite existing files. It does not replace or install missing `AGENTS.md` or `CLAUDE.md` files; instruction changes stay with the workspace owner.
5. Review any proposed structure migration before approving it. Connect collaboration destinations separately when you need them.

Do not delete and regenerate a workspace to switch editions, copy starter instructions over your own, or change existing notes' metadata merely because the installer changed. You may continue using an earlier version under the terms that came with it.
