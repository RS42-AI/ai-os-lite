#!/usr/bin/env python3
"""Exercise real workflow helpers with isolated HOME and distinct vault contents."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / 'plugins/ai-os-lite/skills'
DATE = '2026-10-13'
JOURNAL = f'5. Resources/Personal/Journal/Morning Entries/{DATE}.md'


class VaultPathsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='lite-workflow-paths-')
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.paths = {
            'default': self.home / 'AIOS',
            'environment': self.base / 'configured workspace',
            'explicit': self.base / 'chosen workspace',
            'legacy': self.home / 'Claude/ObsidianVault',
        }
        for label, vault in self.paths.items():
            vault.mkdir(parents=True)
            shutil.copyfile(ROOT / 'fixtures/write-note/AGENTS.md', vault / 'AGENTS.md')
            self.note(vault, f'Personal/Tasks/{label}-marker.md',
                      'type: task\nstatus: todo\narea: personal\npriority: p2', 'selection-token')
            self.note(vault, f'Personal/2. Projects/{label}-course/{label}-course.md',
                      'type: project\nstatus: draft\narea: personal\nproject: course', label)
            links = '\n'.join(f'[[{label}-marker]]' for _ in range(list(self.paths).index(label) + 1))
            self.note(vault, JOURNAL, 'type: journal\narea: personal', '## Recent Accomplishments\n' + links)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        # Use this test's actual Python interpreter rather than a user shim.
        (self.bin / 'python3').symlink_to(sys.executable)
        self.obsidian_marker = self.base / 'obsidian-called'
        (self.bin / 'obsidian').write_text('#!/bin/sh\nprintf called > "$TASK_OBSIDIAN_MARKER"\nprintf wrong-vault >> "$TASK_WRONG_VAULT_FILE"\nexit 0\n')
        (self.bin / 'obsidian').chmod(0o755)
        (self.bin / 'td').write_text('#!/bin/sh\nexit 99\n')
        (self.bin / 'td').chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PYTHONDONTWRITEBYTECODE='1',
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull,
                        AI_OS_LOCAL_ONLY='1', TASK_OBSIDIAN_MARKER=str(self.obsidian_marker),
                        TASK_WRONG_VAULT_FILE=str(self.paths['legacy'] / 'sentinel.txt'),
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        self.env.pop('PERSONAL_OS_VAULT', None)
        self.env.pop('VAULT', None)
        (self.paths['legacy'] / 'sentinel.txt').write_text('untouched legacy workspace\n')
        self.legacy_before = self.snapshot(self.paths['legacy'])

    def tearDown(self):
        try:
            self.assertEqual(self.legacy_before, self.snapshot(self.paths['legacy']))
        finally:
            self.temp.cleanup()

    @staticmethod
    def snapshot(vault):
        return {str(p.relative_to(vault)): p.read_bytes() for p in vault.rglob('*') if p.is_file()}

    @staticmethod
    def note(vault, relative, fields, body=''):
        path = vault / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('---\n' + fields + '\n---\n' + body + '\n')
        return path

    def selection(self, mode):
        env = self.env.copy()
        args = []
        if mode in ('environment', 'explicit'):
            env['PERSONAL_OS_VAULT'] = str(self.paths['environment'])
        if mode == 'explicit':
            args = [str(self.paths['explicit'])]
        return env, args

    def run_helper(self, helper, args, env, check=True):
        interpreter = sys.executable if helper.endswith('.py') else 'bash'
        result = subprocess.run([interpreter, str(SKILLS / helper), *args], env=env,
                                cwd=self.base, text=True, capture_output=True, timeout=60)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def test_read_helpers_resolve_actual_omitted_env_and_explicit_paths(self):
        for mode in ('default', 'environment', 'explicit'):
            env, selected_args = self.selection(mode)
            with self.subTest(mode=mode):
                matched = self.run_helper('start-day/scripts/match_task_note.sh', ['selection-token', *selected_args], env)
                self.assertEqual(matched.stdout.strip(), f'Personal/Tasks/{mode}-marker.md')
                audit = json.loads(self.run_helper('start-day/scripts/audit_journal_links.sh', [DATE, *selected_args], env).stdout)
                self.assertEqual(audit['checked'], list(self.paths).index(mode) + 1)
                self.assertTrue(audit['ok'])
                plan = json.loads(self.run_helper('process-morning/scripts/gather_daily_plan_context.py', [DATE, *selected_args], env).stdout)
                self.assertEqual([Path(t['path']).stem for t in plan['tasks']], [mode + '-marker'])
                morning = json.loads(self.run_helper('start-day/scripts/gather_morning_context.sh', [DATE, *selected_args], env).stdout)
                self.assertEqual([Path(t['path']).stem for t in morning['task_notes']['tasks']], [mode + '-marker'])
                project = json.loads(self.run_helper('project-sync/scripts/gather_project_context.sh', ['course', *selected_args], env).stdout)
                self.assertEqual(project['project']['project_name'], mode + '-course')
        self.assertFalse(self.obsidian_marker.exists())

    def test_writers_and_commit_helpers_keep_selected_vault(self):
        for index, mode in enumerate(('default', 'environment', 'explicit')):
            env, selected_args = self.selection(mode)
            date = f'2026-10-{20 + index}'
            for helper, relative in (
                ('ensure_daily_hub.sh', f'1. Daily/{date}.md'),
                ('ensure_journal.sh', f'5. Resources/Personal/Journal/Morning Entries/{date}.md'),
            ):
                with self.subTest(mode=mode, helper=helper):
                    result = json.loads(self.run_helper('start-day/scripts/' + helper, [date, *selected_args], env).stdout)
                    self.assertTrue(result['created'])
                    self.assertTrue((self.paths[mode] / relative).is_file())
                    self.assertTrue(all(not (vault / relative).exists() for label, vault in self.paths.items() if label != mode))
            # These fixture vaults have no Git repository: no commit or staging.
            for helper in ('start-day/scripts/commit_daily_scaffold.sh', 'process-morning/scripts/commit_journal_processing.sh'):
                with self.subTest(mode=mode, helper=helper):
                    result = json.loads(self.run_helper(helper, [DATE, *selected_args], env).stdout)
                    self.assertFalse(result['committed'])
                    self.assertIn(str(self.paths[mode]), result['error'])

    def test_git_gather_and_library_overrides(self):
        for mode in ('default', 'environment', 'explicit'):
            env, selected_args = self.selection(mode)
            subprocess.run(['git', 'init', '-q', str(self.paths[mode])], env=env, check=True)
            with self.subTest(mode=mode):
                data = json.loads(self.run_helper('vault-commit/scripts/gather_git_context.sh', selected_args, env).stdout)
                text = json.dumps(data)
                self.assertIn(mode + '-marker', text)
                self.assertNotIn('legacy-marker', text)
                self.assertNotEqual(subprocess.run(['git', '-C', str(self.paths[mode]), 'rev-parse', '--verify', 'HEAD'], env=env, capture_output=True).returncode, 0)
                if mode == 'explicit':
                    env['VAULT'] = str(self.paths['explicit'])
                path = subprocess.check_output(['bash', '-c', 'source "$1"; obs_path probe.md', '_', str(SKILLS / 'process-morning/scripts/lib.sh')], env=env, text=True).strip()
                self.assertEqual(path, str(self.paths[mode] / 'probe.md'))
        # Empty configured values retain the documented default fallback.
        env = dict(self.env, PERSONAL_OS_VAULT='', VAULT='')
        plan = json.loads(self.run_helper('process-morning/scripts/gather_daily_plan_context.py', [DATE], env).stdout)
        self.assertEqual([Path(t['path']).stem for t in plan['tasks']], ['default-marker'])

    def test_privacy_stamps_selected_files_not_active_obsidian_vault(self):
        vault = self.paths['environment']
        self.note(vault, 'Personal/2. Projects/Quiet/Quiet.md', 'type: project\nstatus: draft\narea: personal\nproject: quiet\nprivate: true')
        private = self.note(vault, 'Personal/2. Projects/Quiet/Notes/Private.md', f'date: {DATE}\ntype: note\nstatus: capture\narea: personal\nproject: quiet', 'preserve the body')
        shared = self.note(vault, 'Personal/2. Projects/Quiet/Notes/Shared.md', f'date: {DATE}\ntype: note\nstatus: capture\narea: personal\nproject: quiet\nprivate: false', 'keep the override')
        shared_before = shared.read_bytes()
        env = dict(self.env, PERSONAL_OS_VAULT=str(vault), AI_OS_LOCAL_ONLY='0')
        result = json.loads(self.run_helper('start-day/scripts/gather_morning_context.sh', [DATE], env).stdout)
        self.assertIn('private: true\n', private.read_text())
        self.assertIn('preserve the body', private.read_text())
        self.assertEqual(shared_before, shared.read_bytes())
        self.assertNotIn('Notes/Private.md', json.dumps(result))
        self.assertFalse(self.obsidian_marker.exists())
        before = private.read_bytes()
        self.run_helper('start-day/scripts/gather_morning_context.sh', [DATE], env)
        self.assertEqual(before, private.read_bytes())

    def test_missing_or_uninitialized_default_refuses_writes(self):
        writers = ('start-day/scripts/ensure_daily_hub.sh', 'start-day/scripts/ensure_journal.sh',
                   'start-day/scripts/gather_morning_context.sh', 'start-day/scripts/commit_daily_scaffold.sh',
                   'process-morning/scripts/commit_journal_processing.sh')
        for state in ('uninitialized', 'missing'):
            default = self.paths['default']
            if state == 'uninitialized':
                (default / 'AGENTS.md').unlink()
            else:
                shutil.rmtree(default)
            before = self.snapshot(default)
            for helper in writers:
                with self.subTest(state=state, helper=helper):
                    result = self.run_helper(helper, [DATE], self.env, check=False)
                    self.assertIn('Default workspace instructions not found', result.stdout + result.stderr)
                    if '/commit_' in helper:
                        self.assertFalse(json.loads(result.stdout)['committed'])
                    else:
                        self.assertNotEqual(result.returncode, 0)
            self.assertEqual(before, self.snapshot(default))
            if state == 'missing':
                self.assertFalse(default.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
