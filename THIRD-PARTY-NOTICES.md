# Third-party software and services

The AI-OS Lite license covers material RS42 has the right to license. It
does not replace licenses or terms for the separate software and services
below. Installing them does not make them RS42 software.

## Separate applications and runtimes

Depending on the path you choose, setup uses locally installed Git, Bash,
Python and jq; Windows setup uses WSL/Ubuntu and Linux package tools, and
may install Node.js and an assistant CLI. Claude Code, Codex and Obsidian
are separate products requiring their own installation, accounts and terms.
The package does not include their application binaries.

Optional search and integration setup can download [Bun](https://bun.sh/),
[QMD](https://github.com/tobi/qmd) and the
[Obsidian MCP Tools server](https://github.com/jacksteamdev/obsidian-mcp-tools).
QMD may download separate model files. Consult the license and notices
shipped with the exact upstream release and model you install.

## Optional Obsidian plugins

The optional installer downloads selected release files from these upstream
projects. Their authors retain their rights; their own license and notices
apply to the downloaded files.

For a new installation, the installer resolves one release tag and preserves
that tag's root license/notice files and any release notice assets in the
plugin's `upstream-notices/` directory before installing runtime files.
`provenance.json` records the tag, source location and downloaded hashes.
Missing license files, incomplete notice downloads or an unsupported notice
layout stop that plugin's installation. Existing plugins and custom settings
are kept; their earlier notices are not audited or replaced on a rerun.
This preserves upstream root/release notices; it is not a full audit of every
dependency within an upstream bundle. Rate-limited or unavailable upstream
metadata can leave the optional plugin step incomplete and safe to retry.

| Plugin | Upstream project |
| --- | --- |
| Terminal | [polyipseity/obsidian-terminal](https://github.com/polyipseity/obsidian-terminal) |
| Linter | [platers/obsidian-linter](https://github.com/platers/obsidian-linter) |
| Templater | [SilentVoid13/Templater](https://github.com/SilentVoid13/Templater) |
| Dataview | [blacksmithgu/obsidian-dataview](https://github.com/blacksmithgu/obsidian-dataview) |
| Git | [Vinzent03/obsidian-git](https://github.com/Vinzent03/obsidian-git) |
| Local REST API | [coddingtonbear/obsidian-local-rest-api](https://github.com/coddingtonbear/obsidian-local-rest-api) |
| MCP Tools | [jacksteamdev/obsidian-mcp-tools](https://github.com/jacksteamdev/obsidian-mcp-tools) |
| Editing Toolbar | [PKM-er/obsidian-editing-toolbar](https://github.com/PKM-er/obsidian-editing-toolbar) |
| Excalidraw | [zsviczian/obsidian-excalidraw-plugin](https://github.com/zsviczian/obsidian-excalidraw-plugin) |
| Smart Connections | [brianpetro/obsidian-smart-connections](https://github.com/brianpetro/obsidian-smart-connections) |

An upstream URL does not substitute for a notice required by an upstream
license. Keep the notices that accompany those components when copying or
redistributing them. This list is not permission to relicense their files.
Smart Connections currently uses its own Smart Plugins License, including
restrictions on certain competing products; do not assume every plugin above
uses the MIT license or the AI-OS Lite terms. Review the exact downloaded terms
before separately distributing or integrating a plugin into another product.

## Development and display dependencies

Verification uses Bats, ShellCheck, jq, PyYAML and GitHub Actions tooling;
these are not bundled as runtime dependencies. README badges and charts
load from Shields and Star History. External services handle requests under
their own terms and privacy policies.

The package includes no supplied brand artwork or font binaries. Linked
research and documentation in starter notes remain their authors' work;
citation does not transfer ownership to RS42.
