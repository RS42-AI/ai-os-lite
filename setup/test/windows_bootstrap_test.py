"""Exercise installer control flow with real PowerShell/Bash and fake WSL.

These checks never install software, authenticate a client or constitute
actual Windows/WSL acceptance.
"""
import base64
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'setup-windows.ps1').read_text()
PATH_FUNCTIONS = 'function ConvertTo-BashLiteral' + SOURCE.split('function ConvertTo-BashLiteral', 1)[1].split('function Test-Admin', 1)[0]

def ps_literal(value):
    return "'" + value.replace("'", "''") + "'"


def powershell(script):
    encoded = base64.b64encode(script.encode('utf-16-le')).decode()
    return subprocess.run(['pwsh', '-NoLogo', '-NoProfile', '-EncodedCommand', encoded], capture_output=True, text=True)


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell unavailable; run on a host with pwsh')
class WindowsBootstrapFlow(unittest.TestCase):
    def test_powershell_source_parses(self):
        # ParseFile has no execution side effects.
        path = str(ROOT / 'setup-windows.ps1').replace("'", "''")
        run = powershell("$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('" + path + "', [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { $_.Message }; exit 1 }")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_failed_wsl_install_stops_before_success_reboot_prompt(self):
        phase = SOURCE.split('# Phase 2 — WSL install (reboot-and-resume)\n')[1].split('# Phase 3 —')[0]
        for ready, code in [(False, 42), (False, 0), (True, 0)]:
            with self.subTest(ready=ready, code=code):
                script = "$Distro='Fixture'; $ErrorActionPreference='Stop'; function Test-WslReady { return $" + str(ready).lower() + " }; function wsl.exe { Write-Output 'MOCK_WSL_CALLED'; $global:LASTEXITCODE=" + str(code) + " }; " + phase + "; Write-Output 'CONTINUED_AFTER_PHASE'"
                run = powershell(script)
                if code:
                    self.assertNotEqual(run.returncode, 0)
                    self.assertNotIn('RESTART', run.stdout)
                    self.assertIn('installation failed', run.stderr)
                elif ready:
                    self.assertEqual(run.returncode, 0, run.stderr)
                    self.assertNotIn('MOCK_WSL_CALLED', run.stdout)
                    self.assertIn('CONTINUED_AFTER_PHASE', run.stdout)
                else:
                    self.assertEqual(run.returncode, 0, run.stderr)
                    self.assertIn('RESTART', run.stdout)

    def test_incompatible_mcp_selection_stops_before_any_install(self):
        phase = SOURCE.split('# Phase 1 — preflight\n')[1].split('# Phase 2 —')[0]
        run = powershell("$WithObsidianMcp=$true; $Agent='codex'; function Test-Admin { throw 'INSTALL_PREFLIGHT_CALLED' }; " + phase)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('requires -Agent claude or -Agent both', run.stderr)
        self.assertNotIn('INSTALL_PREFLIGHT_CALLED', run.stderr)

    def test_core_and_opt_in_flows_keep_failures_honest(self):
        phase = SOURCE.split('# 4.3 —')[1].split('\n', 1)[1].split('# Phase 5 —')[0]
        # agent, plugins opt-in, MCP opt-in, key, failed helper, calls, prompts, failure
        cases = [
            ('both', False, False, '', '', ['claude', 'codex'], 0, False),
            ('claude', False, False, '', '', ['claude'], 0, False),
            ('codex', False, False, '', '', ['codex'], 0, False),
            ('codex', True, False, '', '', ['codex', 'plugins'], 1, False),
            ('both', False, True, '', '', ['claude', 'codex'], 1, True),
            ('claude', False, True, 'fixture-key', '', ['claude', 'bun', 'mcp'], 1, False),
            ('both', True, True, 'fixture-key', 'mcp', ['claude', 'codex', 'plugins', 'bun', 'mcp'], 2, True),
            ('both', True, True, 'fixture-key', 'claude', ['claude', 'codex', 'plugins', 'bun', 'mcp'], 2, True),
            ('both', True, True, 'fixture-key', 'plugins', ['claude', 'codex', 'plugins', 'bun', 'mcp'], 2, True),
            ('both', False, True, 'fixture-key', 'bun', ['claude', 'codex', 'bun'], 1, True),
        ]
        for agent, plugins, mcp, key, fail, expected, prompts, failed in cases:
            with self.subTest(agent=agent, plugins=plugins, mcp=mcp, key=bool(key), fail=fail):
                prelude = PATH_FUNCTIONS + f"$ErrorActionPreference='Stop'; $Agent='{agent}'; $WithObsidianPlugins=${str(plugins).lower()}; $WithObsidianMcp=${str(mcp).lower()}; $Distro='Fixture'; $wslVaultPath='/tmp/test-vault'; $winVaultPath='C:\\Fixture'; $global:prompts=0; $wslVaultArg=ConvertTo-BashLiteral $wslVaultPath; "
                prelude += f'''function Read-Host {{
  $global:prompts += 1
  if (($args -join ' ') -match 'API key') {{ return '{key}' }}
  return ''
}}
function wsl.exe {{
  $request = $args -join ' '
  if ($request -match 'setup-mcp.sh') {{ $step='mcp' }}
  elseif ($request -match 'setup-claude-plugins.sh') {{ $step='claude' }}
  elseif ($request -match 'setup-codex-plugins.sh') {{ $step='codex' }}
  elseif ($request -match 'setup-plugins.sh') {{ $step='plugins' }}
  elseif ($request -match 'command -v bun') {{ $step='bun' }}
  else {{ throw 'Unexpected WSL command' }}
  Write-Output "CALLED:$step"
  $global:LASTEXITCODE=0
  if ($step -eq '{fail}') {{ $global:LASTEXITCODE=2 }}
}}
'''
                run = powershell(prelude + "try { " + phase + " } finally { Write-Output \"PROMPTS:$global:prompts\" }")
                self.assertEqual(re.findall(r'^CALLED:(.+)$', run.stdout, re.M), expected, run.stdout + run.stderr)
                self.assertEqual(re.findall(r'^PROMPTS:(.+)$', run.stdout, re.M), [str(prompts)], run.stdout + run.stderr)
                self.assertEqual(run.returncode != 0, failed, run.stdout + run.stderr)
                self.assertNotIn('fixture-key', run.stdout + run.stderr)

    def test_windows_default_uses_profile_and_custom_path_wins(self):
        cases = [
            ('', "D:\\Profiles\\O'Brien Example", "D:\\Profiles\\O'Brien Example\\AIOS"),
            ('E:\\My Notes\\Vault', 'C:\\Ignored', 'E:\\My Notes\\Vault'),
        ]
        for requested, profile, expected in cases:
            with self.subTest(requested=requested, profile=profile):
                run = powershell(PATH_FUNCTIONS + '\nResolve-WindowsVaultPath ' + ps_literal(requested) + ' ' + ps_literal(profile))
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertEqual(run.stdout.strip(), expected)

    def test_invalid_windows_paths_fail_before_provisioning(self):
        for path in ['relative', r'\\server\share\Vault', 'C:\\', 'C:\\Notes\\..\\Vault', 'C:\\Bad|Name', 'C:\\Bad"Name', 'C:\\Bad \\Vault', 'C:\\Bad\nName']:
            with self.subTest(path=path):
                run = powershell(PATH_FUNCTIONS + '\nResolve-WindowsVaultPath ' + ps_literal(path) + " 'C:\\Profile'")
                self.assertNotEqual(run.returncode, 0, run.stdout)
                self.assertIn('absolute local Windows folder', run.stderr)
        run = powershell(PATH_FUNCTIONS + "\nResolve-WindowsVaultPath '' ''")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('USERPROFILE is unavailable', run.stderr)

    def test_wsl_translation_and_shell_literals_preserve_space_apostrophe_and_dollar(self):
        windows_path = "D:\\Profiles\\O'Brien $(printf injected)\\AIOS"
        mapped_path = "/custom-mount/O'Brien $(printf injected)/AIOS"
        mock = "\nfunction wsl.exe { $global:request=$args[-1]; $global:LASTEXITCODE=0; return " + ps_literal(mapped_path) + " }\n"
        body = "$result=ConvertTo-WslVaultPath " + ps_literal(windows_path) + " 'Fixture'; [ordered]@{path=$result; command=$global:request; literal=(ConvertTo-BashLiteral $result)} | ConvertTo-Json -Compress"
        run = powershell(PATH_FUNCTIONS + mock + body)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        result = json.loads(run.stdout)
        self.assertEqual(result['path'], mapped_path)
        # Execute the actual generated Bash text with a harmless wslpath stub.
        parsed = subprocess.run(['bash', '-c', "wslpath() { printf '%s\\0' \"$@\"; }; " + result['command']], capture_output=True)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        self.assertEqual(parsed.stdout.split(b'\0'), [b'-a', b'-u', windows_path.encode(), b''])
        parsed = subprocess.run(['bash', '-c', "printf '%s\\0' " + result['literal']], capture_output=True)
        self.assertEqual(parsed.stdout, mapped_path.encode() + b'\0')

    def test_failed_or_ambiguous_wsl_translation_stops(self):
        for output, code in [("'/tmp/mapped'", 9), ("'/tmp/one', '/tmp/two'", 0), ("'relative'", 0)]:
            with self.subTest(output=output, code=code):
                mock = f"\nfunction wsl.exe {{ $global:LASTEXITCODE={code}; return {output} }}\n"
                run = powershell(PATH_FUNCTIONS + mock + "ConvertTo-WslVaultPath 'D:\\Notes\\Vault' 'Fixture'")
                self.assertNotEqual(run.returncode, 0)
                self.assertIn('no vault files changed', run.stderr)


class WindowsBootstrapPipelines(unittest.TestCase):
    def test_failed_prerequisite_downloads_propagate_and_do_not_install(self):
        commands = re.findall(r"-- bash (.*?) -lc '(.*)'", SOURCE)
        prelude = '''command() { if [ "$1" = '-v' ] && { [ "$2" = node ] || [ "$2" = bun ]; }; then return 1; fi; builtin command "$@"; }
curl() { return 22; }
sudo() { if [ "$1" = '-E' ]; then shift; "$@"; else printf 'DOWNSTREAM_INSTALL\n'; return 0; fi; }
'''
        for target in ['node', 'bun']:
            flags, body = next((flags, body) for flags, body in commands if f'command -v {target} ' in body)
            with self.subTest(target=target):
                run = subprocess.run(['bash', *shlex.split(flags), '-c', prelude + body], capture_output=True, text=True)
                self.assertEqual(run.returncode, 22, run.stdout + run.stderr)
                self.assertNotIn('DOWNSTREAM_INSTALL', run.stdout)


if __name__ == '__main__':
    unittest.main()
