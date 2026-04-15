#!/bin/bash
# SessionStart hook - Displays project context when Claude Code starts

set -euo pipefail

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Count uncommitted changes
MODIFIED_FILES=$(git status --short 2>/dev/null | wc -l | xargs)

# Get recent commits
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "No commits")

# Check if in monorepo
if [ -d "apps/web" ] && [ -d "apps/os_ai_agno_agents" ]; then
  PROJECT_TYPE="Monorepo (Next.js + Agno + RAG)"
else
  PROJECT_TYPE="Standard project"
fi

# Build context message
CONTEXT_MESSAGE="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 OS AI Alpha Agents - Session Started
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 Project Type: $PROJECT_TYPE
🌿 Current Branch: $CURRENT_BRANCH
📝 Uncommitted Changes: $MODIFIED_FILES files

📜 Recent Commits:
$RECENT_COMMITS

💡 Quick Commands:
  /git_workflow_commit - Auto-commit and push changes
  /deploy:agno:dev     - Deploy Agno agents to dev
  /deploy:agno:prod    - Deploy Agno agents to production

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"

# Output as system message (appears in Claude's context)
cat <<EOF
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "$CONTEXT_MESSAGE"
}
EOF

exit 0
