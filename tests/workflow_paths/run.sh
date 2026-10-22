#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
python3 "$(dirname "$0")/test_vault_paths.py"
