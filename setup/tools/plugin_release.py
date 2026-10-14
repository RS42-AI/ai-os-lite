"""Stage one upstream Obsidian release with its matching license notices.

No plugin code is executed. The caller installs the staging directory only
after this helper succeeds. Existing user installations are not audited here.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote


NOTICE = re.compile(r'^(?:licen[cs]es?|copying|notices?|third[-_ ]party[-_ ](?:notices?|licenses?))(?:[._-].*)?$', re.I)
LICENSE = re.compile(r'^(?:licen[cs]e|copying)(?:[._-].*)?$', re.I)


def fetch(url, destination):
    subprocess.run(['curl', '-fLsS', '--connect-timeout', '15', '--max-time', '120',
                    url, '-o', str(destination)], check=True)
    data = destination.read_bytes()
    if not data or re.search(br'<!doctype html|<html', data[:200], re.I):
        raise ValueError('Upstream returned an empty file or HTML instead of a release file.')
    return data


def stage_release(repo, plugin, stage):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid upstream repository.')
    release = json.loads(fetch(f'https://api.github.com/repos/{repo}/releases/latest', stage/'release.json'))
    tag = release.get('tag_name')
    if not isinstance(tag, str) or not tag.strip() or release.get('draft') or release.get('prerelease'):
        raise ValueError('No ordinary upstream release tag is available.')
    ref = quote(tag, safe='')
    base = f'https://github.com/{repo}/releases/download/{ref}/'
    assets = {asset['name'] for asset in release['assets']}
    if not {'main.js', 'manifest.json'} <= assets:
        raise ValueError('Release is missing main.js or manifest.json.')

    tree = json.loads(fetch(f'https://api.github.com/repos/{repo}/git/trees/{ref}', stage/'tree.json'))
    if tree.get('truncated') or not isinstance(tree.get('tree'), list):
        raise ValueError('Upstream notice inventory is incomplete.')
    source_notices = []
    for entry in tree['tree']:
        name = entry.get('path', '')
        if NOTICE.fullmatch(name):
            if entry.get('type') != 'blob' or entry.get('mode') == '120000' or '/' in name or '\\' in name:
                raise ValueError('Upstream notice layout needs manual review before installation.')
            source_notices.append(name)
    if not any(LICENSE.fullmatch(name) for name in source_notices):
        raise ValueError('No root license file at the selected release tag; install manually after review.')

    notices = stage/'upstream-notices'
    notices.mkdir()
    records = []
    for origin, names, url_base in [
        ('source', sorted(source_notices), f'https://raw.githubusercontent.com/{repo}/{ref}/'),
        ('release', sorted(name for name in assets if NOTICE.fullmatch(name)), base),
    ]:
        for name in names:
            if '/' in name or '\\' in name:
                raise ValueError('Unsafe upstream notice filename.')
            destination = notices/origin/name
            destination.parent.mkdir(exist_ok=True)
            url = url_base + quote(name, safe='')
            data = fetch(url, destination)
            records.append({'path': str(destination.relative_to(notices)), 'url': url,
                            'sha256': hashlib.sha256(data).hexdigest()})

    files = {}
    for name in ['manifest.json', 'main.js'] + (['styles.css'] if 'styles.css' in assets else []):
        data = fetch(base + name, stage/name)
        files[name] = hashlib.sha256(data).hexdigest()
    manifest = json.loads((stage/'manifest.json').read_text())
    if manifest.get('id') != plugin or not manifest.get('version'):
        raise ValueError('Downloaded manifest does not identify the selected plugin and version.')
    receipt = {'repository': repo, 'release_tag': tag, 'plugin_version': manifest['version'],
               'source_url': f'https://github.com/{repo}/tree/{ref}',
               'source_archive_url': f'https://github.com/{repo}/archive/refs/tags/{ref}.zip',
               'root_tree_sha': tree.get('sha'), 'release_files_sha256': files,
               'notices': records}
    (notices/'provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    # This covers upstream root/release notices, not every bundled dependency.
    (notices/'README.txt').write_text(
        'These files retain the upstream license and notices for the selected release.\n'
        'The plugin and its dependencies keep their own terms, not the AI-OS Lite license.\n'
        'provenance.json records the exact tag, source location and downloaded hashes.\n'
        'Root and release notices are preserved; this is not a transitive dependency audit.\n')
    (stage/'release.json').unlink()
    (stage/'tree.json').unlink()


if __name__ == '__main__':
    try:
        stage_release(sys.argv[1], sys.argv[2], Path(sys.argv[3]))
    except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.CalledProcessError) as exc:
        print(f'Cannot stage plugin with matching upstream notices: {exc}', file=sys.stderr)
        sys.exit(1)
