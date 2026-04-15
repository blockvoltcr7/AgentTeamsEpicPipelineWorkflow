# Claude Code Hooks for OS AI Alpha Agents

This directory contains custom hooks that automate and enhance your Claude Code workflow.

## Installed Hooks

### 1. SessionStart Hook
**When it runs:** Every time you start a Claude Code session

**What it does:**
- Displays current git branch
- Shows count of uncommitted changes
- Lists recent commits
- Shows project type (monorepo structure)
- Provides quick command reminders

**Implementation:** Command hook (`session-start.sh`)

### 2. PreToolUse Hook (File Safety Validator)
**When it runs:** Before any Write or Edit operation

**What it does:**
- Uses AI to validate file operations
- Checks for sensitive files (.env, credentials)
- Blocks system file modifications
- Detects path traversal attempts
- Scans for secrets in file content

**Decisions:**
- `allow` - Safe operation, proceed
- `deny` - Unsafe operation, blocked
- `ask` - Uncertain, request user confirmation

**Implementation:** Prompt-based hook (AI-powered)

## How Hooks Work

### Hook Lifecycle

1. **Event occurs** (e.g., session starts, file write attempted)
2. **Matcher checks** if hook applies (e.g., "Write|Edit" matches Write and Edit tools)
3. **Hook executes** (command script or AI prompt)
4. **Output processed** (JSON with decision and message)
5. **Action taken** (allow/deny/ask)

### Hook Types

**Command Hooks:**
- Fast, deterministic checks
- Bash scripts with JSON output
- Access to environment variables
- Example: session-start.sh

**Prompt-Based Hooks:**
- AI-powered reasoning
- Context-aware decisions
- Natural language logic
- Example: File safety validator

## Testing Your Hooks

### Test Session Start Hook
```bash
# Manually run the script
bash .claude/hooks/session-start.sh

# Should output JSON with systemMessage containing project info
```

### Test in Debug Mode
```bash
# Start Claude Code with debug logging
claude --debug

# Watch for hook execution in logs
```

### Validate Hook Configuration
```bash
# Check JSON syntax
cat .claude/hooks/hooks.json | jq .

# Expected: Valid JSON output, no errors
```

## Customizing Hooks

### Add More Session Context

Edit `session-start.sh` to add:
- Environment detection (dev/staging/prod)
- Database migration status
- Running service checks
- Custom project reminders

### Add More Safety Checks

Modify the PreToolUse prompt to:
- Check for hardcoded API keys
- Validate file naming conventions
- Enforce code organization rules
- Check for TODO comments before commits

### Add New Hook Events

Common additions:
```json
{
  "Stop": [{
    "matcher": "*",
    "hooks": [{
      "type": "prompt",
      "prompt": "Before stopping, verify: tests run, build succeeded, documentation updated. Approve to stop or block with reason."
    }]
  }],
  "PostToolUse": [{
    "matcher": "Bash",
    "hooks": [{
      "type": "command",
      "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/log-command.sh"
    }]
  }]
}
```

## Important Notes

### Hooks Load at Session Start
**You must restart Claude Code to see hook changes:**
1. Edit hook configuration or scripts
2. Exit Claude Code
3. Restart: `claude` or `cc`
4. New configuration loads

### Environment Variables Available

- `$CLAUDE_PROJECT_DIR` - Project root path
- `$CLAUDE_PLUGIN_ROOT` - Plugin directory (for portable paths)
- `$CLAUDE_ENV_FILE` - SessionStart only: persist env vars
- `$CLAUDE_CODE_REMOTE` - Set if running remotely

### Hook Output Format

All hooks must output valid JSON:
```json
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "Message shown to Claude"
}
```

For PreToolUse hooks, add:
```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask"
  },
  "systemMessage": "Explanation"
}
```

## Troubleshooting

### Hook Not Running
- Check hook is in `hooks.json`
- Verify matcher pattern matches tool name
- Ensure script is executable (`chmod +x`)
- Restart Claude Code session

### Script Errors
- Test script manually: `bash .claude/hooks/your-script.sh`
- Check JSON output is valid: `output | jq .`
- Review debug logs: `claude --debug`

### Permission Issues
- Ensure scripts have execute permission
- Check file paths are absolute or use `$CLAUDE_PROJECT_DIR`
- Verify user has access to referenced files

## Resources

- **Official Docs:** https://docs.claude.com/en/docs/claude-code/hooks
- **Hook Skill:** Use `/skill plugin-dev:hook-development` for examples
- **Debug Mode:** `claude --debug` for detailed logs

## Next Steps

Want to add more hooks? Try:

1. **Stop Hook** - Verify task completion before stopping
2. **PostToolUse for Bash** - Log all commands executed
3. **UserPromptSubmit** - Add project context to every request
4. **PreCompact** - Preserve important info before context compression

Edit `hooks.json` and add your custom hooks!
