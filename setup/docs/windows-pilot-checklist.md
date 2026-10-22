# Windows and WSL first-use checklist

This path is **unverified on an actual Windows device**. Complete the checks below on a disposable test workspace before relying on it for your own notes. Record failures and workarounds; installed files, command mocks and a successful script exit do not prove working plugins or an authenticated assistant.

## Record the environment and source

- [ ] Record Windows edition/build, PowerShell version, WSL version/distro, Python version, and Obsidian version only if testing that option.
- [ ] Record the AI-OS Lite repository commit and selected assistant version. Do not record credentials, API keys or private account details in a public report.
- [ ] Use an empty test destination. The automatic installer defaults to `$env:USERPROFILE\AIOS`; use `-VaultPath "D:\AIOS Test"` or the manual candidate path for a separate test folder. Existing vaults are not discovered or moved.
- [ ] Test core setup without Obsidian first. If testing optional community plugins, install Obsidian for Windows and close it during their download.

## Choose the source to test

The PowerShell entry point reviews the license in its full local checkout, then translates that checkout's path into WSL and runs its bundled Bash helpers. It does not clone, pull or select another branch. Keep the package together and use its LF-normalized source files. Record the selected commit, any local changes, package version and license hash; a different checkout does not verify the proposed release. A detached PowerShell file and the retired `-KitRepo` override are unsupported.

For the selected local candidate or issued release, run in elevated PowerShell from that checkout's root:

```powershell
.\setup\setup-windows.ps1 -Agent codex
# Use -Agent claude or -Agent both only for those assistant paths.
# To override the default, add: -VaultPath "D:\AIOS Test"
```

- [ ] Review the complete local license in the console before provisioning. A draft rehearsal is nonoperative. Confirm decline or an incomplete response stops before setup writes; assistants must not supply the response.
- [ ] If WSL is absent, the installer completes WSL installation, requests a reboot and stops. After reboot and the distro's first-run setup, rerun the same command as administrator.
- [ ] Verify the printed Windows path matches the actual profile or explicit `-VaultPath`; test a path with spaces and an apostrophe. Confirm WSL translation resolves the same folder and an unrelated legacy vault remains untouched.
- [ ] The second run detects the configured distro and does not repeat installation or request an unnecessary reboot.
- [ ] Prerequisite installation succeeds. In WSL, confirm `git`, `curl`, `python3`, `jq`, `file`, `node` and the selected assistant command work. Python must be 3.10 or newer.
- [ ] Keep the existing sudo policy. The WSL user's password may be requested; no permanent passwordless sudo should be added.

Alternatively, to test only the Bash steps, prepare WSL and its prerequisites separately, then use a separate checkout of the exact selected package inside WSL. From that checkout's root:

```bash
git rev-parse HEAD
python3 --version
jq --version
# Replace <WindowsUser>; choose a folder that contains no real notes.
vault_path='/mnt/c/Users/<WindowsUser>/AI-OS-Lite-Test'
bash setup/setup-vault.sh "$vault_path"
# Optional later, with Obsidian closed:
# bash setup/setup-plugins.sh "$vault_path"
```

The manual path tests the selected package's Bash steps. It does not by itself test the PowerShell installer, its reboot/resume behavior or authentication. Record those outcomes separately.

## Optional: open the vault in Windows Obsidian

- [ ] Open the Windows path corresponding to the WSL destination, for example `C:\Users\<WindowsUser>\AI-OS-Lite-Test`. The automatic default is `$env:USERPROFILE\AIOS`, or the explicit `-VaultPath`. Use the Windows filesystem path printed by the installer, not a `\\wsl$\...` share.
- [ ] Confirm the starter hub and all three onboarding tasks are visible under `Personal/2. Projects/Vault-Setup/`.
- [ ] In Settings → Community plugins, review restricted mode and enable the plugins you intend to test. A populated enabled-plugin JSON file alone is not acceptance.
- [ ] Confirm Templater, Dataview and the other selected plugins actually load without an error. Record each plugin version and any plugin not tested.
- [ ] Edit a non-sensitive test note in Obsidian and verify the change is visible from WSL; edit that test note from WSL and verify Obsidian notices it.

## Activate the exact candidate in an authenticated assistant

Use the assistant's own sign-in flow. Authentication is a separate prerequisite from downloading its CLI. Do not put credentials in shell commands, screenshots or public logs.

For the manual candidate path, from the candidate repository root inside WSL:

```bash
AI_OS_LITE_MARKETPLACE="$PWD" bash setup/setup-codex-plugins.sh "$vault_path"
# Or, for Claude Code:
AI_OS_LITE_MARKETPLACE="$PWD" bash setup/setup-claude-plugins.sh "$vault_path"
```

These helpers change the selected assistant's user-level plugin configuration and use this reviewed local checkout as the marketplace source. The optional override shown above must resolve to that same checkout; a remote repository or different directory is rejected before client changes. Run them only in the test profile/account you intend to configure. If the client cannot install a local marketplace, record that failure; do not silently switch to the public release and call it candidate acceptance.

- [ ] Verify the marketplace name is `ai-os-lite-marketplace`, its source is the reviewed local checkout, and the installed `ai-os-lite@ai-os-lite-marketplace` package version and enabled state match the test candidate.
- [ ] Start a fresh assistant session in the test vault. Confirm AI-OS Lite's skills, including `setup-context`, are actually loaded without Obsidian or MCP.
- [ ] Follow the [core first-use checks](../../docs/first-use-acceptance.md): inspect the correct workspace, choose to skip personalization and verify rerun preservation.
- [ ] If testing guided personalization, use a fictional outcome and verify approved notes, links and resumption separately.
- [ ] Optionally run the [Morning Brief example](../../docs/first-use.md) and record its own result.
- [ ] Confirm all three tasks remain `todo` and no external service or real vault was changed.

## Optional Claude Obsidian integration

Core workspace and skill setup does not require MCP or QMD. Only claim this integration if these additional checks pass.

- [ ] Enable Local REST API and MCP Tools in Windows Obsidian. Opt in with `-WithObsidianPlugins -WithObsidianMcp` for the automatic Claude path, then paste the Local REST API key only into its local PowerShell prompt. For manual setup, run `bash setup/setup-mcp.sh "$vault_path"` inside WSL and use its prompt. Keep the key out of receipts.
- [ ] Confirm the helper registered the API key without printing it. Do not copy an additional key snippet into configuration if registration already succeeded.
- [ ] In WSL, run `file "$vault_path/.obsidian/plugins/mcp-tools/bin/mcp-server"` and confirm Linux ELF output. A Windows executable or failed download is a failed integration.
- [ ] Run `claude mcp list`; then perform a live search for a unique non-sensitive phrase in the test note. Registration alone does not prove network connectivity or a successful search.
- [ ] If testing QMD, configure its test-vault collection, index it and prove a separate attributed search. A registered but unindexed server is not search acceptance.

## Record the result

Record the tested commit, environment, assistant, successful checks, skipped integrations, failures and workaround steps. Keep separate outcomes for PowerShell provisioning, authenticated skill activation, guided personalization, optional Obsidian, the optional Morning Brief and each integration. A partial pass must not become a blanket Windows-support claim.
