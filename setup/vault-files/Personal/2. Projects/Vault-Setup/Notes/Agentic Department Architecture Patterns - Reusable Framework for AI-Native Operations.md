---
date: 2026-02-23
type: note
status: capture
area: personal
project: vault-setup
tags:
  - multi-agent
  - architecture-patterns
  - ai-agents
  - business-automation
  - system-design
---

# Agentic Department Architecture Patterns - Reusable Framework for AI-Native Operations

## Core Idea

A **department pattern** groups agents by responsibility. Each group owns a domain, produces outputs, and hands work to other groups through defined interfaces. A department can represent a stage in a workflow, as well as a place to organize files.

The diagrams, names, tasks and schedules below are illustrative design examples. They are not measured results, universal rules or features installed by AI-OS Lite. Adapt them to the work, tools and permissions you actually have.

---

## Define Responsibilities and Handoffs

A list of agents such as website-agent, social-agent, email-agent and research-agent still needs answers to two questions:

1. **Ownership** — Which agent proposes the brand voice, and which person approves it?
2. **Information flow** — How does market research reach the content creator, and how is the handoff recorded?

Grouping related responsibilities gives you a place to define those interfaces:

```
┌─ DEPARTMENT A ─────┐     output/     ┌─ DEPARTMENT B ─────┐
│                     │ ──────────────► │                     │
│  Owns: domain X     │                 │  Reads: A's output  │
│  Writes: output/    │ ◄────────────── │  Owns: domain Y     │
│  Reads: B's output  │     feedback    │  Writes: output/    │
└─────────────────────┘                 └─────────────────────┘
```

One possible rule lets each department **read** approved outputs from other departments and **write** only to its own. Enforce that boundary through the tools or runtime when needed; a written instruction alone does not enforce access control or prevent concurrent-write conflicts.

---

## Start with the Responsibilities You Need

Begin with a workflow you can observe and review. One agent can handle several responsibilities; separate agents are useful only when their distinct context, tools or permissions justify the handoffs.

Consider splitting a group when its responsibilities overlap, its context becomes hard to manage, or its handoffs are difficult to verify. Measure whether the change helps. A coordinating agent may summarize work across groups, but adds its own context and review costs.

### An Example Grouping

The following three labels illustrate one way to divide work:

| Department | What It Owns | Output Type |
|-----------|-------------|-------------|
| **Build** (Product) | Everything the customer sees — website, product, brand, design | Assets, code, specifications |
| **Grow** (Growth/Marketing) | Getting in front of people — content, social, email, community | Content, campaigns, outreach |
| **Know** (Intelligence/Research) | Understanding the market — research, analysis, investor materials | Reports, databases, models |

These names and boundaries are optional. A software project might use Engineering, Marketing and Analytics; a consulting project might use Delivery, Business Development and Research. Choose groups that fit the actual work.

---

## The Pipeline Cycle

In this example, groups exchange outputs and feedback in a cycle:

```
        ┌──────────┐
        │   KNOW   │
        │ Research │
        │ Analysis │
        └────┬─────┘
   findings  │        ▲ traction data
   & data    │        │ & market feedback
             ▼        │
        ┌──────────┐  │  ┌──────────┐
        │   GROW   │──┘  │  BUILD   │
        │ Content  │◄────│ Product  │
        │ Marketing│     │ Design   │
        │ Outreach │────►│ Brand    │
        └──────────┘     └──────────┘
         brand assets      audience
         & copy            feedback
```

### Illustrative Handoffs

**Know → Grow**: Research identifies a recurring customer question and links the supporting evidence. Growth uses it to draft a post for human review.

