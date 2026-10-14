# Capabilities and integrations

AI-OS Lite supplies workflow instructions for a supported assistant. The assistant needs access to your workspace and permission to use any external source you connect. A skill being present does not mean its optional integrations are configured.

## The local starting point

| Component | Purpose | Required for core setup? |
|---|---|---|
| Workspace files | Markdown notes, project hubs, tasks and templates | Yes |
| Git, Bash and Python 3.10+ | Setup and deterministic helpers | Yes |
| `jq` | Some setup integrations and Morning Brief context assembly | Included in the documented prerequisites; offline vault creation does not need it |
| Obsidian | Browse notes and display dashboard views | No; the assistant can use files directly |
| Claude Code or Codex | Use the skills and workspace context, then write approved results | Yes for the assistant workflow; not for the deterministic example |
| AI-provider account | Authenticates your chosen assistant | Yes for the assistant workflow |

The starter material includes onboarding tasks and a curriculum about working with agents. Those reference notes discuss broader ideas; their presence does not claim that every architecture they describe is implemented in Lite.

## The eleven skills

| Skill | Input | Output and boundary |
|---|---|---|
| `setup-context` | One chosen outcome, existing workspace rules and records | A previewed area/goal/project/task example and resumable progress; fictional use or skipping allowed |
| `start-day` | Available tasks, recent work, optional connected sources | A Morning Brief; missing sources must remain visible |
| `process-morning` | Optional morning input and current context | A daily plan and proposed task actions; task changes require the applicable approval |
| `prep-evening` | The day's evidence | An optional Evening Entry draft |
| `process-evening` | Optional evening input | A summary and proposed tomorrow actions |
| `project-sync` | A project hub and its evidence | Refreshed status; evidence does not authorize marking work done |
| `write-note` | Requested note content and workspace conventions | A routed note with lint output; contract coverage is incomplete |
| `vault-audit` | Workspace instructions and files | Findings against supported rules; a clean result is not a complete semantic audit |
| `vault-commit` | Local Git changes | Reviewed, grouped commits; no automatic production release |
| `capture-workflow` | A demonstrated bounded process | A sanitized skill package and approval preview before installation |
| `vault-config` | Workspace configuration | Source/tool-selection guidance used by the other skills |

## Optional sources

| Integration | What it adds | Setup boundary |
|---|---|---|
| Todoist | External tasks and approved task actions | Uses the `td` executable from `@doist/todoist-cli`; a similarly named third-party CLI is not interchangeable. Install and authenticate separately. |
| Linear | Project and issue evidence, approved issue actions | Requires an accessible, authorized Linear connector/MCP server and a workspace mapping |
| Obsidian CLI | Direct access to supported Obsidian functions | Optional for the Morning Brief task scan; the filesystem path must still be accessible |
| Obsidian community plugins | Template rendering, queries and optional local integrations | Downloading files is separate from enabling plugins in Obsidian |
| Obsidian Local REST API / MCP | Local application integration | Requires the plugin, API key and assistant-specific wiring; no blanket Codex MCP setup is claimed |
| Calendar, email, meeting tools | Additional evidence when connected | Requires separate accounts, connectors and authorization; none is required for the starter example |
| External scheduler | Repeated invocation | Not installed or configured by Lite |

Refer to the skill's source instructions for its exact workflow and available fallbacks. Do not install every integration just to try the package.

## Not included as operating services

Lite does not provide a hosted team, continuous universal capture, a shared business backend or an unattended agent service. It does not guarantee the accuracy of generated summaries. You review the assistant's evidence and decide which actions it may take.
