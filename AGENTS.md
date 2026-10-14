## Git Workflow — Human-Only Production Gate

`main` is production.

- AI may create branches, commit, push non-production branches, open/update PRs, monitor checks, and report previews.
- GitHub operations are programmatic only. Never use Browser, Computer Use, GitHub.com UI, GitHub Desktop, or a phone GitHub app for GitHub work.
- AI must never push to production branches; approve a PR; enable auto-merge; merge a production PR; or trigger the final production deployment through CLI, API, connector, browser, or any other mechanism.
- “Deploy,” “publish,” “ship,” “go live,” or approval of the changes means: prepare the PR, verify it, and stop. The human owner personally reviews and merges through a human-controlled `gh`/API session.
- Even an instruction to “merge it” does not delegate this human-only action. Return the PR URL, final head commit, checks, preview, and merge consequence.
- Missing or bypassable branch protection never relaxes the rule.
- Never use an owner/admin credential for automation. AI writes use the restricted RS42 GitHub App identity with no bypass; a machine user is an exception requiring a separate decision.
- Never force-push, delete protected branches, rewrite shared history, discard user changes, or change repository/deployment permissions without a separate exact preview and explicit authorization.
