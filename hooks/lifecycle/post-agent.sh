#!/bin/bash
# Post-agent hook - runs after agent completes

AGENT_NAME="$1"
TASK_DESC="$2"
EXIT_CODE="${3:-0}"

echo "[HOOK:post-agent] $AGENT_NAME completed with code $EXIT_CODE"

# Log
mkdir -p .claude/logs
echo "$(date -Iseconds) | POST_AGENT | $AGENT_NAME | EXIT=$EXIT_CODE" >> .claude/logs/hooks.log

# Store session summary in core memory
if [ -f ".claude/scripts/memory_manager.py" ]; then
    SESSION_DATA=$(cat <<EOF
{
  "agent": "$AGENT_NAME",
  "task": "$TASK_DESC",
  "completed_at": $(date +%s),
  "exit_code": $EXIT_CODE
}
EOF
)
    echo "$SESSION_DATA" | python3 .claude/scripts/memory_manager.py store-core "session_${AGENT_NAME}_$(date +%s)" 2>/dev/null || true
fi

# Evict old core memory (older than 1 hour)
if [ -f ".claude/scripts/memory_manager.py" ]; then
    python3 .claude/scripts/memory_manager.py evict 3600 2>/dev/null || true
fi

exit 0
