# Move from Vault Setup Kit to the consolidated package

Your existing vault remains the source of truth. New installs default to `~/AIOS`, but that does not relocate an existing vault. Always pass the existing location explicitly to update and helper commands; `--update` without a path fails before writing. No old vault is discovered, copied or moved automatically. The change is where setup and workflow updates come from: `RS42-AI/ai-os-lite` now holds both. Keep the old Kit checkout until you have verified the transition. The old repository is not redirected, archived or deleted by this candidate.

## 1. Protect and inspect the current vault

Back up or commit the vault. Close Obsidian while changing plugin configuration. Identify your actual vault path, edition and existing Claude/Codex plugin source. Keep customized instructions, templates, community-plugin settings and project content. A package update alone does not migrate vault content.

Obtain the reviewed AI-OS Lite candidate or issued release in a separate source directory. For the planned replacement history, use a fresh checkout from its announced destination; do not pull or merge it into an old checkout. Keep the old source and workspace backups private until verification is complete. From that checkout's root:

```bash
bash setup/setup-vault.sh --update "/absolute/path/to/MyVault"
```

This changes `.vault-kit-path` to the new `setup/` folder, installs a missing update command, copies missing supported starter files and creates missing project containers. Existing files and instructions remain unchanged. An existing customized or older update command is preserved; compare it with `setup/commands/update-structure.md` before replacing it yourself. The updater skips duplicate Personal starter content while the old Personal layout is present.

## 2. Preview existing-content migration

The helper recognizes established project hubs; it does not guess that ordinary folders are projects. Generate a complete preview:

```bash
python3 setup/tools/project_structure.py plan \
  --vault "/absolute/path/to/MyVault" \
  --output "/absolute/path/to/MyVault/.vault-structure-preview.json"
```

Read that JSON before approval. It lists exact moves, new directories, path references to update, collisions, unknown legacy roots and an `approval_token`. A collision, symlink, binary/HTML artifact consumer or instruction-file reference blocks application. Custom HTML workspaces are preserved and require their own owner-reviewed update; this package does not install or refresh them. Unknown Personal roots remain untouched. Resolve instruction changes yourself; the helper will never rewrite them.

After the owner approves that exact preview, use its unchanged token:

```bash
python3 setup/tools/project_structure.py apply \
  --vault "/absolute/path/to/MyVault" \
  --plan "/absolute/path/to/MyVault/.vault-structure-preview.json" \
  --approval-token "TOKEN_FROM_THE_REVIEWED_PREVIEW"
```

A stale source, destination, plan or reference stops the operation. Successful application prints a receipt path and retains local backups. Generate the preview again: no remaining moves or missing directories means the structural transition is complete. This does not prove all templates, instructions or integrations are current; review those separately using the applicable structure-update document.

## 3. Verify before removing old sources

Open representative projects and their links in Obsidian. Confirm task and journal content, customized area names, private files and instructions are preserved. Keep the receipt and backup until you are satisfied. To reverse an unchanged migration:

```bash
python3 setup/tools/project_structure.py rollback \
  --vault "/absolute/path/to/MyVault" \
  --receipt "/absolute/path/to/RECEIPT.json"
```

Rollback refuses to overwrite files edited after application. Review any refusal rather than forcing it.

From the same reviewed AI-OS Lite checkout, update the selected assistant through
the gated local-package wrapper, using the existing workspace's explicit path:

```bash
bash setup/setup-codex-plugins.sh "/absolute/path/to/MyVault"
# Or, for Claude Code:
bash setup/setup-claude-plugins.sh "/absolute/path/to/MyVault"
```

A changed license requires the person's new explicit review. These wrappers
register the current checkout as the source for `ai-os-lite-marketplace` and
install `ai-os-lite@ai-os-lite-marketplace`. A marketplace override must resolve
to that same checkout. Confirm the client's registered source, installed version
and enabled state, then start a fresh session. If an older registration conflicts,
review its replacement in that client; do not silently fall back to a remote
source or run duplicate active installations. Keep the reviewed checkout available
while the client uses it.

No task, project or goal is marked complete by this transition. Any existing user's machine requires its owner's separate approval and actual-machine verification.
