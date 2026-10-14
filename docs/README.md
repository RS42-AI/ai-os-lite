# AI-OS Lite documentation

AI-OS helps you organize your knowledge and put it to work with AI. Start with a small workspace and one useful action, then connect more sources as you need them.

1. [Set up your AI-OS workspace](setup.md).
2. [Personalize your context, or skip](setup.md#add-context-through-a-short-conversation).
3. [Understand the capabilities and requirements](capabilities.md).
4. [Review your data and control boundaries](data-and-control.md).

For an existing workspace, begin with [transition and updates](existing-users.md). For a failed or partial install, use [troubleshooting and known limitations](known-limitations.md).

Other references:

- [Clean first-use acceptance](first-use-acceptance.md)
- [Optional Morning Brief example](first-use.md)
- [Community and support](community.md)
- [Contribution guidance](contributing.md)
- [Future recording outline](recording-outline.md)
- [Setup component](../setup/README.md)
- [Structure update mechanism](../setup/docs/architecture/update-channel.md)
- [Windows owner-run checklist](../setup/docs/windows-pilot-checklist.md)

## Package layout

| Location | Responsibility |
|---|---|
| `plugins/ai-os-lite/` | Eleven assistant skills and their deterministic helpers |
| `setup/` | Workspace installers, starter notes, templates and structural update tools |
| `docs/` | Product setup, examples, usage and transition guidance |
| `tests/`, `fixtures/` | Workflow regression checks and synthetic examples |

The workspace you create is separate from this source checkout. Keep your personal notes out of the public repository.
