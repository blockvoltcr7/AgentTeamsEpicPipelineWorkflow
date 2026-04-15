#!/bin/bash
# Pre-commit quality hook for Claude Code
# Runs lint, type-check, and lockfile sync before allowing git commit

set -euo pipefail

# Resolve repo root relative to this script's location
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WEB_DIR="$REPO_ROOT/apps/web"

# Project-aware no-op: skip if apps/web doesn't exist in this repo
[ ! -d "$WEB_DIR" ] && exit 0

# Read tool input from stdin
INPUT=$(cat)

# Extract the command from the JSON payload
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If not a git commit command, allow passthrough
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
  exit 0
fi

echo "--- Pre-commit quality checks ---"

FAILED=0

# 1. Run ESLint
echo ""
echo "[1/3] Running lint..."
if (cd "$WEB_DIR" && pnpm run lint 2>&1); then
  echo "  Lint: PASSED"
else
  echo "  Lint: FAILED"
  FAILED=1
fi

# 2. Run TypeScript type checking
echo ""
echo "[2/3] Running type-check..."
if (cd "$WEB_DIR" && pnpm run type-check 2>&1); then
  echo "  Type-check: PASSED"
else
  echo "  Type-check: FAILED"
  FAILED=1
fi

# 3. Check lockfile sync
echo ""
echo "[3/3] Checking pnpm lockfile sync..."
if (cd "$REPO_ROOT" && pnpm install --frozen-lockfile 2>&1); then
  echo "  Lockfile sync: PASSED"
else
  echo "  Lockfile sync: FAILED — run 'pnpm install' to update pnpm-lock.yaml"
  FAILED=1
fi

echo ""
echo "--- End pre-commit checks ---"

if [ "$FAILED" -ne 0 ]; then
  echo "BLOCKED: Pre-commit checks failed. Fix the issues above before committing."
  exit 1
fi

exit 0
