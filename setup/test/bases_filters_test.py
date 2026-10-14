"""Check the equality/and/or subset used by shipped active-task Bases.

This is a narrow contract check, not the Obsidian renderer. Live GUI acceptance
must independently confirm the actual app displays the starter tasks.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'vault-files'
TARGETS = {
    'Personal/2. Projects/Vault-Setup/Vault-Setup.md': ('project', 'vault-setup'),
    'Personal/Personal.md': ('area', 'personal'),
    'system-settings/Templates/Area Dashboard Template.md': ('area', '{{VALUE:area slug}}'),
}


def predicate(expression, properties):
    match = re.fullmatch(r'([a-z_]+) == "([^"]*)"', expression.strip())
    if not match:
        raise ValueError(f'Unsupported Bases predicate: {expression}')
    key, value = match.groups()
    return properties.get(key) == value


def matches(source, properties):
    section = source.split('## Active Tasks\n', 1)[1].split('```base\n', 1)[1].split('```', 1)[0]
    lines = section.split('views:', 1)[0].splitlines()
    if lines[:2] != ['filters:', '  and:']:
        raise ValueError('Expected a global and filter')
    terms = []
    i = 2
    while i < len(lines):
        line = lines[i]
        if line == '    - or:':
            group = []
            i += 1
            while i < len(lines) and lines[i].startswith('        - '):
                group.append(predicate(lines[i][10:], properties))
                i += 1
            if not group:
                raise ValueError('Empty or group')
            terms.append(any(group))
            continue
        if not line.startswith('    - '):
            raise ValueError(f'Unexpected filter structure: {line}')
        terms.append(predicate(line[6:], properties))
        i += 1
    return all(terms)


class ActiveTaskBases(unittest.TestCase):
    def test_shipped_views_include_open_states_and_exclude_other_work(self):
        for relative, (routing_key, routing_value) in TARGETS.items():
            source = (ROOT / relative).read_text()
            for state in ['todo', 'active', 'on-hold', 'done', 'archived']:
                properties = {'type': 'task', routing_key: routing_value, 'status': state}
                with self.subTest(view=relative, state=state):
                    self.assertEqual(matches(source, properties), state in ['todo', 'active'])
                    self.assertFalse(matches(source, dict(properties, type='note')))
                    self.assertFalse(matches(source, dict(properties, **{routing_key: 'another-scope'})))

    def test_onboarding_view_finds_all_three_actual_starter_tasks(self):
        project = ROOT / 'Personal/2. Projects/Vault-Setup'
        source = (project / 'Vault-Setup.md').read_text()
        found = []
        for task in sorted((project / 'Tasks').glob('*.md')):
            properties = dict(re.findall(r'^(type|project|status): ([^\n]+)$', task.read_text().split('---', 2)[1], re.M))
            if matches(source, properties):
                found.append(task.stem)
        self.assertEqual(found, ['Add my first project', 'Set up my AGENTS', 'Set up my first goal'])


if __name__ == '__main__':
    unittest.main()