**Build → Grow**: Brand department outputs the color palette (#FF6B35, #2E8B57). Growth uses these exact hex codes in Instagram stories and email headers.

**Grow → Know**: Growth supplies measured campaign signups and their reporting period. Research updates the traction summary without inventing results.

**Know → Build**: Research supplies a bounded comparison of competitor packaging. Product uses it to propose a design to test.

---

## Department Anatomy

You can describe a department through these four components:

### 1. Agent Persona (AGENT.md / agents.yaml)

Defines the agent's responsibility and working context. The **role + goal + backstory** vocabulary is used by CrewAI; this illustrative template adds explicit constraints and output expectations.

```markdown
# [Department] Lead

## Role
[Professional title — e.g., "Senior Growth Marketing Strategist"]

## Goal
[Outcome and deadline agreed with the project owner]

## Backstory
[Experience narrative that shapes decision-making style]

## Constraints
- NEVER [dangerous action] — flag for human review
- ALWAYS [required check] before [action]
- [Domain-specific rules]

## Tools Available
- [What this agent can use]
- Read-only access to [other department]/output/

## Output Standards
- [Where outputs go]
- [What format]
- Always include REVIEW.md for human approval items
```

### 2. Task Tracking (TASKS.md / tracker issues)

What needs to be done, linked to external project management.

```markdown
- [ ] Draft homepage hero copy <!-- Tracker: WS-101 -->
- [ ] Build landing page HTML/CSS <!-- Tracker: WS-102 -->
- [x] Define brand color palette <!-- Tracker: WS-103, completed 2026-02-20 -->
```

### 3. Output Directory

Where the department writes its work products. Other departments read from here.

```
department/
├── sub-area-1/
│   ├── TASKS.md
│   └── output/          ← Generated artifacts go here
├── sub-area-2/
│   ├── TASKS.md
│   └── output/
└── output/              ← Cross-project department-level artifacts
```

### 4. Cross-Department Access Rules

Explicit read/write boundaries:

```
# In growth/AGENT.md:
- Read-only: build/branding/output/ (for brand assets)
- Read-only: know/market-research/output/ (for data)
- Write: growth/**

# In know/AGENT.md:
- Read-only: grow/output/ (for traction data)
- Write: know/**

# In build/AGENT.md:
- Read-only: know/output/ (for competitive positioning)
- Write: build/**
```

---

## Automation Layer

If the work benefits from automation, a separate tool such as n8n, Zapier, Make or custom code can handle handoffs. These examples require their own implementation, authorization and checks; AI-OS Lite does not install this automation layer.

### Category 1: Defined Pipelines
- Signup → CRM → welcome email
- Human-confirmed tracker completion → reconcile the linked task record
- Social media post approved → schedule via Buffer

### Category 2: Agent-Triggered Execution
- Agent finishes research → automation routes brief to Growth agent
- Agent drafts content → automation sends for human approval → automation publishes

### Category 3: Scheduled Synthesis
- Monday 8:00 AM: collect approved department outputs → AI drafts a weekly report
- Friday: competitor monitoring → agent analyzes changes
- Daily: collect metrics → update dashboards

---

## Scaling Patterns

### Starting Small (Solo Founder + One Agent)
- One agent with persona switching (read AGENT.md per department)
- Manual handoffs (human moves information between departments)
- Shared memory, single context

### Growing (Solo Founder + Multiple Agents)
- Separate agents per department with isolated workspaces
- Automation handles handoffs and approval gates
- Inter-agent communication for quick messages

### Scaling (Small Team + Agent Fleet)
- Department leads (humans) review agent work per domain
- Meta-agent synthesizes cross-department activity
- Full automation pipeline with QA validators between handoffs
- Different models per department (cheap for routine, expensive for analysis)

---

## Implementation Checklist

For any new project using the department pattern:

- [ ] Choose the responsibility groups the project actually needs
- [ ] Write AGENT.md persona for each department
- [ ] Create workspace directory structure with output/ directories
- [ ] Define cross-department read/write access rules
- [ ] Map the pipeline cycle (which department feeds which)
- [ ] Set up project management (tracker / GitHub Issues) with department labels
- [ ] Create TASKS.md files linked to external tracking
- [ ] Decide: one agent with personas or multiple agents
- [ ] Set up automation layer for handoffs
- [ ] Create a meta-agent or weekly synthesis for cross-department visibility

---

## Related Notes

- [[Multi-Agent Architecture Patterns]] — The orchestration patterns each department uses internally
- [[AI-Native Architecture - Business Logic as Agent Instructions]] — How each department's rules are encoded in agent instructions
- [[Human-AI Trust Boundary Architecture for 24-7 Agent Systems]] — Where humans gate department outputs

### Sources and Further Reading

These sources explore related approaches. They do not establish a universal agent count or validate the illustrative outcomes in this note. Check current documentation before implementing a specific framework.

- [Anthropic - Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
- [LangChain - State of Agent Engineering](https://www.langchain.com/state-of-agent-engineering)
- [CrewAI Flows Docs](https://docs.crewai.com/en/concepts/flows)
- [Jacob Bank / Relay.app - Agent-First GTM](https://www.productgrowth.blog/p/agent-first-gtm-jacob-bank-relay-app)
- [Rocketable (YC W25)](https://www.ycombinator.com/companies/rocketable)
- [2026 Playbook for Reliable Agentic Workflows](https://promptengineering.org/agents-at-work-the-2026-playbook-for-building-reliable-agentic-workflows/)
