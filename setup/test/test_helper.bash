#!/usr/bin/env bash

# Project root used by all tests
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KIT_ROOT

# Throwaway test vault — recreated per test
setup_test_vault() {
  export TEST_VAULT="${BATS_TEST_TMPDIR}/vault"
  mkdir -p "$TEST_VAULT"
  # Deterministic test fixture only: no production noninteractive acceptance mode.
  # These disposable records are not evidence of a real person's agreement.
  python3 - "$KIT_ROOT" "$TEST_VAULT" <<'PYFIXTURE'
import importlib.util, pathlib, sys
kit, workspace = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("license_consent", kit / "tools/license_consent.py")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
policy = module.load_policy(kit.parent)
receipt = module.make_receipt(policy, name="Synthetic Test User", capacity="personal", organization="", authority=False, source="human-terminal")
module.save_receipt(workspace, policy, receipt)
PYFIXTURE
}

# Throwaway test workspace
setup_test_workspace() {
  export TEST_WORKSPACE="${BATS_TEST_TMPDIR}/workspace"
  mkdir -p "$TEST_WORKSPACE"
}
