# Clean first-use acceptance

The core release succeeds when a new user can create the intended portable workspace and install and load the Lite skills in a supported assistant. Personal disclosure, a Morning Brief, Obsidian and external integrations are not required. Test personalization and optional applications separately.

Use an empty synthetic workspace and the exact release commit. A helper test, existing login or installed application does not establish a clean installation. Redact account information and credentials from receipts.

## Record before starting

Record the repository commit, operating system, assistant/client version, plugin version and source. State whether testing a local candidate or the public release, and whether the client profile is fresh or existing. Record Obsidian only if included in the optional test. Keep automated tests and live installation results separate.

## Core installation

1. Follow [setup](setup.md) with one supported assistant in a clean test profile, using its real sign-in flow. Do not substitute a cached workshop plugin for the candidate.
2. Verify the new workspace contains its routed folders, starter notes, templates and instruction files. Confirm it is separate from the source checkout and contains no private source content.
3. Confirm the selected assistant's installed version and marketplace source match the candidate. Record failures rather than silently switching to a different source.
4. Start a fresh authenticated assistant session in the test workspace. Confirm it discovers the Lite skills, including `setup-context`, and can read the starter context directly without Obsidian or MCP. Installation, enabled state and successful skill loading are separate checks.
5. Ask for setup-context, then choose to skip personalization. The assistant must respect that choice; a correctly installed workspace does not require invented goals or completed starter tasks.
6. Rerun workspace setup and confirm existing human content and settings are preserved. Keep the original three starter task statuses unchanged.

The setup helpers modify user-level plugin configuration. Use only the profile you intend to configure. An isolated filesystem or simulated-client test remains a helper test, even when it passes.

## Optional guided personalization

1. Choose a fictional outcome. Check that the assistant reads actual workspace rules and existing records before proposing an area, goal, project and task.
2. Provide only the missing choices you want to make. Confirm no dates, targets, areas or commitments are invented, and that proposed destinations and note contents are previewed.
3. If instructions conflict with templates or routing, verify affected writes pause for a concrete human decision. Instruction-file edits need their separate approval; ordinary note approval does not cover them.
4. Approve a valid example, then inspect the actual saved links, routing and note lint results. If instruction review prevents saving it, record that limitation rather than claiming a pass.
5. Resume the conversation and confirm it reuses saved context without duplicate records. Check that no real task was inferred complete and no global agent memory was created.

A successful simulated conversation exercises the skill's behavior. It does not prove a fresh authenticated installation.

## Optional worked example and applications

The [Morning Brief example](first-use.md) checks local task discovery, dependency order, skipped sources, a useful proposed next step and a correctly saved note with the human-input region preserved. Keep all three starter tasks `todo`. This demonstrates one use of context after setup.

If testing Obsidian, open only the test workspace, verify its hub and links, and check an edit in each direction between the editor and filesystem. For community plugins, close Obsidian during installation, reopen it, review restricted mode and verify each selected plugin actually loads. Record versions and failures; configuration files alone are insufficient.

Calendar, task trackers, MCP and QMD need separate live checks if claimed. Core first use must work without them.

## Platforms and receipt

Run the [Windows/WSL checklist](../setup/docs/windows-pilot-checklist.md) on an actual Windows device before claiming that path is verified. A parser check or mocked Windows command is not Windows acceptance.

Record pass, fail or not tested separately for exact candidate selection, workspace structure, fresh authenticated session, skill discovery, skip behavior, rerun preservation, guided personalization and each optional example/application/integration. Include reproducible failures and redacted evidence. Do not hide a skipped core check behind an overall success label.
