#!/bin/bash
# Error hook - runs when agent fails

AGENT_NAME="$1"
TASK_DESC="$2"
EXIT_CODE="$3"

echo "[HOOK:on-error] $AGENT_NAME failed with code $EXIT_CODE"

# Log error
mkdir -p .claude/logs
echo "$(date -Iseconds) | ERROR | $AGENT_NAME | CODE=$EXIT_CODE" >> .claude/logs/hooks.log
echo "Task: $TASK_DESC" >> .claude/logs/hooks.log

# Store error in archival memory for learning
if [ -f ".claude/scripts/memory_manager.py" ]; then
    ERROR_DATA=$(cat <<EOF
{
  "agent": "$AGENT_NAME",
  "task": "$TASK_DESC",
  "error_code": $EXIT_CODE,
  "timestamp": $(date +%s)
}
EOF
)
    echo "$ERROR_DATA" | python3 .claude/scripts/memory_manager.py store-archival "error_${AGENT_NAME}_$(date +%s)" 2>/dev/null || true
fi

# Optional: Send notification
# (future implementation)

exit 0
