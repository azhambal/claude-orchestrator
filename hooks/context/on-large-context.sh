#!/bin/bash
# Context overflow hook - runs when context is large

AGENT_NAME="$1"
CONTEXT_SIZE="${2:-0}"

echo "[HOOK:on-large-context] $AGENT_NAME has large context: $CONTEXT_SIZE tokens"

# Log warning
mkdir -p .claude/logs
echo "$(date -Iseconds) | LARGE_CONTEXT | $AGENT_NAME | SIZE=$CONTEXT_SIZE" >> .claude/logs/hooks.log

# Suggest cleanup actions
echo "  Suggestion: Clear old data or use /compact"

# Optional: Auto-compact if enabled in config
# (future implementation)

exit 0
