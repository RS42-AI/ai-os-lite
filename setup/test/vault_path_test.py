"""Run real installers in child processes whose home is disposable.

HOME keeps its ordinary meaning for those child processes only. The host shell,
Git configuration, real vault and assistant accounts are never changed.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from license_consent import load_policy, make_receipt, save_receipt


def seed_synthetic_review(workspace):
    # Disposable fixture only; tests do not supply a human's legal assent.
    policy = load_policy(ROOT.parent)
    save_receipt(workspace, policy, make_receipt(policy, 'Synthetic Test User', 'personal'))


def snapshot(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in directory.rglob('*')
            if p.is_file() and '.git' not in p.relative_to(directory).parts}


class VaultPathSelection(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='lite-paths-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.task_home = self.root / "Example Person's Home"
        self.task_home.mkdir()
        self.env = dict(os.environ, HOME=str(self.task_home),
                        XDG_CONFIG_HOME=str(self.task_home/'.config'),
                        GIT_CONFIG_GLOBAL=str(self.root/'empty.gitconfig'),
                        GIT_CONFIG_NOSYSTEM='1', PYTHONDONTWRITEBYTECODE='1')
        self.legacy = self.task_home/'Claude/ObsidianVault'
        self.previous_default = self.task_home/'MyVault'
        self.custom = self.task_home/'My Custom Vault'
        for directory in [self.legacy, self.previous_default, self.custom]:
            directory.mkdir(parents=True)
            (directory/'Keep.md').write_text('Existing human notes must stay unchanged.\n')

    def run_installer(self, script, *args):
        return subprocess.run(['bash', str(ROOT/script), *args], env=self.env,
                              cwd=self.root, capture_output=True, text=True)

    def assert_success(self, run):
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_real_default_vault_creation_and_repeat_preserve_other_roots(self):
        seed_synthetic_review(self.task_home/'AIOS')
        untouched = {p: snapshot(p) for p in [self.legacy, self.previous_default, self.custom]}
        self.assert_success(self.run_installer('setup-vault.sh'))
        fresh = self.task_home/'AIOS'
        self.assertTrue((fresh/'AGENTS.md').is_file())
        self.assertFalse((fresh/'Vault').exists())
        self.assertTrue((fresh/'Personal/2. Projects/Vault-Setup/Vault-Setup.md').is_file())
        (fresh/'6. Main Notes/Keep.md').write_text('New vault, preserved human text.\n')
        first = snapshot(fresh)
        self.assert_success(self.run_installer('setup-vault.sh'))
        self.assertEqual(snapshot(fresh), first)
        for directory, before in untouched.items():
            self.assertEqual(snapshot(directory), before)
        self.assertFalse((fresh/'.obsidian/plugins').exists())

    def test_real_combined_vault_only_default_creation_and_repeat_preserve_other_roots(self):
        seed_synthetic_review(self.task_home/'AIOS')
        untouched = {p: snapshot(p) for p in [self.legacy, self.previous_default, self.custom]}
        self.assert_success(self.run_installer('setup.sh', '--agent=none'))
        fresh = self.task_home/'AIOS'
        self.assertTrue((fresh/'AGENTS.md').is_file())
        self.assertFalse((fresh/'Vault').exists())
        (fresh/'6. Main Notes/Keep.md').write_text('New vault, preserved human text.\n')
        first = snapshot(fresh)
        self.assert_success(self.run_installer('setup.sh', '--agent=none'))
        self.assertEqual(snapshot(fresh), first)
        for directory, before in untouched.items():
            self.assertEqual(snapshot(directory), before)
        self.assertFalse((fresh/'.obsidian/plugins').exists())
        self.assertFalse((self.task_home/'.claude').exists())
        self.assertFalse((self.task_home/'.codex').exists())

    def test_explicit_space_and_apostrophe_path_wins_and_workflow_env_is_not_installer_target(self):
        seed_synthetic_review(self.custom)
        self.env['PERSONAL_OS_VAULT'] = str(self.legacy)
        original = snapshot(self.legacy)
        before_custom = (self.custom/'Keep.md').read_bytes()
        for script, args in [('setup-vault.sh', []), ('setup.sh', ['--agent=none'])]:
            with self.subTest(script=script):
                self.assert_success(self.run_installer(script, *args, str(self.custom)))
                self.assertEqual((self.custom/'Keep.md').read_bytes(), before_custom)
                self.assertEqual(snapshot(self.legacy), original)
                self.assertFalse((self.task_home/'AIOS').exists())
        # No positional path selects the fresh default even when the workflow env is set.
        seed_synthetic_review(self.task_home/'AIOS')
        self.assert_success(self.run_installer('setup.sh', '--agent=none'))
        self.assertTrue((self.task_home/'AIOS/AGENTS.md').is_file())
        self.assertEqual(snapshot(self.legacy), original)

    def test_update_without_explicit_path_stops_without_modifying_existing_default(self):
        fresh = self.task_home/'AIOS'
        fresh.mkdir(parents=True); (fresh/'Keep.md').write_text('Already exists.\n')
        before = snapshot(self.task_home)
        for args in [('--update',), ('--update', ''), ('--update', '--edition=team')]:
            with self.subTest(args=args):
                run = self.run_installer('setup-vault.sh', *args)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn('requires an explicit existing vault path', run.stdout)
                self.assertNotIn('Target vault:', run.stdout)
                self.assertEqual(snapshot(self.task_home), before)

    def test_explicit_update_keeps_location_and_missing_instructions(self):
        seed_synthetic_review(self.custom)
        legacy_before = snapshot(self.legacy)
        self.assert_success(self.run_installer('setup-vault.sh', '--update', str(self.custom)))
        self.assertEqual((self.custom/'Keep.md').read_text(), 'Existing human notes must stay unchanged.\n')
        self.assertEqual((self.custom/'.vault-kit-path').read_text().strip(), str(ROOT))
        self.assertFalse((self.custom/'AGENTS.md').exists())
        self.assertFalse((self.custom/'CLAUDE.md').exists())
        self.assertFalse((self.task_home/'AIOS').exists())
        self.assertEqual(snapshot(self.legacy), legacy_before)


if __name__ == '__main__':
    unittest.main()
