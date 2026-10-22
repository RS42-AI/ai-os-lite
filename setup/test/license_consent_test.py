"""Synthetic consent tests: no real person accepts a license in this suite.

Interactive responses are deterministic unit-test mocks, never sent to a live
terminal. Installer checks use throwaway paths and stub clients only.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('license_consent_test_target', ROOT/'setup/tools/license_consent.py')
consent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(consent)


class LicenseConsent(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='consent-unit-', dir='/private/tmp' if Path('/private/tmp').is_dir() else None)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root/'workspace'
        self.policy = consent.load_policy(ROOT)

    def review(self, answers, **options):
        with patch.object(sys.stdin, 'isatty', return_value=True), patch.object(sys.stdout, 'isatty', return_value=True), patch('builtins.input', side_effect=answers), contextlib.redirect_stdout(io.StringIO()) as output:
            # redirect_stdout has a separate stream; mark only this test stream as interactive.
            with patch.object(output, 'isatty', return_value=True):
                consent.ensure_acceptance(self.workspace, **options)
            return output.getvalue()

    def fixture_policy(self, state, text=None):
        """Load synthetic policy files without issuing or editing the real license."""
        package = self.root / ('synthetic-' + state)
        package.mkdir()
        version = 'AI-OS Lite Synthetic Test License 1.0'
        (package/'LICENSE').write_text(text or version + '\nSynthetic testing material only; no real rights granted.\n')
        (package/'LICENSE-METADATA.json').write_text(json.dumps({
            'license_version': version, 'publication_state': state,
        }))
        return consent.load_policy(package)

    def test_explicit_personal_review_records_current_policy_and_preserves_text(self):
        output = self.review(['YES', 'Synthetic Test User', 'personal'])
        receipt = json.loads((self.workspace/consent.RECEIPT).read_text())
        self.assertTrue(consent.valid_receipt(receipt, self.policy))
        self.assertEqual(receipt['typed_name'], 'Synthetic Test User')
        self.assertEqual(receipt['source'], 'human-terminal')
        expected_effect = 'draft-review-only' if self.policy['publication_state'] == 'draft' else 'license-acceptance'
        self.assertEqual(receipt['effect'], expected_effect)
        self.assertEqual(receipt['publication_state'], self.policy['publication_state'])
        self.assertTrue(receipt['accepted_at_utc'].endswith('Z'))
        self.assertIn(self.policy['license_text'], output)
        if self.policy['publication_state'] == 'draft':
            self.assertIn('PRIVATE DRAFT', output)
        snapshot = self.workspace/'.ai-os/licenses'/f"{self.policy['license_sha256']}.txt"
        self.assertEqual(snapshot.read_bytes(), (ROOT/'LICENSE').read_bytes())

    def test_synthetic_draft_and_release_require_distinct_explicit_responses(self):
        draft = self.fixture_policy('draft')
        release = self.fixture_policy('release')
        # Identical bytes/version isolate the publication-state boundary.
        self.assertEqual(draft['license_sha256'], release['license_sha256'])
        self.assertEqual(draft['license_version'], release['license_version'])
        with patch.object(consent, 'load_policy', return_value=draft):
            draft_output = self.review(['YES', 'Synthetic Test User', 'personal'])
        draft_bytes = (self.workspace/consent.RECEIPT).read_bytes()
        draft_receipt = json.loads(draft_bytes)
        self.assertEqual(draft_receipt['effect'], 'draft-review-only')
        self.assertEqual(draft_receipt['publication_state'], 'draft')
        self.assertIn('PRIVATE DRAFT', draft_output)
        self.assertTrue(consent.existing_receipt(self.workspace, draft))
        self.assertFalse(consent.existing_receipt(self.workspace, release))
        with patch.object(consent, 'load_policy', return_value=release):
            with self.assertRaises(consent.ConsentError):
                consent.ensure_acceptance(self.workspace, check_only=True)
            with self.assertRaises(consent.ConsentError):
                self.review(['no'])
            self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), draft_bytes)
            release_output = self.review(['YES', 'Synthetic Test User', 'personal'])
            with patch('builtins.input', side_effect=AssertionError('must not prompt')):
                self.assertTrue(consent.ensure_acceptance(self.workspace))
        release_receipt = json.loads((self.workspace/consent.RECEIPT).read_text())
        self.assertEqual(release_receipt['effect'], 'license-acceptance')
        self.assertEqual(release_receipt['publication_state'], 'release')
        self.assertNotIn('PRIVATE DRAFT', release_output)
        self.assertTrue(consent.existing_receipt(self.workspace, release))
        self.assertFalse(consent.existing_receipt(self.workspace, draft))
        snapshot = self.workspace/'.ai-os/licenses'/f"{release['license_sha256']}.txt"
        self.assertEqual(snapshot.read_text(), release['license_text'])

    def test_synthetic_release_metadata_cannot_issue_draft_license_text(self):
        with self.assertRaisesRegex(consent.ConsentError, 'Draft license text'):
            self.fixture_policy('release', 'AI-OS Lite Synthetic Test License 1.0\nDRAFT FOR PRIVATE REVIEW\nSynthetic test only.\n')

    def test_organization_requires_separate_authority(self):
        self.review(['YES', 'Synthetic Test User', 'organization', 'Synthetic Example LLC', 'YES'])
        receipt = json.loads((self.workspace/consent.RECEIPT).read_text())
        self.assertEqual(receipt['organization'], 'Synthetic Example LLC')
        self.assertTrue(receipt['authority_confirmed'])

    def test_decline_incomplete_and_unauthorized_leave_no_files(self):
        for answers in [['no'], [''], ['YES', '', 'personal'], ['YES', 'Synthetic Test User', ''],
                        ['YES', 'Synthetic Test User', 'organization', 'Example LLC', 'no'],
                        ['YES', EOFError()], [KeyboardInterrupt()]]:
            with self.subTest(answers=answers), self.assertRaises(consent.ConsentError):
                self.review(answers)
            self.assertFalse(self.workspace.exists())

    def test_missing_record_headless_fails_even_with_yes_environment(self):
        env = dict(os.environ, SETUP_YES='1', ACCEPT_LICENSE='YES', AI_OS_LICENSE_ACCEPTED='1', PYTHONDONTWRITEBYTECODE='1')
        run = subprocess.run([sys.executable, str(ROOT/'setup/tools/license_consent.py'), str(self.workspace)],
                             input='YES\nSynthetic Test User\npersonal\n', capture_output=True, text=True, env=env)
        self.assertEqual(run.returncode, 3)
        self.assertIn('interactive terminal', run.stderr)
        self.assertFalse(self.workspace.exists())

    def test_matching_receipt_reused_without_prompt_or_mutation(self):
        self.review(['YES', 'Synthetic Test User', 'personal'])
        before = (self.workspace/consent.RECEIPT).read_bytes()
        with patch('builtins.input', side_effect=AssertionError('must not prompt')):
            self.assertTrue(consent.ensure_acceptance(self.workspace, check_only=True))
            self.assertTrue(consent.ensure_acceptance(self.workspace))
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), before)

    def test_history_preserves_exact_previous_response_and_is_idempotent(self):
        first = consent.make_receipt(self.policy, 'Synthetic First Person', 'personal')
        consent.save_receipt(self.workspace, self.policy, first)
        first_bytes = (self.workspace/consent.RECEIPT).read_bytes()
        second = consent.make_receipt(self.policy, 'Synthetic Second Person', 'organization', 'Synthetic LLC', True)
        consent.save_receipt(self.workspace, self.policy, second)
        second_bytes = (self.workspace/consent.RECEIPT).read_bytes()
        history = self.workspace/consent.HISTORY
        self.assertEqual({p.read_bytes() for p in history.iterdir()}, {first_bytes, second_bytes})
        for path in history.iterdir():
            self.assertEqual(path.stem, hashlib.sha256(path.read_bytes()).hexdigest())
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in history.iterdir()}
        consent.save_receipt(self.workspace, self.policy, second)
        self.assertEqual({p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in history.iterdir()}, before)
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), second_bytes)

    def test_history_migrates_legacy_or_malformed_current_bytes_without_validating_them(self):
        for previous in [b'{"legacy": "not acceptance"}\r\n', b'older incomplete evidence\n']:
            with self.subTest(previous=previous):
                if self.workspace.exists():
                    shutil.rmtree(self.workspace)
                (self.workspace/'.ai-os').mkdir(parents=True)
                (self.workspace/consent.RECEIPT).write_bytes(previous)
                self.assertFalse(consent.existing_receipt(self.workspace, self.policy))
                receipt = consent.make_receipt(self.policy, 'Synthetic New Person', 'personal')
                consent.save_receipt(self.workspace, self.policy, receipt)
                self.assertEqual((self.workspace/consent.HISTORY/(hashlib.sha256(previous).hexdigest()+'.json')).read_bytes(), previous)
                self.assertTrue(consent.existing_receipt(self.workspace, self.policy))

    def test_history_tampering_and_redirection_stop_before_mutation(self):
        self.review(['YES', 'Synthetic Test User', 'personal'])
        history = self.workspace/consent.HISTORY
        entry = next(history.iterdir())
        entry.write_bytes(b'Changed historic evidence\n')
        before = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        second = consent.make_receipt(self.policy, 'Synthetic Other Person', 'personal')
        with self.assertRaisesRegex(consent.ConsentError, 'history'):
            consent.save_receipt(self.workspace, self.policy, second)
        self.assertEqual({str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}, before)
        shutil.rmtree(history)
        outside = self.root/'outside-history'; outside.mkdir()
        history.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(consent.ConsentError):
            consent.save_receipt(self.workspace, self.policy, second)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), before[str(consent.RECEIPT)])

    def test_explicit_review_again_changes_licensee_only_after_complete_response(self):
        self.review(['YES', 'Synthetic First Person', 'personal'])
        before = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        for answers in [['no'], ['YES', 'Synthetic Other Person', 'organization', 'Synthetic LLC', 'no'], [EOFError()]]:
            with self.subTest(answers=answers), self.assertRaises(consent.ConsentError):
                self.review(answers, review_again=True)
            self.assertEqual({str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}, before)
        self.review(['YES', 'Synthetic Other Person', 'organization', 'Synthetic LLC', 'YES'], review_again=True)
        current = json.loads((self.workspace/consent.RECEIPT).read_text())
        self.assertEqual(current['typed_name'], 'Synthetic Other Person')
        self.assertEqual(current['capacity'], 'organization')
        self.assertIn(before[str(consent.RECEIPT)], {p.read_bytes() for p in (self.workspace/consent.HISTORY).iterdir()})

    def test_review_again_still_rejects_headless_input_with_existing_record(self):
        self.review(['YES', 'Synthetic First Person', 'personal'])
        before = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        run = subprocess.run([sys.executable, str(ROOT/'setup/tools/license_consent.py'), '--review-again', str(self.workspace)],
                             input='YES\nSynthetic Other Person\npersonal\n', capture_output=True, text=True)
        self.assertEqual(run.returncode, 3)
        self.assertIn('interactive terminal', run.stderr)
        self.assertEqual({str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}, before)

    def test_changed_license_or_state_requires_fresh_human_response(self):
        self.review(['YES', 'Synthetic Test User', 'personal'])
        before = (self.workspace/consent.RECEIPT).read_bytes()
        other_state = 'release' if self.policy['publication_state'] == 'draft' else 'draft'
        for field, value in [('license_sha256', '0'*64), ('publication_state', other_state), ('license_version', 'New version')]:
            policy = dict(self.policy, **{field: value})
            self.assertFalse(consent.existing_receipt(self.workspace, policy))
            with patch.object(consent, 'load_policy', return_value=policy), self.assertRaises(consent.ConsentError):
                consent.ensure_acceptance(self.workspace, check_only=True)
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), before)

    def test_private_receipt_is_ignored_by_git_and_snapshot_tampering_fails(self):
        self.review(['YES', 'Synthetic Test User', 'personal'])
        subprocess.run(['git', '-C', str(self.workspace), 'init', '-q'], check=True, capture_output=True)
        ignored = subprocess.run(['git', '-C', str(self.workspace), 'check-ignore', '.ai-os/license-acceptance.json',
                                  '.ai-os/licenses/'+self.policy['license_sha256']+'.txt',
                                  str(next((self.workspace/consent.HISTORY).iterdir()).relative_to(self.workspace))], capture_output=True, text=True)
        self.assertEqual(ignored.returncode, 0)
        self.assertEqual(len(ignored.stdout.splitlines()), 3)
        snapshot = self.workspace/'.ai-os/licenses'/f"{self.policy['license_sha256']}.txt"
        snapshot.write_text('Edited snapshot; retain for review.\n')
        self.assertFalse(consent.existing_receipt(self.workspace, self.policy))
        before = (self.workspace/consent.RECEIPT).read_bytes()
        with self.assertRaises(consent.ConsentError):
            consent.save_receipt(self.workspace, self.policy, consent.make_receipt(self.policy, 'Synthetic Test User', 'personal'))
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), before)
        self.assertEqual(snapshot.read_text(), 'Edited snapshot; retain for review.\n')

    def test_chat_evidence_cannot_be_inferred(self):
        with self.assertRaises(consent.ConsentError):
            consent.make_receipt(self.policy, 'Synthetic Test User', 'personal', source='human-chat')
        receipt = consent.make_receipt(self.policy, 'Synthetic Test User', 'personal', source='human-chat', human_message_reference='Synthetic unit-test human message only')
        self.assertTrue(consent.valid_receipt(receipt, self.policy))

    def test_malformed_receipt_never_counts(self):
        valid = consent.make_receipt(self.policy, 'Synthetic Test User', 'personal')
        wrong_effect = 'license-acceptance' if valid['effect'] == 'draft-review-only' else 'draft-review-only'
        for field, value in [('typed_name', ''), ('accepted', 'true'), ('accepted_at_utc', 'yesterday'), ('source', 'agent'), ('effect', wrong_effect)]:
            self.assertFalse(consent.valid_receipt(dict(valid, **{field: value}), self.policy), field)
        self.assertFalse(consent.valid_receipt([], self.policy))

    def test_product_checkout_and_children_rejected_through_canonical_and_tmp_alias(self):
        paths = [ROOT, ROOT/'must-not-create-workspace']
        if Path('/tmp').resolve() == Path('/private/tmp') and ROOT.is_relative_to('/private/tmp'):
            alias = Path('/tmp') / ROOT.relative_to('/private/tmp')
            paths.extend([alias, alias/'must-not-create-workspace'])
        for path in paths:
            with self.subTest(path=str(path)), self.assertRaisesRegex(consent.ConsentError, 'separate from the product checkout'):
                consent.safe_workspace(path)
        self.assertFalse((ROOT/'must-not-create-workspace').exists())

    def test_direct_structure_cli_rejects_workspace_symlink_before_resolving(self):
        consent.save_receipt(self.workspace, self.policy, consent.make_receipt(self.policy, 'Synthetic Test User', 'personal'))
        alias = self.root/'workspace-link'
        alias.symlink_to(self.workspace, target_is_directory=True)
        before = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        for command, options in [('scaffold', []), ('plan', ['--output', str(self.root/'must-not-write-plan.json')]),
                                 ('apply', ['--plan', str(self.root/'absent-plan.json'), '--approval-token', 'synthetic']),
                                 ('rollback', ['--receipt', str(self.root/'absent-receipt.json')])]:
            run = subprocess.run([sys.executable, str(ROOT/'setup/tools/project_structure.py'), command,
                                  '--vault', str(alias), *options], capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0, command)
            self.assertIn('must not contain symlinks', run.stderr, run.stdout+run.stderr)
        after = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        self.assertEqual(after, before)
        self.assertFalse((self.root/'must-not-write-plan.json').exists())

    def test_redirected_receipt_refused_without_outside_write(self):
        self.workspace.mkdir()
        outside = self.root/'outside'; outside.mkdir()
        (self.workspace/'.ai-os').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(consent.ConsentError):
            consent.ensure_acceptance(self.workspace)
        self.assertEqual(list(outside.iterdir()), [])

    def test_bundled_license_copies_and_all_skill_entrypoints_share_review_contract(self):
        for location in ('setup', 'plugins/ai-os-lite'):
            self.assertEqual((ROOT/location/'LICENSE').read_bytes(), (ROOT/'LICENSE').read_bytes())
            self.assertEqual(json.loads((ROOT/location/'LICENSE-METADATA.json').read_text()), json.loads((ROOT/'LICENSE-METADATA.json').read_text()))
        for path in (ROOT/'plugins/ai-os-lite/skills').glob('*/SKILL.md'):
            source = path.read_text()
            if path.parent.name == 'setup-context':
                self.assertIn('## License review before setup writes', source)
            else:
                self.assertIn('../setup-context/SKILL.md#license-review-before-setup-writes', source, str(path))
                self.assertIn('## Human license check', source, str(path))

    def test_all_shell_install_routes_stop_headless_before_client_or_workspace_writes(self):
        bindir = self.root/'bin'; bindir.mkdir()
        task_home = self.root/'home'; task_home.mkdir()
        log = self.root/'client-called'
        for cli in ('claude', 'codex'):
            stub = bindir/cli
            stub.write_text('#!/bin/sh\ntouch "$CONSENT_TEST_CLIENT_LOG"\n')
            stub.chmod(0o700)
        env = dict(os.environ, PATH=str(bindir)+os.pathsep+os.environ['PATH'],
                   HOME=str(task_home), CONSENT_TEST_CLIENT_LOG=str(log), SETUP_YES='1', PYTHONDONTWRITEBYTECODE='1')
        for script, args in [('setup.sh', ['--agent=none']), ('setup-vault.sh', []), ('setup-codex-plugins.sh', []),
                             ('setup-claude-plugins.sh', []), ('setup-plugins.sh', []), ('setup-mcp.sh', [])]:
            with self.subTest(script=script):
                run = subprocess.run(['bash', str(ROOT/'setup'/script), *args, str(self.workspace)],
                                     capture_output=True, text=True, env=env)
                self.assertEqual(run.returncode, 3, run.stdout+run.stderr)
                self.assertFalse(self.workspace.exists(), script)
                self.assertFalse(log.exists(), script)
                self.assertEqual(list(task_home.iterdir()), [], script)

    def test_update_decline_preserves_existing_notes(self):
        self.workspace.mkdir(); note = self.workspace/'Keep.md'; note.write_text('Human notes\n')
        run = subprocess.run(['bash', str(ROOT/'setup/setup-vault.sh'), '--update', str(self.workspace)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 3)
        self.assertEqual(note.read_text(), 'Human notes\n')
        self.assertEqual(sorted(p.name for p in self.workspace.iterdir()), ['Keep.md'])


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell unavailable')
class WindowsConsent(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='consent-ps-', dir='/private/tmp' if Path('/private/tmp').is_dir() else None)
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)/'workspace'
        self.policy = consent.load_policy(ROOT)

    def ps(self, body):
        helper = str(ROOT/'setup/license-consent.ps1').replace("'", "''")
        return subprocess.run(['pwsh', '-NoLogo', '-NoProfile', '-Command', ". '"+helper+"'; $ErrorActionPreference='Stop'; "+body], capture_output=True, text=True)

    def test_powershell_consent_parses(self):
        path = str(ROOT/'setup/license-consent.ps1').replace("'", "''")
        run = self.ps("$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('"+path+"', [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { $_.Message }; exit 1 }")
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)

    def test_powershell_headless_cannot_accept_or_write(self):
        run = self.ps(f"Confirm-AiosLicense -Workspace '{self.workspace}' -PackageRoot '{ROOT}'")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('interactive local console', run.stderr)
        self.assertFalse(self.workspace.exists())

    def test_python_record_is_accepted_by_windows_without_prompt(self):
        receipt = consent.make_receipt(self.policy, 'Synthetic Test User', 'personal')
        consent.save_receipt(self.workspace, self.policy, receipt)
        before = (self.workspace/consent.RECEIPT).read_bytes()
        run = self.ps(f"Confirm-AiosLicense -Workspace '{self.workspace}' -PackageRoot '{ROOT}'")
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), before)

    def test_powershell_history_migrates_exact_python_record_and_reuses_entries(self):
        first = consent.make_receipt(self.policy, 'Synthetic Python Person', 'personal')
        consent.save_receipt(self.workspace, self.policy, first)
        first_bytes = (self.workspace/consent.RECEIPT).read_bytes()
        # Simulate a pre-history installation; do not rewrite the old response.
        shutil.rmtree(self.workspace/consent.HISTORY)
        fixture = Path(self.temp.name)/'synthetic-response.json'
        second = consent.make_receipt(self.policy, 'Synthetic Windows Person', 'organization', 'Synthetic LLC', True, source='human-windows-console')
        fixture.write_text(json.dumps(second))
        body = f"$p=Get-AiosLicensePolicy '{ROOT}'; $r=Get-Content -Raw -LiteralPath '{fixture}' | ConvertFrom-Json; Save-AiosReceipt -Workspace '{self.workspace}' -Policy $p -Receipt $r; Save-AiosReceipt -Workspace '{self.workspace}' -Policy $p -Receipt $r"
        run = self.ps(body)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        current_bytes = (self.workspace/consent.RECEIPT).read_bytes()
        self.assertEqual({p.read_bytes() for p in (self.workspace/consent.HISTORY).iterdir()}, {first_bytes,current_bytes})
        self.assertTrue(consent.existing_receipt(self.workspace, self.policy))
        self.assertEqual(json.loads(current_bytes)['organization'], 'Synthetic LLC')
        # Python can then preserve the exact Windows response as well.
        third = consent.make_receipt(self.policy, 'Synthetic Third Person', 'personal')
        consent.save_receipt(self.workspace, self.policy, third)
        self.assertIn(current_bytes, {p.read_bytes() for p in (self.workspace/consent.HISTORY).iterdir()})

    def test_powershell_history_tamper_and_redirect_refuse_replacement(self):
        receipt = consent.make_receipt(self.policy, 'Synthetic Test User', 'personal')
        consent.save_receipt(self.workspace, self.policy, receipt)
        entry = next((self.workspace/consent.HISTORY).iterdir())
        entry.write_bytes(b'Edited historical response\n')
        before = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        body = f"$p=Get-AiosLicensePolicy '{ROOT}'; $r=Get-Content -Raw -LiteralPath '{self.workspace/consent.RECEIPT}' | ConvertFrom-Json; Save-AiosReceipt -Workspace '{self.workspace}' -Policy $p -Receipt $r"
        run = self.ps(body)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('history', run.stderr)
        self.assertEqual({str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}, before)
        shutil.rmtree(self.workspace/consent.HISTORY)
        outside = Path(self.temp.name)/'outside'; outside.mkdir()
        (self.workspace/consent.HISTORY).symlink_to(outside, target_is_directory=True)
        run = self.ps(body)
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual((self.workspace/consent.RECEIPT).read_bytes(), before[str(consent.RECEIPT)])

    def test_powershell_review_again_is_headless_safe(self):
        consent.save_receipt(self.workspace, self.policy, consent.make_receipt(self.policy, 'Synthetic Test User', 'personal'))
        before = {str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}
        run = self.ps(f"Confirm-AiosLicense -Workspace '{self.workspace}' -PackageRoot '{ROOT}' -ReviewAgain")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('interactive local console', run.stderr)
        self.assertEqual({str(p.relative_to(self.workspace)): p.read_bytes() for p in self.workspace.rglob('*') if p.is_file()}, before)

    def test_native_response_collection_uses_mocked_human_fields_and_never_writes(self):
        for answers, expected in [(['YES', 'Synthetic Test User', 'personal'], True),
                                  (['YES', 'Synthetic Test User', 'Personal'], True),
                                  (['YES', 'Synthetic Test User', 'Organization', 'Synthetic LLC', 'YES'], True),
                                  (['YES', 'Synthetic Test User', 'organization', 'Synthetic LLC', 'YES'], True),
                                  (['YES', 'Synthetic Test User', 'organization', 'Synthetic LLC', 'NO'], False),
                                  (['NO'], False)]:
            values = ','.join("'"+value+"'" for value in answers)
            body = f"$policy=Get-AiosLicensePolicy '{ROOT}'; $script:answers=@({values}); $script:index=0; function Read-Host {{ $result=$script:answers[$script:index]; $script:index++; return $result }}; $r=Read-AiosHumanResponse $policy; if (-not (Test-AiosReceipt $r $policy)) {{ exit 2 }}; Write-Output ('SYNTHETIC_RECEIPT:' + ($r | ConvertTo-Json -Compress))"
            run = self.ps(body)
            self.assertEqual(run.returncode == 0, expected, run.stdout+run.stderr)
            if expected:
                record_line = next(line for line in run.stdout.splitlines() if line.startswith('SYNTHETIC_RECEIPT:'))
                native_receipt = json.loads(record_line.partition(':')[2])
                self.assertTrue(consent.valid_receipt(native_receipt, self.policy), native_receipt)
            self.assertFalse(self.workspace.exists())

    def test_bootstrap_gates_before_wsl_and_uses_reviewed_package(self):
        text = (ROOT/'setup/setup-windows.ps1').read_text()
        self.assertLess(text.index('Confirm-AiosLicense -Workspace'), text.index('# Phase 2 — WSL install'))
        self.assertIn('$wslSetupArg = ConvertTo-BashLiteral', text)
        self.assertNotIn('git clone --', text)
        self.assertNotIn('git pull --ff-only', text)


if __name__ == '__main__':
    unittest.main()
