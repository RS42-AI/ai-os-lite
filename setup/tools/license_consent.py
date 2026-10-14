#!/usr/bin/env python3
"""Present the exact local license and record a person's affirmative response.

No acceptance flags, environment variables, network calls, or piped-input mode.
A receipt is local evidence, not identity verification or tamper-proof enforcement.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import os
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = Path('.ai-os/license-acceptance.json')
HISTORY = Path('.ai-os/acceptance-history')
PRIVATE_IGNORE = '/license-acceptance.json\n/licenses/\n/acceptance-history/\n/.license-*.tmp\n'


class ConsentError(RuntimeError):
    pass


def load_policy(root: Path = ROOT) -> dict:
    license_bytes = (root / 'LICENSE').read_bytes()
    policy = json.loads((root / 'LICENSE-METADATA.json').read_text(encoding='utf-8'))
    version = policy.get('license_version')
    state = policy.get('publication_state')
    if not isinstance(version, str) or not version.strip() or state not in ('draft', 'release'):
        raise ConsentError('License metadata must identify its version and draft/release state.')
    text = license_bytes.decode('utf-8')
    if state == 'release' and 'DRAFT FOR PRIVATE REVIEW' in text:
        raise ConsentError('Draft license text cannot be treated as an issued release.')
    if version not in text:
        raise ConsentError('License text and version metadata disagree.')
    return {'license_version': version, 'publication_state': state,
            'license_sha256': hashlib.sha256(license_bytes).hexdigest(),
            'license_text': text}


def safe_workspace(workspace: Path) -> Path:
    workspace = Path(os.path.abspath(workspace.expanduser()))
    # Do not follow a redirected receipt or workspace parent into another location.
    for path in (workspace, *workspace.parents):
        if path.is_symlink():
            # macOS /tmp is a standard symlink. Resolve it only when callers use it.
            if (path == Path('/tmp') and path.resolve() == Path('/private/tmp')) or (path == Path('/var') and path.resolve() == Path('/private/var')):
                continue
            raise ConsentError('Workspace and receipt paths must not contain symlinks.')
    for path in (workspace / '.ai-os', workspace / RECEIPT, workspace / HISTORY, workspace / '.ai-os/licenses', workspace / '.ai-os/.gitignore'):
        if path.is_symlink():
            raise ConsentError('Workspace and receipt paths must not contain symlinks.')
    if workspace.exists() and not workspace.is_dir():
        raise ConsentError('Selected workspace is not a directory.')
    # Compare canonical locations only after rejecting redirected paths above.
    # Standard macOS /tmp or /var aliases must not hide the product checkout.
    canonical_workspace = workspace.resolve()
    canonical_package = ROOT.resolve()
    if canonical_workspace == canonical_package or canonical_package in canonical_workspace.parents:
        raise ConsentError('Choose a workspace separate from the product checkout.')
    return canonical_workspace


def clean_name(value: str, label: str) -> str:
    value = value.strip()
    if not 2 <= len(value) <= 200 or any(ord(c) < 32 for c in value):
        raise ConsentError(f'{label} must contain 2–200 ordinary characters.')
    return value


def make_receipt(policy: dict, name: str, capacity: str, organization: str = '',
                 authority: bool = False, source: str = 'human-terminal',
                 human_message_reference: str = '') -> dict:
    name = clean_name(name, 'Typed name')
    if capacity not in ('personal', 'organization'):
        raise ConsentError('Choose personal or organization capacity.')
    if capacity == 'organization':
        organization = clean_name(organization, 'Organization')
        if authority is not True:
            raise ConsentError('An organizational representative must affirm authority.')
    elif organization or authority:
        raise ConsentError('Personal acceptance must not assert organizational authority.')
    if source not in ('human-terminal', 'human-chat', 'human-windows-console'):
        raise ConsentError('Unsupported human-response source.')
    if source == 'human-chat' and not human_message_reference.strip():
        raise ConsentError('A chat response needs a reference to the actual human message.')
    return {
        'schema_version': 1,
        'license_version': policy['license_version'],
        'license_sha256': policy['license_sha256'],
        'publication_state': policy['publication_state'],
        'effect': 'draft-review-only' if policy['publication_state'] == 'draft' else 'license-acceptance',
        'accepted': True, 'affirmative_response': 'YES',
        'typed_name': name, 'capacity': capacity,
        'organization': organization, 'authority_confirmed': authority,
        'accepted_at_utc': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        'source': source, 'human_message_reference': human_message_reference,
    }


def valid_receipt(receipt: dict, policy: dict) -> bool:
    try:
        if receipt.get('schema_version') != 1 or receipt.get('accepted') is not True or receipt.get('affirmative_response') != 'YES':
            return False
        for field in ('license_version', 'license_sha256', 'publication_state'):
            if receipt.get(field) != policy[field]:
                return False
        expected_effect = 'draft-review-only' if policy['publication_state'] == 'draft' else 'license-acceptance'
        if receipt.get('effect') != expected_effect:
            return False
        timestamp = receipt['accepted_at_utc']
        if not isinstance(timestamp, str) or not timestamp.endswith('Z'):
            return False
        datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        make_receipt(policy, receipt['typed_name'], receipt['capacity'],
                     receipt.get('organization', ''), receipt.get('authority_confirmed', False),
                     receipt['source'], receipt.get('human_message_reference', ''))
        return True
    except (ConsentError, KeyError, TypeError, ValueError, AttributeError):
        return False


def existing_receipt(workspace: Path, policy: dict) -> bool:
    try:
        validate_history(workspace)
        receipt = json.loads((workspace / RECEIPT).read_text(encoding='utf-8-sig'))
        snapshot = workspace / '.ai-os/licenses' / (policy['license_sha256'] + '.txt')
        return (valid_receipt(receipt, policy) and not snapshot.is_symlink()
                and snapshot.read_bytes() == policy['license_text'].encode('utf-8'))
    except (ConsentError, OSError, ValueError, TypeError, AttributeError):
        return False


def validate_history(workspace: Path) -> None:
    """History retains raw evidence; its presence does not make a receipt valid."""
    history = workspace / HISTORY
    if history.is_symlink() or (history.exists() and not history.is_dir()):
        raise ConsentError('Acceptance history must be an ordinary directory; preserve it for owner review.')
    if history.exists():
        for path in history.iterdir():
            if (path.is_symlink() or not path.is_file()
                    or not re.fullmatch(r'[0-9a-f]{64}\.json', path.name)
                    or hashlib.sha256(path.read_bytes()).hexdigest() != path.stem):
                raise ConsentError('Acceptance history differs from its saved evidence; preserve it for owner review.')


def archive_response(history: Path, evidence: bytes) -> None:
    """Write each exact response once; never replace an existing history entry."""
    destination = history / (hashlib.sha256(evidence).hexdigest() + '.json')
    try:
        with destination.open('xb') as handle:
            handle.write(evidence)
    except FileExistsError:
        if destination.is_symlink() or not destination.is_file() or destination.read_bytes() != evidence:
            raise ConsentError('Acceptance history collision; preserve the existing evidence for owner review.')


def collect_human_acceptance(policy: dict) -> dict:
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise ConsentError('Human license review requires an interactive terminal. No files changed. '
                           'An assistant must not supply acceptance or emulate the human terminal.')
    print('\n' + policy['license_text'] + '\n')
    print(f"Exact license SHA-256: {policy['license_sha256']}")
    if policy['publication_state'] == 'draft':
        print('PRIVATE DRAFT: this is a review rehearsal, not operative license acceptance or publication approval.')
    print('Only you, the human user, may answer. An assistant cannot accept for you. '
          'The response and typed name stay in this workspace; nothing is sent to RS42.')
    try:
        if input('After reading the full text above, type YES to agree (anything else stops): ').strip() != 'YES':
            raise ConsentError('License not accepted; no files changed.')
        name = input('Type your full name: ')
        capacity = input('Type personal or organization for the capacity in which you accept: ').strip()
        organization, authority = '', False
        if capacity == 'organization':
            organization = input('Type the organization\'s legal name: ')
            authority = input('Type YES to confirm you are authorized to bind that organization: ').strip() == 'YES'
        return make_receipt(policy, name, capacity, organization, authority)
    except (EOFError, KeyboardInterrupt) as exc:
        raise ConsentError('License response incomplete; no files changed.') from exc


def save_receipt(workspace: Path, policy: dict, receipt: dict) -> None:
    workspace = safe_workspace(workspace)
    if not valid_receipt(receipt, policy):
        raise ConsentError('Invalid acceptance evidence; no files changed.')
    validate_history(workspace)
    current_path = workspace / RECEIPT
    previous_response = current_path.read_bytes() if current_path.exists() else None
    response = (json.dumps(receipt, indent=2) + '\n').encode('utf-8')
    record_dir = workspace / '.ai-os'
    license_path = record_dir / 'licenses' / (policy['license_sha256'] + '.txt')
    if license_path.is_symlink() or (license_path.exists() and license_path.read_bytes() != policy['license_text'].encode('utf-8')):
        raise ConsentError('The saved license snapshot differs from the reviewed text; preserve it for owner review.')
    record_dir.mkdir(parents=True, exist_ok=True)
    # A directory-local ignore keeps names and private evidence out of ordinary
    # Git staging without rewriting a workspace's existing root ignore rules.
    ignore_path = record_dir / '.gitignore'
    previous_ignore = ignore_path.read_text(encoding='utf-8') if ignore_path.exists() else ''
    if not previous_ignore.endswith(PRIVATE_IGNORE):
        with ignore_path.open('a', encoding='utf-8') as handle:
            handle.write(('\n' if previous_ignore and not previous_ignore.endswith('\n') else '') + PRIVATE_IGNORE)
    # Preserve the exact reviewed text, including a private draft's warning.
    license_dir = record_dir / 'licenses'
    license_dir.mkdir(exist_ok=True)
    license_path = license_dir / (policy['license_sha256'] + '.txt')
    if license_path.is_symlink():
        raise ConsentError('Refusing a redirected license snapshot.')
    if not license_path.exists():
        with license_path.open('x', encoding='utf-8', newline='') as handle:
            handle.write(policy['license_text'])
    history = workspace / HISTORY
    history.mkdir(exist_ok=True)
    # Migrate even malformed older evidence byte-for-byte, without treating it
    # as valid acceptance. Preserve both responses before changing the pointer.
    if previous_response is not None:
        archive_response(history, previous_response)
    archive_response(history, response)
    if previous_response == response:
        return
    fd, temporary = tempfile.mkstemp(prefix='.license-', suffix='.tmp', dir=record_dir)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(response)
        if (current_path.read_bytes() if current_path.exists() else None) != previous_response:
            raise ConsentError('The current acceptance changed during review; history was preserved, but the current record was not replaced.')
        os.replace(temporary, current_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def ensure_acceptance(workspace: Path, check_only: bool = False, review_again: bool = False) -> bool:
    if check_only and review_again:
        raise ConsentError('Choose either a read-only check or a new human review.')
    workspace = safe_workspace(workspace)
    validate_history(workspace)
    policy = load_policy()
    if not review_again and existing_receipt(workspace, policy):
        if not check_only:
            previous = json.loads((workspace / RECEIPT).read_text(encoding='utf-8-sig'))
            capacity = previous['organization'] if previous['capacity'] == 'organization' else 'personal capacity'
            print(f"Using the local record for {previous['typed_name']} ({capacity}).")
        return True
    if check_only:
        raise ConsentError('No matching human acceptance record. Open the license helper yourself in a terminal; no files changed.')
    receipt = collect_human_acceptance(policy)
    save_receipt(workspace, policy, receipt)
    print('Local review record saved.' if policy['publication_state'] == 'draft' else 'Local license acceptance saved.')
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Check a matching record without prompting or writing.')
    mode.add_argument('--review-again', action='store_true', help='Ask the human again, for example when changing the person or organization; never accepts automatically.')
    args = parser.parse_args()
    try:
        ensure_acceptance(args.workspace, args.check, args.review_again)
    except (ConsentError, OSError, ValueError, KeyError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 3
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
