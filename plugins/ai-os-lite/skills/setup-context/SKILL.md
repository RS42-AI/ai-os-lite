---
name: setup-context
description: Guide a new or returning AI-OS Lite user from one chosen outcome to connected area, goal, project and task notes. Use for getting started, personalizing a vault or resuming context setup; this is a conversation and note-writing workflow, not a machine installer.
---

# Set up your context

Help the person build one useful, portable example in their own Markdown
workspace. Explain briefly: an **area** is an ongoing responsibility, a **goal**
is an outcome, a **project** is a bounded effort toward it, and a **task** is a
next action. The files hold the context; assistant skills help put it to work.
Obsidian is an optional way to view them. MCP, QMD, additional service accounts, reflection and
external integrations are not prerequisites for this conversation.

## License review before setup writes

Normal assistant operation with the person's own content remains permitted.
License review gates installation and initial context-setup writes; it is not
consent to send their data anywhere or a ban on using their chosen assistant.

Resolve the selected workspace and the installed plugin root (two directories
above this skill). Read that package's complete `LICENSE` and
`LICENSE-METADATA.json`; compute SHA-256 from the exact LICENSE bytes using a
filesystem tool. If either is missing or inconsistent, explain the gap and stop
setup writes. Never fetch a different license and call it this package's terms.

A matching local `.ai-os/license-acceptance.json` can be reused only when its
version, hash, publication state, affirmative response, typed name, capacity,
authority where applicable, UTC timestamp and source are valid under
[the receipt contract](references/license-acceptance.md). An old AGPL install
or a draft rehearsal is not acceptance of a newly issued license.

If no matching record exists, present the full license with its exact version,
hash and draft/release status before requesting a response. Explicitly identify
a draft as nonoperative review only. Ask the human to type YES, their full name,
and whether they accept personally or for an organization. For an organization,
require its legal name and an explicit affirmation of authority to bind it.
Ask for missing items; never infer them from a profile, signature, employer,
prior chat, installation request or permission to continue. Silence, decline
and an incomplete answer mean no setup or consent-record writes.

Only after that actual human response may you record it locally using the
receipt contract, with `source: human-chat` and a reference to the human's exact
message. Show the local destination and explain that it is not sent to RS42.
Do not invent evidence of human input or claim that a chat response came from
a terminal. Never send answers into the installer prompt, emulate a terminal,
or set an acceptance flag on the person's behalf. The person may instead run
`python3 setup/tools/license_consent.py <workspace>` themselves from the full
checkout. Read-only orientation can continue if they decline.

## Find the starting point

Resolve the user's selected vault; do not mistake the product checkout for
their workspace or search unrelated folders. If no vault is selected, ask for
its location. Check whether its instruction file, templates and starter content
exist. Say separately what installation evidence is available and what the
person has personalized. Files being present do not prove that an assistant
skill, application or connection works.

Read the selected vault's `AGENTS.md`, the relevant instructions and the
[vault-config skill](../vault-config/SKILL.md). Discover configured areas,
existing goals, project hubs and any prior onboarding progress before proposing
new records. Read the canonical templates and effective contracts through the
[write-note skill](../write-note/SKILL.md). Use direct filesystem access when
Obsidian or search integrations are absent.

If required instructions or templates are missing, explain that specific gap
and offer the repository's existing setup guide as a separate next step. You
can still explore an outcome without saving anything. Do not install software,
rewrite instructions or migrate folders.

## Guide one connected example

Ask one short question at a time, reusing answers already given. Start with
“What is one outcome you would like help making progress on?” Offer a fictional
example or skipping personalization; no biography, private goals, public-profile
lookup or personal inventory is required. If the person skips, stop without
creating records or interpreting the skip as a setup failure.

Follow **outcome → area → goal → project → task**:

1. Offer an existing area that fits, with a brief reason, and let the person
   choose. If they want a new area, propose it without silently adding it to
   their configured vocabulary. Do not copy another person's areas.
2. Reuse a matching goal or help phrase the chosen outcome as one. Ask only
   for missing details needed to make it useful and valid, such as its horizon
   and what would count as progress. Do not invent dates, targets or commitments
   to fill template placeholders. Fictional choices must be identified as
   examples and kept out of real commitments.
3. Reuse a relevant project or propose one bounded effort serving that goal.
   Explain the proposed project before asking to create it.
4. Help choose one concrete next action. Keep onboarding guidance in the
   existing walkthrough project/task when available; the person's new project
   is their work, not a replacement walkthrough.

If a choice remains open, leave that part as a conversational proposal. Do not
write incomplete records merely to finish the sequence.

## Preview, then save the agreed work

Before writing, show the exact create/edit destinations and proposed note
contents, including the area/goal/project/task links. Derive paths, slugs,
fields, types and statuses from the selected vault's actual configuration and
templates, not a remembered folder layout. Explain any conflict between its
instructions and existing folders; do not resolve it by moving or duplicating
work. Search for overlap again and prefer updating or linking existing records.

Obtain approval for the concrete records if the current request has not already
authorized them. General “set this up” permission does not approve a newly
invented area, goal, project or commitment. An instruction-file change, including
an Areas-table addition, needs a separate exact edit preview: the human applies
it or directly authorizes those specific edits. Never self-edit `AGENTS.md` or
`CLAUDE.md` as a side effect of ordinary note approval. While that is pending,
offer a conversation-only preview or an approved existing area; do not force a
substitute choice.

Use the bundled `write-note` workflow for each approved note and run its
`scripts/lint_note.py` against the selected vault and each created/edited note.
Resolve that script relative to the installed skill rather than assuming a
client-specific environment variable exists. Fix reported note violations;
report unavailable checks or canon errors instead of claiming a pass. Preserve
human text and settled choices. Never infer `done` for these records or the
starter onboarding tasks, and never invent schema or relationships.

Save resumable progress only within the approved ordinary private workspace:
prefer the existing onboarding task/note, recording the agreed choices, links
and next unanswered question. Include this edit in the preview. If none exists,
propose a normally routed note through `write-note`; do not create an agent
memory entry, global configuration, public-repository receipt or parallel
progress database. On a repeat, read that progress and the actual records,
reconcile differences with the person, and resume without duplicate creation.

Finish with links to what was actually saved, the chosen next action and any
remaining decision. Explain that the same files can be used directly by an
assistant or opened in Obsidian. Offer `start-day` as a next use of the context
only when the user wants it; personalization does not prove a fresh install or
an authenticated assistant invocation.
