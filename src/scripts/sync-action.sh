#!/usr/bin/env bash
#* Sync the canonical CI script into the GitHub Action dir.
# Source of truth: src/scripts/everything.sh
# Vendored copy: .github/actions/run_task/everything.sh (runs via $ACTION_PATH, so it works without actions/checkout — see action.yml).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_root/src/scripts/everything.sh"
dest="$repo_root/.github/actions/run_task/everything.sh"

cp "$src" "$dest"
chmod +x "$dest" "$src"
