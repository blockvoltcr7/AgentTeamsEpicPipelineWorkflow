#!/bin/bash
# Pre-push quality hook for Claude Code
# Runs a full build before allowing git push

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

# If not a git push command, allow passthrough
if ! echo "$COMMAND" | grep -qE '^\s*git\s+push\b'; then
  exit 0
fi

echo "--- Pre-push build check ---"
echo ""
echo "Running full build..."

if (cd "$WEB_DIR" && pnpm run build 2>&1); then
  echo ""
  echo "  Build: PASSED"
  echo ""
  echo "--- End pre-push check ---"
  exit 0
else
  echo ""
  echo "  Build: FAILED"
  echo ""
  echo "--- End pre-push check ---"
  echo "BLOCKED: Build failed. Fix build errors before pushing."
  exit 1
fi
