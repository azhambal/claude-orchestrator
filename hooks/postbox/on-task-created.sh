#!/bin/bash
# Task created hook - runs when new task is added to postbox

TASK_ID="$1"
TASK_DESC="$2"

echo "[HOOK:on-task-created] Task created: $TASK_ID"

# Log
mkdir -p .claude/logs
echo "$(date -Iseconds) | TASK_CREATED | $TASK_ID" >> .claude/logs/hooks.log

# Optional: Notify about new task
# (future implementation)

exit 0
