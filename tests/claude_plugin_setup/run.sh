#!/usr/bin/env bash
# Regression coverage for clients that automatically enable installed plugins.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
plugin_id = 'ai-os-lite@ai-os-lite-marketplace'
enabled = [{'id': plugin_id, 'scope': 'user', 'enabled': True}]
cases = [
    ('explicit enable succeeds', 0, '', 0, 0),
    ('install already enabled plugin', 1, json.dumps(enabled), 0, 0),
    ('disabled plugin remains failure', 1, json.dumps([
        {'id': plugin_id, 'scope': 'user', 'enabled': False}]), 0, 2),
    ('different plugin cannot mask failure', 1, json.dumps([
        {'id': 'unrelated@marketplace', 'scope': 'user', 'enabled': True}]), 0, 2),
    ('different scope cannot mask failure', 1, json.dumps([
        {'id': plugin_id, 'scope': 'project', 'enabled': True}]), 0, 2),
    ('invalid status cannot mask failure', 1, 'not JSON', 0, 2),
    ('failed list cannot mask failure', 1, json.dumps(enabled), 1, 2),
]
with tempfile.TemporaryDirectory(prefix='lite-plugin-regression-') as temp:
    fixture = Path(temp)
    setup = fixture / 'setup'
    (setup / 'tools').mkdir(parents=True)
    shutil.copyfile(root / 'setup/setup-claude-plugins.sh', setup / 'setup-claude-plugins.sh')
    # Unit-test boundary only: no receipt, real license response, CLI or login.
    (setup / 'tools/license_consent.py').write_text('raise SystemExit(0)\n')
    bin_dir = fixture / 'bin'
    bin_dir.mkdir()
    client = bin_dir / 'claude'
    client.write_text('''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if args[:2] == ['plugin', 'enable']:
    print('opaque enable diagnostic')
    sys.exit(int(os.environ['TEST_ENABLE_EXIT']))
if args == ['plugin', 'list', '--json']:
    print(os.environ['TEST_PLUGIN_JSON'])
    sys.exit(int(os.environ['TEST_LIST_EXIT']))
if args[:3] == ['plugin', 'marketplace', 'add'] or args[:2] == ['plugin', 'install']:
    sys.exit(0)
raise SystemExit('unexpected command')
''')
    client.chmod(0o755)
    for label, enable_exit, payload, list_exit, expected in cases:
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                   TEST_ENABLE_EXIT=str(enable_exit), TEST_PLUGIN_JSON=payload,
                   TEST_LIST_EXIT=str(list_exit))
        result = subprocess.run(['bash', str(setup / 'setup-claude-plugins.sh'),
                                 str(fixture / 'workspace')], env=env,
                                text=True, capture_output=True)
        assert result.returncode == expected, (label, result.returncode, result.stdout, result.stderr)
        assert ('=== AI-OS Lite Installed ===' in result.stdout) == (expected == 0), label
        if enable_exit and expected == 0:
            assert 'already enabled (verified' in result.stdout, label
        print('PASS:', label)
PY
