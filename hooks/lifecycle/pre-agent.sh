#!/bin/bash
# Pre-agent hook - runs before each agent starts

AGENT_NAME="$1"
TASK_DESC="$2"

echo "[HOOK:pre-agent] Starting $AGENT_NAME"

# Log to hooks.log
mkdir -p .claude/logs
echo "$(date -Iseconds) | PRE_AGENT | $AGENT_NAME" >> .claude/logs/hooks.log

# Optional: Preload cache for this agent
# (implemented in orchestrate.sh)

# Optional: Check context size and warn if large
# (future implementation)

exit 0
