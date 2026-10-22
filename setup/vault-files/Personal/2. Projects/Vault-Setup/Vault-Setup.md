---
date: 2026-05-09
type: project
status: draft
area: personal
project: vault-setup
goal:
tags:
  - onboarding
  - vault
  - agentic-systems
---

## Overview

### Welcome — This Is Your Operating System

This vault is a **human-AI operating system**: a place where you and an AI assistant collaborate on work, projects, and life using the same files, structure, and shared context.

Your files hold context that you can give to your assistant across sessions: what matters, what you are working toward and what has already been decided. Use them directly with your assistant or any Markdown editor; Obsidian is optional for browsing and dashboard views.

### The One-Sentence Idea

> Keep useful context in files you own, and give your assistant a consistent way to put it to work.

### How This Is Structured

The vault uses a **hub-and-spoke** layout. Hubs organize related notes through frontmatter properties. Their dashboard views auto-populate when displayed in Obsidian.

Three properties route every note:

- **`type`** — what kind of note (`note`, `task`, `project`, `devlog`, `meeting`, `goal`, and so on)
- **`area`** — which responsibility it belongs to (`personal`, `health`, `personal-finance`, and so on)
- **`project`** — which project, if any (a slug such as `home-buying` or `vault-setup`)

The full taxonomy and decision tree live in `AGENTS.md` at the vault root. That is also the file AI coding agents read to understand how to work inside the vault. `CLAUDE.md` imports it for Claude Code.

### Curriculum

Optional background reading. You do not need to finish it before using the workspace. These notes discuss broader architectures; Lite provides manually invoked skills, not an always-on agent team.

#### 1. The Thesis — Why This Exists

- [[AI-Native Architecture - Business Logic as Agent Instructions]] — why instructions in Markdown are a real architecture.
- [[Human-AI Trust Boundary Architecture for 24-7 Agent Systems]] — where humans approve, where AI acts, and how to design that boundary.

#### 2. The Architecture — How Agents Are Organized

- [[Multi-Agent Architecture Patterns]] — manager, handoff, and specialist patterns.
- [[Agentic Department Architecture Patterns - Reusable Framework for AI-Native Operations]] — how to structure agents like a real organization.
- [[Overview of AI Agent Systems and Their Fundamental Overlap]] — how common agent frameworks relate.

#### 3. Where It Lives — The Vault as OS

- [[AI Workstation Organization - Filesystem and Vault Mapping Architecture]] — how the filesystem layout supports agents.
- [[Personal OS Daily Lifecycle Architecture - The Executive Meeting Model]] — the Morning Brief, workday, and optional Evening Entry loop.

#### 4. The Implementation Patterns

- [[Closed-Loop Systems - Feedback Property and Trigger Independence]] — the design rule that makes autonomous loops reliable.
- [[Agentic Thinking]] — the shift from writing prompts to designing agent capabilities and expectations.

#### 5. Deeper Dive (Optional)


### First Steps

After installing the Lite skills, ask your assistant to run `setup-context`. It will help connect one outcome to an area, goal, project and next task using your actual workspace rules. Choose a fictional example or skip personalization. Review proposed notes before saving; instruction changes need a separate decision.

The following manual exercises remain available if you prefer to work through them yourself:

- [[Add my first project]] — practice the project-creation flow with a real or fictional example.
- [[Set up my first goal]] — anchor a project to an outcome.
- [[Set up my AGENTS.md]] — tailor the vault instructions to your areas, systems, and conventions.

### What "Done" Looks Like

Core setup is ready when the intended workspace files exist and your chosen assistant loads the Lite skills. Personalization, the curriculum and optional applications are separate choices. You decide when your own onboarding work is complete; the assistant must not infer completion from installed files.

---

## Current Status

These are the starter workspace files. Verify that your assistant loads the Lite skills, then choose guided context setup, a manual exercise below, or a later return. Existing examples remain until you decide to change them.

---

## Active Tasks

```base
filters:
  and:
    - type == "task"
    - project == "vault-setup"
    - or:
        - status == "todo"
        - status == "active"
views:
  - type: table
    name: Onboarding Tasks
    order:
      - file.name
      - status
      - priority
    sort:
      - property: priority
        direction: ASC
```

---

## On Hold

```base
filters:
  and:
    - type == "task"
    - project == "vault-setup"
    - status == "on-hold"
views:
  - type: table
    name: On-Hold Onboarding Tasks
```

---

## Completed Tasks

```base
filters:
  and:
    - type == "task"
    - project == "vault-setup"
    - status == "done"
views:
  - type: table
    name: Completed Onboarding Tasks
```

---

## Artifacts

Link working documents and other project outputs here, naming the authoritative
file or URL when copies exist.

*No artifacts linked yet.*

---

## Resources

```base
filters:
  and:
    - type == "resource"
    - project == "vault-setup"
views:
  - type: table
    name: Onboarding Resources
    order:
      - file.name
      - date
```

---

## Knowledge Notes

```base
filters:
  and:
    - type == "note"
    - project == "vault-setup"
views:
  - type: table
    name: Onboarding Knowledge Notes
    order:
      - file.name
      - status
      - date
```

---

## Dev Log

```base
filters:
  and:
    - type == "devlog"
    - project == "vault-setup"
views:
  - type: table
    name: Onboarding Sessions
    order:
      - date
      - file.name
      - session_topic
    sort:
      - property: date
        direction: DESC
```

---

## Meetings

```base
filters:
  and:
    - type == "meeting"
    - project == "vault-setup"
views:
  - type: table
    name: Onboarding Meetings
```

---

## Related Projects

- [[Personal]] — the starter personal-area dashboard.
