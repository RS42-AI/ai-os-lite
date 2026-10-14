#!/usr/bin/env python3
"""Check the complete candidate, including files not yet added to Git."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT
).decode().split('\0')
errors = []
private_patterns = []
if os.environ.get('AI_OS_PRIVATE_PATTERN_FILE'):
    pattern_file = Path(os.environ['AI_OS_PRIVATE_PATTERN_FILE'])
    private_patterns = [p for p in pattern_file.read_text().splitlines() if p and not p.startswith('#')]
for name in sorted(set(paths)):
    if not name or not (ROOT / name).is_file():
        continue
    if 'docs/superpowers/' in name:
        errors.append(f'{name}: internal development record included')
    data = (ROOT / name).read_bytes()
    if b'\0' in data:
        continue
    try:
        source = data.decode('utf-8')
    except UnicodeDecodeError:
        continue
    # Test fixtures deliberately exercise unsafe inputs; do not treat them as published user content.
    is_test = name.startswith(('tests/', 'fixtures/', 'setup/test/', 'scripts/'))
    if not is_test:
        for i, line in enumerate(source.splitlines(), 1):
            if re.search(r'(?<!/c)/Users/(?!<|\$|\{)', line):
                errors.append(f'{name}:{i}: machine-specific home path')
            for pattern in private_patterns:
                if pattern.casefold() in line.casefold() and not line.startswith('> Copyright © 2026 Yandi Farinango / RandomStateLabs.'):
                    errors.append(f'{name}:{i}: configured private pattern')
            if re.search(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{32,}|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----)', line):
                errors.append(f'{name}:{i}: possible secret')
    # Check navigable README/document links. Wiki links in starter notes are resolved by Obsidian.
    if name == 'README.md' or name.startswith('docs/'):
        source = re.sub(r'```.*?```', '', source, flags=re.S)
        for match in re.finditer(r'!?\[[^\]]*\]\(([^\n]+?)\)', source):
            dest = match.group(1).strip().split(' "', 1)[0].strip('<>')
            parsed = urlsplit(dest)
            if parsed.scheme or dest.startswith(('#', '//')):
                continue
            path = (ROOT / name).parent / unquote(parsed.path)
            if not path.exists():
                errors.append(f'{name}: missing local link {dest}')
for manifest in ['.claude-plugin/marketplace.json', '.agents/plugins/marketplace.json',
                 'plugins/ai-os-lite/.claude-plugin/plugin.json', 'plugins/ai-os-lite/.codex-plugin/plugin.json']:
    json.loads((ROOT / manifest).read_text())
if errors:
    print('\n'.join(errors), file=sys.stderr)
    raise SystemExit(1)
print('PASS: complete candidate privacy patterns, JSON, and documentation links')
