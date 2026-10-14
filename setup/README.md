# Set up AI-OS Lite

This folder brings Vault Setup Kit's starter vault, templates, setup scripts and existing-vault updates into AI-OS Lite. Your vault stays separate from this source checkout. Use [the product README](../README.md) for capabilities and examples.

## Start with local files

Install Git and Python 3.10 or later. Clone this repository, then run from its root:

```bash
bash setup/setup-vault.sh "$HOME/AIOS"
```

Without a path, fresh setup uses `~/AIOS`. An explicit path always selects that folder instead; setup does not discover, move or copy an older vault. `AIOS/` itself holds your notes and workspace instructions; no `Vault/` subfolder is created. Keep the product checkout separate.

This creates the starter Markdown files and empty project folders without network calls or agent software. Use your assistant or Markdown editor to read `Personal/2. Projects/Vault-Setup/Vault-Setup.md`. You can use a fictional project while learning; personal disclosure is optional. The initial Git repository is created without changing your Git identity or committing on your behalf. Make your own first backup commit when ready.

One generalized setup supports personal and internal business use. The old RS42-specific team installer has been retired. Existing team-edition workspaces remain yours; follow the [existing team-workspace guidance](docs/switching-to-team-edition.md) before updating.

## Workspace and assistant skills

From the repository root, choose your already installed assistant:

```bash
AI_OS_LITE_MARKETPLACE="$PWD" bash setup/setup.sh --agent=codex "$HOME/AIOS"
# Or --agent=claude, --agent=both, or --agent=none for vault files only.
```

Assistant plugins remain in the selected assistant's user-level configuration; they are not moved into `AIOS`. The script prepares the vault and invokes the selected assistant's plugin installer with this reviewed local checkout as its marketplace source. An optional `AI_OS_LITE_MARKETPLACE` value must resolve to this same checkout; remote sources and other directories are rejected. That CLI must be installed and available on your PATH; authentication uses its own sign-in flow. Open the workspace in a fresh assistant session and invoke `setup-context` to explore one outcome, use a fictional example or skip. No Obsidian application or external tracker is required.

## Optional integrations

Add `--with-obsidian-plugins` to download the supplied community plugins; close Obsidian first, then review and enable them after reopening. Add `--with-obsidian-mcp` with `--agent=claude` or `--agent=both` only if you want Claude's Obsidian MCP/QMD setup. That step requires running Obsidian, enabled Local REST API/MCP Tools plugins and its local key. Use both switches if those plugins are absent. Neither integration runs by default.

The vault-file step can succeed while an integration fails. Exit code `2` means a requested assistant or integration step remains incomplete; the output names the exact script to rerun. Missing CLIs, failed downloads and marketplace failures never count as a successful integration. Run the workflow in a fresh agent session to verify availability; scripted checks do not prove a live service connection.

Existing plugin settings are preserved byte for byte. The enabled-plugin list keeps your entries and adds only successfully installed plugins. Downloads require valid HTTP responses, a matching plugin manifest and a nonempty JavaScript asset. Rerunning retries failed downloads. Invalid existing JSON and symlinks stop the relevant step for owner review.

## Existing vaults and earlier Kit users

Keep the existing vault and old checkout. Update mode requires its explicit path, for example `bash setup/setup-vault.sh --update "/absolute/path/to/Existing Vault"`; omitting the path stops before writes. The new-install default does not relocate existing notes. Clone or update AI-OS Lite separately, then follow [existing-vault transition](docs/existing-vault-transition.md). Do not point a new clone over your vault or copy starter instructions over customized instructions.

`AGENTS.md` and `CLAUDE.md` remain human-owned. The packaged starter instructions reflect this candidate's structure and rules. Compare your existing instructions with the new defaults when adopting new workflows. Setup never modifies existing copies, and update mode never installs missing instruction files automatically.

## Windows

The PowerShell entry point uses WSL2 and stores the vault on the Windows filesystem, also usable by optional Obsidian:

```powershell
.\setup\setup-windows.ps1 -Agent codex
```

The default is `$env:USERPROFILE\AIOS`, translated by WSL rather than assuming a username or `C:` drive. Use `-VaultPath "D:\My Notes\AIOS"` for a custom local Windows folder. Spaces and apostrophes are supported; relative paths and network shares are rejected. No existing vault is discovered or moved.

Use `-WithObsidianPlugins` and, for Claude, `-WithObsidianMcp` only when you want those integrations. It requires an elevated PowerShell session and may require a reboot while enabling WSL. Keep the full reviewed checkout together. The entry point presents its local license before provisioning, then runs that same checkout through WSL; it does not clone or pull another source. A detached script and the retired `-KitRepo` override cannot select a different package. [The Windows pilot checklist](docs/windows-pilot-checklist.md) is required for actual-machine acceptance. This candidate's isolated macOS tests are not Windows acceptance.

## Verification and development

```bash
bats setup/test/
python3 -m unittest discover -s setup/test -p '*_test.py'
shellcheck setup/*.sh setup/test/test_helper.bash
```

[Update behavior](docs/architecture/update-channel.md) explains the separate package and vault updates. [Structure migrations](structure-updates/) carry detection, review, verification and rollback instructions. No setup command migrates a real user's existing content without the separately approved migration preview.
