# Local human-response record

This is evidence stored only in the selected workspace, not identity verification,
a signature service, telemetry or tamper-proof enforcement. The installer checks
its shape and exact license match. A person with filesystem access can alter it.

Use `.ai-os/license-acceptance.json` and retain the exact reviewed LICENSE bytes
at `.ai-os/licenses/<license_sha256>.txt`. Reject linked or redirected paths.
Verify an existing snapshot against the actual license bytes; a hash in its
filename alone is not evidence. Preserve a mismatch for owner review.
After affirmative input and before writing the record, create or append these
entries to the directory-local `.ai-os/.gitignore`: `/license-acceptance.json`,
`/licenses/`, `/acceptance-history/`, and `/.license-*.tmp`, one per line. This protects the typed name
from ordinary Git staging. Already tracked files need separate owner review;
ignore rules do not untrack existing history.
Do not write anything when a response is declined, absent or incomplete.

Before replacing the current response, preserve its exact existing bytes at
`.ai-os/acceptance-history/<sha256-of-response-bytes>.json`, and preserve the new
response's exact serialized bytes under its own hash in that same directory.
Only then atomically replace `.ai-os/license-acceptance.json` with those new
bytes. Never overwrite a history entry. Verify existing entries against their
filenames and exact expected bytes; refuse linked paths, non-files, unexpected
names or mismatches and preserve them for owner review. A legacy response is
archived on the next completed review, even if malformed; that archive is raw
evidence, not proof of valid acceptance. Reusing an existing matching response
requires no history writes. If the current response changes during the save,
stop rather than replacing another writer's response. This local retention is
not an authenticated signature or tamper-proof storage.

A copied/restored record belongs to the named person or organization; it does
not establish a new person's agreement. Personal acceptance does not bind an
employer. If the human explicitly asks to change person or organization or
review again, show the exact terms again and collect every required field from
that human even if the old record matches. Do not infer identity, organization
or authority from login names, profiles or previous permission to install.
Decline/incomplete answers leave the existing record and history untouched.
Ordinary skill use need not repeat the prompt. The human can instead use
`python3 setup/tools/license_consent.py --review-again <workspace>` from the full
checkout; an assistant must never run that prompt on the person's behalf.

The JSON fields are:

- `schema_version`: 1.
- `license_version`: exact `license_version` in this package's metadata.
- `license_sha256`: computed SHA-256 of this package's LICENSE bytes.
- `publication_state`: exact metadata value, `draft` or `release`.
- `effect`: `draft-review-only` for draft; `license-acceptance` for release.
- `accepted`: true, and `affirmative_response`: `YES`, only after the human's explicit response.
- `typed_name`: the name the human actually typed, 2–200 characters.
- `capacity`: `personal` or `organization`, as explicitly selected by the person.
- `organization`: empty for personal, otherwise the legal name the person supplied.
- `authority_confirmed`: false for personal, true only after explicit organizational authority confirmation.
- `accepted_at_utc`: the actual recording time as ISO 8601 UTC ending in `Z`.
- `source`: `human-chat` for an assistant-recorded answer, never `human-terminal`.
- `human_message_reference`: the actual human-message identifier when available;
  otherwise a precise local conversation reference and the exact affirmative
  response, name, capacity and authority response. Never fabricate an identifier.

Names and organization names must have no control characters. Store no unrelated
conversation, profile data or credentials. License/version/publication-state
changes require fresh explicit review. A draft record never establishes acceptance
of a release, even if the version label remains the same. Keep ordinary user
content, assistant configuration and publication approval separate.
