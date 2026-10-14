---
name: missing-gate-pkg
description: Fixture workflow package for tests/capture_workflow/run.sh.
user-invocable: true
---

# Fixture: Etsy Morning Queue

This is a fixture capture-workflow package used by `tests/capture_workflow/run.sh`
to exercise the manifest validator. It models a small morning-review workflow
for an Etsy seller dashboard: the agent opens the dashboard and reads new
orders and messages, a human judges edge cases the automation can't classify,
the agent drafts a daily action queue, and finally previews and sends replies
only after human approval.

Urgency rules (fixture only, not enforced by the validator):
- Unread messages older than 24 hours are high priority.
- Unfulfilled orders due to ship today are high priority.
- Anything ambiguous gets routed to the human judgment step instead of guessed.

This file exists purely to satisfy the `SKILL.md` presence and length checks
in the validator; its prose content is not otherwise interpreted.
