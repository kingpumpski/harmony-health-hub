#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "Git is not available or this folder is not a Git working tree." >&2
  exit 1
}

[ -f package.json ] || { echo "package.json is missing; open the cloned repository root." >&2; exit 1; }

echo "Git repository verified: $REPO_ROOT"
npm ci
npm run verify:local
echo "Local environment is ready. Start development with: npm run dev"
