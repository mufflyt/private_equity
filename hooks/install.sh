#!/usr/bin/env bash
# Installs the blocking pre-commit hook into .git/hooks.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
install -m 0755 "$ROOT/hooks/pre-commit" "$ROOT/.git/hooks/pre-commit"
echo "Installed .git/hooks/pre-commit -> runs tests/run_blocking.R"
