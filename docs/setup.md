# Set up a first workspace

Your AI-OS workspace lives directly in `~/AIOS` by default. It is a folder of notes and context you own, with no extra `Vault/` folder. The AI-OS Lite source checkout is the software that prepares and works with it; keep the two directories separate.

## Before you start

For the documented local helper path, have Git, Bash, Python 3.10+ and `jq` on your PATH. Install and authenticate Claude Code or Codex using that assistant's own setup instructions. Its account or subscription is separate from AI-OS Lite. Obsidian is optional; a supported assistant can work directly with your files.

Get AI-OS Lite, which includes workspace setup, starter content, templates and skills:

```bash
git clone https://github.com/RS42-AI/ai-os-lite.git
cd ai-os-lite
```

If already downloaded, open a terminal in that `ai-os-lite` directory. You do not need a separate Vault Setup Kit checkout.

You can ask your assistant to guide these steps: “Read the setup guide, check the prerequisites and help me create my AI-OS workspace at ~/AIOS. Explain proposed installation changes and preserve existing files.” This is guided use of the installer; `setup-context` is the later conversation that personalizes your notes.

## Review the license

Before setup changes files or assistant configuration, the person using the
workspace reads the complete license, types YES and their full name, and chooses
personal or organizational capacity. Organization representatives also state the
organization's legal name and confirm authority. Run this step yourself in an
interactive terminal; an assistant cannot accept for you. A decline or incomplete
response leaves setup files unchanged. Earlier private draft acknowledgments
do not accept this license; a new explicit agreement is required. See
[license agreement and local records](license-acceptance.md).

## Install the workspace and skills

Choose the assistant you have installed:

```bash
AI_OS_LITE_MARKETPLACE="$PWD" bash setup/setup.sh --agent=codex "$HOME/AIOS"
# Or use --agent=claude for Claude Code, or --agent=both for both clients.
```

This creates starter files and installs the selected assistant's skills from this checkout. It does not install Obsidian plugins or configure MCP unless you request them. On macOS, the chosen assistant CLI must already be installed. Sign-in remains that assistant's own flow.

An explicit workspace path overrides the new-install default. Setup does not search for or move older vaults; keep using their explicit locations. The `AIOS/` folder itself contains your notes and workspace instructions. For a separate trial, pass another empty folder explicitly.

The helpers change the selected assistant's user-level plugin configuration; those assistant-managed files stay outside the vault. Use only the client/profile you intend to configure. The marketplace is `ai-os-lite-marketplace` and the plugin is `ai-os-lite@ai-os-lite-marketplace`; avoid enabling duplicate copies from different sources. Confirm the installed version and source, then start a fresh assistant session with `~/AIOS` (or your chosen workspace) as its working directory. Files being present do not prove the skill loaded successfully.

For separate steps or offline workspace creation:

```bash
bash setup/setup-vault.sh "$HOME/AIOS"
AI_OS_LITE_MARKETPLACE="$PWD" bash setup/setup-codex-plugins.sh "$HOME/AIOS"
# Or use setup/setup-claude-plugins.sh for Claude Code.
```

The vault-only step makes no network calls, installs no assistant and initializes local Git without changing your Git identity or committing for you. `setup.sh --agent=none` also selects vault-only setup.

Read `Personal/2. Projects/Vault-Setup/Vault-Setup.md` using your assistant or editor. Review the instruction files yourself: the supplied starter reflects this candidate, while [existing workspace instructions remain yours](known-limitations.md). The guided workflow must surface conflicting rules and pause affected writes for your decision.

## Add context through a short conversation

Invoke `/ai-os-lite:setup-context` in Claude Code or ask Codex `Run $setup-context.` Choose one outcome you would like help with, use a fictional example, or skip personalization.

The workflow reads your existing instructions and notes, then helps connect the outcome to an area, a goal, a bounded project and one next task. It reuses matching records, asks for missing choices and previews note contents and destinations before approved writes. It does not invent goals, dates or commitments to fill a template. Adding an area can require a separate human-approved instruction change.

Once you approve saving progress, you can resume later from that record in your workspace. Your notes provide context for subsequent work; a Morning Brief, project refresh or reusable workflow is a later use of that context. The three manual starter tasks remain available if you prefer them, and completing them is your decision.

## Optional Obsidian and integrations

Open the same workspace as a vault in Obsidian if you want its editor and dashboard views. To download the supplied community plugins, close Obsidian first and explicitly opt in:

```bash
AI_OS_LITE_MARKETPLACE="$PWD" bash setup/setup.sh --agent=codex --with-obsidian-plugins "$HOME/AIOS"
```

Review and enable selected plugins after reopening Obsidian. Downloaded files and working plugins are separate checks. Existing plugin settings are preserved.

Claude's optional Obsidian MCP/QMD setup uses `--with-obsidian-mcp` with `--agent=claude` or `--agent=both`. It requires Obsidian running with Local REST API and MCP Tools enabled, plus its local API key. Add `--with-obsidian-plugins` as well if those plugins are absent. Codex can read files directly; no automatic Codex MCP configuration is claimed. Todoist, Linear and calendar services require separate authorization and are not prerequisites.

An exit code of `2` means a requested assistant or integration step is incomplete. Keep the workspace, read the component result and retry the named helper. Do not treat a partial install as successful skill activation.

## Windows and WSL

The included [PowerShell entry point](../setup/setup-windows.ps1) provisions WSL2, prerequisites and the selected assistant CLI. It defaults to `$env:USERPROFILE\AIOS` on the Windows filesystem, usable by Windows editors including optional Obsidian. Use `-VaultPath "D:\My Notes\AIOS"` to select another local Windows folder. WSL translates the actual path; relative paths and network shares are rejected. It requires administrator access and may require a reboot. Obsidian plugins and MCP require explicit `-WithObsidianPlugins` and `-WithObsidianMcp` switches; the latter requires Claude.

Keep the full local package together: the entry point reads its license before provisioning and then runs that same checkout through WSL. It does not fetch a different branch after acceptance. A detached PowerShell script or the retired `-KitRepo` override is insufficient. This path has not been verified on a real Windows device; follow the [Windows checklist](../setup/docs/windows-pilot-checklist.md) and keep provisioning, authentication and optional integrations as separate results.

## Check the result

Use the [first-use acceptance guide](first-use-acceptance.md) to distinguish installed files, loaded skills and optional personalization. Try the [Morning Brief example](first-use.md) if useful. For an existing vault, use [transition guidance](existing-users.md) before running setup against real notes.
