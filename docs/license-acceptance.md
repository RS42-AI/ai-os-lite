# License agreement and local records

This package carries [AI-OS Lite License 1.0](../LICENSE). Installation and
guided setup require a person's explicit agreement to these terms. Earlier
private draft rehearsals produced `draft-review-only` records; those records
do not accept this license. Tests use synthetic responses and do not record
real human acceptance. Accepting this license is not an ownership transfer.

Before an installation or update writes setup files, show the complete local
LICENSE and its SHA-256 hash. The person types YES, their full name, and personal
or organizational capacity. A representative also supplies the organization's
legal name and expressly confirms authority to bind it. Silence, decline,
piped input, missing fields and missing authority stop before setup writes.
`SETUP_YES`, assistant approval and ordinary permission to install do not accept
the license. Assistants must never fill this prompt or emulate human input.

## Where the gate applies

| Route | Review boundary |
|---|---|
| `setup/setup.sh` | First invokes the gated vault step; integrations run only afterward. |
| `setup/setup-vault.sh`, including `--update` | Validates arguments and dependencies, then requires matching review before target writes. |
| `setup/setup-claude-plugins.sh` and `setup/setup-codex-plugins.sh` | Requires matching review before marketplace or user-level plugin changes. |
| `setup/setup-plugins.sh` and `setup/setup-mcp.sh` | Requires matching review before downloads and configuration writes. |
| `setup/setup-windows.ps1` | Native console review before WSL, prerequisites or setup writes; runs this exact local package in WSL. |
| All operational skills, including direct skill invocation | Require the shared `setup-context` record check before workflow execution; show the bundled full license, collect the actual human response and record its source if missing. This is an instruction-level check. |
| `/update-structure` and `project_structure.py` | Check matching review before update records, plan files, scaffold or apply writes; read-only discussion remains possible. Rollback remains available. |
| A plugin manager's own direct install/update command | The package cannot intercept that external manager. Use the gated wrapper or complete explicit review through `setup-context` before setup writes. Do not claim marketplace installation itself proves assent. |

The terminal helper can be opened separately from this checkout:

```bash
python3 setup/tools/license_consent.py "$HOME/AIOS"
# Read-only record validation; no prompting or writing:
python3 setup/tools/license_consent.py --check "$HOME/AIOS"
# The human can request a new review when changing person or organization:
python3 setup/tools/license_consent.py --review-again "$HOME/AIOS"
```

`--review-again` still requires the human's complete response in a real terminal;
it is not an acceptance flag. Decline or incomplete input leaves the existing
record and history unchanged. On Windows, the equivalent separate human action
from the checkout is:

```powershell
. ./setup/license-consent.ps1
Confirm-AiosLicense -Workspace "$HOME/AIOS" -PackageRoot (Get-Location).Path -ReviewAgain
```

The plugin wrappers install from this reviewed local package. An optional
`AI_OS_LITE_MARKETPLACE` value must resolve to this same directory; a remote
repository or different checkout is rejected before client writes. This keeps
the reviewed terms and selected installation source together. A local client
marketplace registration still needs live verification in each supported client.

The same version, hash and draft/release state can reuse a valid local record.
Changed terms or publication state require a new explicit response. The record
lives at `.ai-os/license-acceptance.json` in the selected workspace, with exact
reviewed license bytes at `.ai-os/licenses/<hash>.txt`. It contains the typed
name, capacity, organization and authority when applicable, actual UTC recording
time, response source, version and hash. Chat records identify the actual human
message. It sends nothing to RS42 and makes no network request.

Before replacing that current record, the helper preserves both the previous
response's exact bytes and the new response at
`.ai-os/acceptance-history/<response-bytes-sha256>.json`. Existing entries are
verified and never overwritten by the helper. Older installations without a
history directory migrate the prior response on the next completed review.
Even malformed prior evidence is retained unchanged; retaining it does not make
it valid acceptance. Matching-record reuse does not rewrite or migrate anything.
An altered history entry or a redirected path stops the save for owner review.

The current record describes the named person or organization. Copying or
restoring it does not prove a different person agreed, and personal acceptance
does not bind an employer. Use the explicit review-again action to change the
licensee, then select the correct capacity and authority. Routine skills can
reuse a matching record; they must not guess identity from a login or profile.

These private files, including acceptance history, are ignored by a directory-local `.ai-os/.gitignore` so normal
Git staging does not include the name or response. Ignore rules do not remove
already tracked data; review that separately if these paths existed in history.
An altered saved license snapshot is refused and preserved for owner review.

A local record is evidence under the user's control, not identity verification,
a signature service or tamper-proof enforcement. A terminal check can reject
headless or piped input but cannot establish who controls a terminal. The rule
against assistant consent still applies. Ordinary permitted assistant work with
the person's content is not disabled by this installation gate.

The Windows helper requires the full local checkout, an interactive console and
LF-normalized source files. Its mocked control-flow tests do not establish a
successful real Windows/WSL installation; that device-level acceptance remains
outstanding. Client marketplaces also have their own rules and UI capabilities.
