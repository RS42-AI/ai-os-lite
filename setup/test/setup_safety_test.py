"""Offline installer regression tests; fake downloads never contact services."""
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from license_consent import load_policy, make_receipt, save_receipt
IDS = ['terminal', 'obsidian-linter', 'templater-obsidian', 'dataview', 'obsidian-git', 'obsidian-local-rest-api', 'mcp-tools', 'editing-toolbar', 'obsidian-excalidraw-plugin', 'smart-connections']


class SetupSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.vault = self.root / 'My Vault'
        self.vault.mkdir()
        # Synthetic, disposable test fixture; never a real human agreement.
        policy = load_policy(ROOT.parent)
        save_receipt(self.vault, policy, make_receipt(policy, 'Synthetic Test User', 'personal'))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        curl = self.bin / 'curl'
        curl.write_text('''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
args=sys.argv[1:]; url=next(x for x in args if x.startswith('https://')); out=pathlib.Path(args[args.index('-o')+1])
ids={'obsidian-terminal':'terminal','obsidian-linter':'obsidian-linter','Templater':'templater-obsidian','obsidian-dataview':'dataview','obsidian-git':'obsidian-git','obsidian-local-rest-api':'obsidian-local-rest-api','obsidian-mcp-tools':'mcp-tools','obsidian-editing-toolbar':'editing-toolbar','obsidian-excalidraw-plugin':'obsidian-excalidraw-plugin','obsidian-smart-connections':'smart-connections'}
parts=url.split('/'); repo=parts[5] if parts[2]=='api.github.com' else parts[4]; plugin=ids[repo]
with open(os.environ['FAKE_LOG'],'a') as log: log.write(url+'\\n')
if os.environ.get('FAKE_FAIL')==plugin:
    out.write_text('<html>404</html>');sys.exit(22)
license_name={'terminal':'LICENSE.txt','templater-obsidian':'LICENSE.TXT'}.get(plugin,'LICENSE')
if url.endswith('/releases/latest'):
    out.write_text(json.dumps({'tag_name':'v1.0.0','draft':False,'prerelease':False,'assets':[{'name':x} for x in ['main.js','manifest.json','styles.css','NOTICE.txt']]}))
elif '/git/trees/' in url:
    names=[] if os.environ.get('FAKE_NO_LICENSE')==plugin else [license_name]
    names+=['NOTICE.md']
    out.write_text(json.dumps({'sha':'abc123','tree':[{'path':x,'type':'blob','mode':'100644'} for x in names]}))
elif url.endswith((license_name,'NOTICE.md','NOTICE.txt')):
    if os.environ.get('FAKE_NOTICE_FAIL')==plugin: sys.exit(22)
    out.write_text('<html>wrong response</html>' if os.environ.get('FAKE_NOTICE_HTML')==plugin else 'Copyright Synthetic Upstream.\\nFixture permission notice.\\n')
elif url.endswith('manifest.json'):
    out.write_text(json.dumps({'id': 'wrong' if os.environ.get('FAKE_BAD_ID')==plugin else plugin,'version':'1.0.0'}))
else:out.write_text('// offline fixture\\n')
''')
        curl.chmod(0o755)
        copy = self.bin/'cp'
        copy.write_text('''#!/usr/bin/env python3
import os, subprocess, sys
if os.environ.get('FAKE_COPY_FAIL') and sys.argv[-1].rstrip('/').endswith('/terminal'):
    stage=os.environ['FAKE_COPY_FAIL']
    if (stage=='notices' and 'upstream-notices' in sys.argv[-2]) or (stage=='runtime' and any(x.endswith('main.js') for x in sys.argv)) or (stage=='styles' and any(x.endswith('styles.css') for x in sys.argv)):
        sys.exit(1)
sys.exit(subprocess.call(['/bin/cp',*sys.argv[1:]]))
''')
        copy.chmod(0o755)
        temp = self.bin/'mktemp'
        temp.write_text('#!/bin/sh\n[ "${FAKE_MKTEMP_FAIL:-0}" != 1 ] || exit 1\nexec /usr/bin/mktemp "$@"\n')
        temp.chmod(0o755)
        self.log = self.bin/'downloads.log'
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], FAKE_LOG=str(self.log))

    def run_script(self, name, *args, env=None):
        return subprocess.run(['/bin/bash', str(ROOT/name), *args, str(self.vault)], env=env or self.env, capture_output=True, text=True)

    def test_plugin_settings_and_enabled_list_survive_repeat(self):
        settings = self.vault/'.obsidian/plugins'
        originals = {}
        for plugin in ['terminal','obsidian-linter','templater-obsidian','obsidian-git']:
            path=settings/plugin/'data.json';path.parent.mkdir(parents=True)
            raw=b'{ "custom": "keep exactly" }\n';path.write_bytes(raw);originals[path]=raw
        enabled=self.vault/'.obsidian/community-plugins.json';enabled.write_text('["my-existing-plugin"]')
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        for path, raw in originals.items():self.assertEqual(path.read_bytes(),raw)
        self.assertEqual(set(json.loads(enabled.read_text())),set(IDS+['my-existing-plugin']))
        first=enabled.read_bytes()
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual(enabled.read_bytes(),first)

    def test_http_failure_reports_partial_and_rerun_recovers(self):
        run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_FAIL='terminal'))
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertNotIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))
        self.assertFalse((self.vault/'.obsidian/plugins/terminal/main.js').exists())
        self.assertIn('INCOMPLETE:',run.stdout)
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))

    def test_wrong_manifest_is_rejected(self):
        run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_BAD_ID='dataview'))
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertFalse((self.vault/'.obsidian/plugins/dataview/main.js').exists())

    def test_downloads_one_tag_and_preserves_source_and_release_notices(self):
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        directory=self.vault/'.obsidian/plugins/terminal/upstream-notices'
        receipt=json.loads((directory/'provenance.json').read_text())
        self.assertEqual(receipt['release_tag'],'v1.0.0')
        self.assertEqual({item['path'] for item in receipt['notices']}, {'source/LICENSE.txt','source/NOTICE.md','release/NOTICE.txt'})
        import hashlib
        for item in receipt['notices']:
            self.assertEqual(hashlib.sha256((directory/item['path']).read_bytes()).hexdigest(),item['sha256'])
        urls=self.log.read_text().splitlines()
        self.assertFalse(any('/releases/latest/download/' in url or '/main/' in url or '/master/' in url for url in urls))
        for url in urls:
            if '/releases/latest' not in url:
                self.assertIn('/v1.0.0/',url+'/' if '/git/trees/' in url else url)

    def test_missing_or_html_notices_never_install_or_enable_plugin(self):
        for flag in ['FAKE_NOTICE_FAIL','FAKE_NOTICE_HTML','FAKE_NO_LICENSE']:
            with self.subTest(flag=flag):
                run=self.run_script('setup-plugins.sh',env=dict(self.env,**{flag:'terminal'}))
                self.assertEqual(run.returncode,2,run.stdout+run.stderr)
                self.assertFalse((self.vault/'.obsidian/plugins/terminal/main.js').exists())
                self.assertNotIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))
                self.assertIn('release or notices unavailable',run.stdout)
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertTrue((self.vault/'.obsidian/plugins/terminal/upstream-notices/source/LICENSE.txt').exists())

    def test_existing_plugin_and_settings_are_not_replaced_or_claimed_audited(self):
        directory=self.vault/'.obsidian/plugins/terminal';directory.mkdir(parents=True)
        files={'main.js':b'// human-installed version\\n','manifest.json':b'{"id":"terminal","version":"older"}',
               'data.json':b'{"human":"keep"}'}
        for name,data in files.items():(directory/name).write_bytes(data)
        run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_NOTICE_FAIL='terminal'))
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        for name,data in files.items():self.assertEqual((directory/name).read_bytes(),data)
        self.assertIn('existing notices not audited or replaced',run.stdout)
        self.assertFalse((directory/'upstream-notices').exists())
        self.assertFalse(any('polyipseity/obsidian-terminal/' in url for url in self.log.read_text().splitlines()))

    def test_notice_copy_failure_prevents_runtime_install_and_preserves_settings(self):
        directory=self.vault/'.obsidian/plugins/terminal';directory.mkdir(parents=True)
        settings=b'{"human":"keep"}';(directory/'data.json').write_bytes(settings)
        for stage in ['notices','runtime']:
            with self.subTest(stage=stage):
                run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_COPY_FAIL=stage))
                self.assertEqual(run.returncode,2,run.stdout+run.stderr)
                self.assertFalse((directory/'main.js').exists())
                self.assertEqual((directory/'data.json').read_bytes(),settings)
                self.assertNotIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))
                self.assertNotIn('INSTALLED: terminal',run.stdout)

    def test_staging_failure_never_downloads_to_current_directory(self):
        run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_MKTEMP_FAIL='1'))
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertIn('cannot create terminal staging directory',run.stdout)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.vault/'.obsidian/plugins/terminal/main.js').exists())

    def test_partial_runtime_copy_is_retried_before_plugin_is_newly_enabled(self):
        run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_COPY_FAIL='styles'))
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        directory=self.vault/'.obsidian/plugins/terminal'
        self.assertTrue((directory/'main.js').exists())
        self.assertTrue((directory/'.ai-os-install-incomplete').exists())
        self.assertNotIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))
        settings=(directory/'data.json').read_bytes()
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('INSTALLED: terminal',run.stdout)
        self.assertFalse((directory/'.ai-os-install-incomplete').exists())
        self.assertTrue((directory/'styles.css').exists())
        self.assertIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))
        self.assertEqual((directory/'data.json').read_bytes(),settings)

    def test_invalid_existing_enabled_json_stops_before_download(self):
        enabled=self.vault/'.obsidian/community-plugins.json';enabled.parent.mkdir();enabled.write_text('{bad}')
        run=self.run_script('setup-plugins.sh');self.assertNotEqual(run.returncode,0)
        self.assertEqual(enabled.read_text(),'{bad}');self.assertFalse((self.vault/'.obsidian/plugins').exists())

    def test_unborn_git_and_custom_files_survive_rerun(self):
        subprocess.run(['git','-C',str(self.vault),'init','-q'],check=True)
        preserved={'AGENTS.md':b'Human instructions\n','CLAUDE.md':b'@AGENTS.md\n','.gitignore':b'custom-secret\n','.claude/commands/update-structure.md':b'custom command\n'}
        for relative,raw in preserved.items():
            path=self.vault/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
        for _ in range(2):
            run=self.run_script('setup-vault.sh','--update');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn('create your first backup commit',run.stdout)
        for relative,raw in preserved.items():self.assertEqual((self.vault/relative).read_bytes(),raw)

    def test_symlink_target_is_rejected_without_writes(self):
        outside=self.root/'outside';outside.mkdir();(self.vault/'system-settings').symlink_to(outside,target_is_directory=True)
        run=self.run_script('setup-vault.sh');self.assertNotEqual(run.returncode,0)
        self.assertEqual(list(outside.iterdir()),[])
        self.assertFalse((self.vault/'1. Daily').exists())

    def test_custom_html_reference_blocks_migration(self):
        project=self.vault/'Personal/Example';project.mkdir(parents=True)
        (project/'Example.md').write_text('---\ntype: project\n---\n')
        page=self.vault/'Index.html';page.write_text('<a href="Personal/Example/Example.md">Keep me</a>')
        preview=self.vault/'.vault-structure-preview.json'
        run=subprocess.run(['python3',str(ROOT/'tools/project_structure.py'),'plan','--vault',str(self.vault),'--output',str(preview)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        plan=json.loads(preview.read_text())
        self.assertEqual(plan['blocked_binary_consumers'][0]['path'],'Index.html')
        self.assertEqual(page.read_text(),'<a href="Personal/Example/Example.md">Keep me</a>')

    def test_update_then_legacy_goal_migration_does_not_self_collide(self):
        goals=self.vault/'Personal/Goals';goals.mkdir(parents=True)
        (goals/'Keep.md').write_text('goal evidence\n')
        run=self.run_script('setup-vault.sh','--update');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertFalse((self.vault/'Personal/1. Goals').exists())
        preview=self.vault/'.vault-structure-preview.json'
        helper=['python3',str(ROOT/'tools/project_structure.py')]
        run=subprocess.run(helper+['plan','--vault',str(self.vault),'--output',str(preview)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        plan=json.loads(preview.read_text());self.assertEqual(plan['moves'][0]['status'],'ready')
        run=subprocess.run(helper+['apply','--vault',str(self.vault),'--plan',str(preview),'--approval-token',plan['approval_token']],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertEqual((self.vault/'Personal/1. Goals/Keep.md').read_text(),'goal evidence\n')

    def test_linter_defaults_do_not_insert_status_and_ignore_instructions(self):
        run=self.run_script('setup-plugins.sh');self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        config=json.loads((self.vault/'.obsidian/plugins/obsidian-linter/data.json').read_text())
        rule=config['ruleConfigs']['insert-yaml-attributes']
        self.assertFalse(rule['enabled']);self.assertEqual(rule['text-to-insert'],'')
        patterns=[re.compile(item['match']) for item in config['filesToIgnore']]
        for name in ['AGENTS.md','CLAUDE.md','Nested/AGENTS.md','Nested/CLAUDE.md']:
            self.assertTrue(any(pattern.search(name) for pattern in patterns),name)
        self.assertFalse(any(pattern.search('Notes/Normal.md') for pattern in patterns))

    def test_cached_html_download_is_not_enabled_when_retry_fails(self):
        directory=self.vault/'.obsidian/plugins/terminal';directory.mkdir(parents=True)
        (directory/'main.js').write_text('<html>old failed download</html>')
        (directory/'manifest.json').write_text(json.dumps({'id':'terminal','version':'1.0.0'}))
        run=self.run_script('setup-plugins.sh',env=dict(self.env,FAKE_FAIL='terminal'))
        self.assertEqual(run.returncode,2,run.stdout+run.stderr)
        self.assertNotIn('terminal',json.loads((self.vault/'.obsidian/community-plugins.json').read_text()))

    def test_parser_rejects_ambiguous_input_and_help_is_read_only(self):
        before = {str(p.relative_to(self.vault)): p.read_bytes()
                  for p in self.vault.rglob('*') if p.is_file()}
        for args, expected in [(['--dry-run'],1),(['--edition'],1),(['--edition','--update'],1),([str(self.vault),'extra'],1),(['--help'],0)]:
            with self.subTest(args=args):
                run=subprocess.run(['/bin/bash',str(ROOT/'setup-vault.sh'),*args],cwd=self.root,capture_output=True,text=True)
                self.assertEqual(run.returncode,expected,run.stdout+run.stderr)
                self.assertEqual({str(p.relative_to(self.vault)): p.read_bytes()
                                  for p in self.vault.rglob('*') if p.is_file()}, before)
                self.assertEqual(set(p.name for p in self.root.iterdir()),{'My Vault','bin'})


if __name__ == '__main__':
    unittest.main()
