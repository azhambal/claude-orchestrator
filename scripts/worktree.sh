#!/bin/bash
# ============================================
# Claude Orchestrator - Worktree Manager
# ============================================
# Manages git worktrees for parallel Claude Code agents.
#
# Usage:
#   worktree.sh spawn <n> [task_id]            Create N worktrees (optional: N agents for one task)
#   worktree.sh list                          List active worktrees + tmux sessions
#   worktree.sh status                        Show detailed status
#   worktree.sh attach <agent|session>        Attach to tmux session (agent attaches latest)
#   worktree.sh logs <agent|session> [n]      Show last N log lines (default 50)
#   worktree.sh watch [sec]                   Live monitor (default 2s)
#   worktree.sh merge <agent|session>         Merge agent's work into main (excludes .claude/)
#   worktree.sh cleanup [--all]               Remove orchestrator worktrees (--all includes tournament)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../.." && pwd)"

WORKTREES_BASE="${WORKTREES_BASE:-$REPO_ROOT/../.worktrees}"
BRANCH_PREFIX="${BRANCH_PREFIX:-claude}"
REPO_NAME="$(basename "$REPO_ROOT")"
POSTBOX="$REPO_ROOT/.claude/postbox"
TMUX_SESSION_PREFIX="${TMUX_SESSION_PREFIX:-claude-agent}"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-Read,Write,Edit,Bash,Grep,Glob}"
CLAUDE_MODEL_DEFAULT="${CLAUDE_MODEL_DEFAULT:-sonnet}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_warn "Missing required command: $cmd"
    return 1
  fi
}

ensure_postbox() {
  mkdir -p "$POSTBOX"
  if [ ! -f "$POSTBOX/tasks.json" ]; then
    cat > "$POSTBOX/tasks.json" <<'EOF'
{
  "pending": [],
  "in_progress": [],
  "completed": []
}
EOF
  fi
}

copy_claude_skeleton_to_worktree() {
  local worktree_path="$1"
  mkdir -p "$worktree_path/.claude"

  # Copy stable config, not runtime artifacts
  [ -d "$REPO_ROOT/.claude/agents" ] && cp -r "$REPO_ROOT/.claude/agents" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$REPO_ROOT/.claude/scripts" ] && cp -r "$REPO_ROOT/.claude/scripts" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$REPO_ROOT/.claude/hooks" ] && cp -r "$REPO_ROOT/.claude/hooks" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$REPO_ROOT/.claude/.claude-plugin" ] && cp -r "$REPO_ROOT/.claude/.claude-plugin" "$worktree_path/.claude/" 2>/dev/null || true
  [ -f "$REPO_ROOT/.claude/settings.local.json" ] && cp "$REPO_ROOT/.claude/settings.local.json" "$worktree_path/.claude/" 2>/dev/null || true

  mkdir -p "$worktree_path/.claude/pipeline"/{current,history}
  mkdir -p "$worktree_path/.claude/tournament"/{current,history}
  mkdir -p "$worktree_path/.claude/logs"
}

determine_agent_type() {
  local task_desc="$1"
  if echo "$task_desc" | grep -qiE "(реализовать|implement|создать|create|добавить|add|build|develop|write|code|feature|сделать|исправить|fix)"; then
    echo "implementer"
  elif echo "$task_desc" | grep -qiE "(тест|test|spec|coverage|unit|integration|pytest|jest|vitest)"; then
    echo "tester"
  elif echo "$task_desc" | grep -qiE "(lint|format|style|quality|eslint|prettier|ruff|black)"; then
    echo "linter"
  elif echo "$task_desc" | grep -qiE "(review|audit|inspect|проверить|ревью)"; then
    echo "reviewer"
  else
    echo "implementer"
  fi
}

latest_session_for_agent() {
  local agent="$1"
  tmux ls 2>/dev/null | cut -d: -f1 | grep "^${TMUX_SESSION_PREFIX}-${agent}-" | sort | tail -1 || true
}

worktree_for_session() {
  local session="$1"
  local session_part agent_instance timestamp
  session_part="${session#${TMUX_SESSION_PREFIX}-}"
  agent_instance="$(echo "$session_part" | rev | cut -d- -f2- | rev)"
  timestamp="$(echo "$session_part" | rev | cut -d- -f1 | rev)"
  git worktree list 2>/dev/null | grep "${agent_instance}-${timestamp}" | head -1 | awk '{print $1}' || true
}

spawn_agents() {
  local count="${1:-4}"
  local single_task_id="${2:-}"

  require_cmd git || exit 1
  require_cmd jq || exit 1
  require_cmd tmux || exit 1
  require_cmd "$CLAUDE_BIN" || exit 1

  cd "$REPO_ROOT"
  ensure_postbox
  mkdir -p "$WORKTREES_BASE"

  local pending_tasks=""
  if [ -n "$single_task_id" ]; then
    log_info "Creating $count parallel agents for task: $single_task_id"

    local task_desc
    task_desc="$(jq -r --arg id "$single_task_id" '.pending[] | select(.id == $id) | .description' "$POSTBOX/tasks.json" 2>/dev/null)"

    if [ -z "$task_desc" ] || [ "$task_desc" = "null" ]; then
      log_warn "Task $single_task_id not found in pending queue!"
      exit 1
    fi

    jq --arg id "$single_task_id" '.pending = [.pending[] | select(.id != $id)]' \
      "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"

    local i=1
    while [ $i -le "$count" ]; do
      local agent_task_id="${single_task_id}-agent-${i}"
      jq --arg id "$agent_task_id" \
         --arg desc "$task_desc" \
         --arg parent "$single_task_id" \
         --argjson agent_num "$i" \
         --argjson total "$count" \
         '.pending += [{"id": $id, "description": $desc, "parent_task": $parent, "agent_num": $agent_num, "total_agents": $total, "created": now}]' \
         "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
      i=$((i + 1))
    done

    pending_tasks="$(jq -r --arg parent "$single_task_id" '.pending[] | select(.parent_task == $parent) | .id' "$POSTBOX/tasks.json" 2>/dev/null)"
  else
    pending_tasks="$(jq -r '.pending[].id' "$POSTBOX/tasks.json" 2>/dev/null | head -n "$count")"
  fi

  local spawned=0
  for task_id in $pending_tasks; do
    [ "$spawned" -lt "$count" ] || break

    local task_desc agent_num agent_type agent_instance
    task_desc="$(jq -r --arg id "$task_id" '.pending[] | select(.id == $id) | .description' "$POSTBOX/tasks.json" 2>/dev/null)"
    agent_num="$(jq -r --arg id "$task_id" '.pending[] | select(.id == $id) | .agent_num // empty' "$POSTBOX/tasks.json" 2>/dev/null || true)"

    if [ -z "$task_desc" ] || [ "$task_desc" = "null" ]; then
      log_warn "Task $task_id not found, skipping..."
      continue
    fi

    agent_type="$(determine_agent_type "$task_desc")"
    if [ -n "$agent_num" ]; then
      agent_instance="${agent_type}-${agent_num}"
    else
      agent_instance="${agent_type}"
    fi

    local timestamp worktree_name worktree_path branch_name
    timestamp=$(date +%s)
    sleep 0.1
    worktree_name="${REPO_NAME}-${agent_instance}-${timestamp}"
    worktree_path="$WORKTREES_BASE/$worktree_name"
    branch_name="${BRANCH_PREFIX}/${agent_instance}-${timestamp}"

    log_info "Creating worktree for $agent_instance (task: $task_id): $worktree_name"

    git branch "$branch_name" HEAD 2>/dev/null || true
    git worktree add "$worktree_path" "$branch_name"

    copy_claude_skeleton_to_worktree "$worktree_path"

    jq --arg id "$task_id" --arg agent "$agent_instance" \
      '(.pending[] | select(.id == $id)) as $task |
       .pending = [.pending[] | select(.id != $id)] |
       .in_progress += [$task + {"agent": $agent, "started": now}]' \
      "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"

    local abs_worktree_path task_script tmux_name
    abs_worktree_path="$(cd "$worktree_path" && pwd)"

    task_script="$worktree_path/.claude/execute_task.sh"
    cat > "$task_script" <<SCRIPT_EOF
#!/bin/bash
set -euo pipefail

cd "$abs_worktree_path"

TASK_ID="$task_id"
POSTBOX_PATH="$POSTBOX"
AGENT_TYPE="$agent_type"
AGENT_INSTANCE="$agent_instance"
MODEL="$CLAUDE_MODEL_DEFAULT"
ALLOWED_TOOLS="$CLAUDE_ALLOWED_TOOLS"

TASK_DESC=\$(jq -r --arg id "\$TASK_ID" '.in_progress[] | select(.id == \$id) | .description' "\$POSTBOX_PATH/tasks.json" 2>/dev/null || true)
if [ -z "\$TASK_DESC" ] || [ "\$TASK_DESC" = "null" ]; then
  echo "Task \$TASK_ID not found in in_progress"
  exit 1
fi

echo "Executing task: \$TASK_ID"
echo "Agent: \$AGENT_INSTANCE"
echo "Description: \$TASK_DESC"
echo ""

PROMPT=\$(cat <<'PROMPT_EOF'
You are acting as the AGENT_TYPE agent.
Read your instructions first from: @.claude/agents/AGENT_TYPE.md

Task to execute:
TASK_DESC_PLACEHOLDER

Work in THIS git worktree. Implement the task completely.
Prefer following repo conventions and commands from @.claude/CLAUDE.md when available.

After finishing:
- Ensure changes are consistent and correct.
- Summarize what you did.
PROMPT_EOF
)

PROMPT="\${PROMPT//AGENT_TYPE/\$AGENT_TYPE}"
PROMPT="\${PROMPT//TASK_DESC_PLACEHOLDER/\$TASK_DESC}"

set +e
$CLAUDE_BIN -p "\$PROMPT" \\
  --model "\$MODEL" \\
  --allowedTools "\$ALLOWED_TOOLS" \\
  --dangerously-skip-permissions \\
  --output-format text
EXIT_CODE=\$?
set -e

if [ \$EXIT_CODE -eq 0 ]; then
  echo "Task execution completed successfully"
  jq --arg id "\$TASK_ID" \\
    '(.in_progress[] | select(.id == \$id)) as \$task |
     .in_progress = [.in_progress[] | select(.id != \$id)] |
     .completed += [\$task + {"completed": now, "status": "success"}]' \\
    "\$POSTBOX_PATH/tasks.json" > "\$POSTBOX_PATH/tasks.json.tmp" && mv "\$POSTBOX_PATH/tasks.json.tmp" "\$POSTBOX_PATH/tasks.json"
else
  echo "Task execution failed with exit code \$EXIT_CODE"
  jq --arg id "\$TASK_ID" --argjson code "\$EXIT_CODE" \\
    '(.in_progress[] | select(.id == \$id)) as \$task |
     .in_progress = [.in_progress[] | select(.id != \$id), (\$task + {"failed": true, "error_code": \$code})]' \\
    "\$POSTBOX_PATH/tasks.json" > "\$POSTBOX_PATH/tasks.json.tmp" && mv "\$POSTBOX_PATH/tasks.json.tmp" "\$POSTBOX_PATH/tasks.json"
fi

exit \$EXIT_CODE
SCRIPT_EOF
    chmod +x "$task_script"

    tmux_name="${TMUX_SESSION_PREFIX}-${agent_instance}-${timestamp}"
    log_info "Starting agent in tmux session: $tmux_name"
    tmux new-session -d -s "$tmux_name" -c "$abs_worktree_path" \
      "$abs_worktree_path/.claude/execute_task.sh 2>&1 | tee .claude/task_output.log; exec bash" \
      2>/dev/null || log_warn "tmux session $tmux_name may already exist"

    log_success "Spawned $agent_instance in $worktree_path (task: $task_id)"
    spawned=$((spawned + 1))
  done

  echo ""
  if [ "$spawned" -eq 0 ]; then
    log_warn "No tasks spawned"
  else
    log_success "Spawned $spawned agent(s)"
    echo "Attach: tmux attach -t ${TMUX_SESSION_PREFIX}-<agent-instance>-<timestamp>"
    echo "List:   tmux ls"
  fi
}

list_worktrees() {
  log_info "Active worktrees under: $WORKTREES_BASE"
  echo ""
  git worktree list 2>/dev/null | grep "$WORKTREES_BASE" || echo "  None"
  echo ""
  echo "Active tmux sessions:"
  tmux ls 2>/dev/null | grep "$TMUX_SESSION_PREFIX" || echo "  None"
}

show_status() {
  echo ""
  echo -e "${CYAN}=== Agent Status ===${NC}"
  echo ""

  local sessions
  sessions="$(tmux ls 2>/dev/null | cut -d: -f1 | grep "^${TMUX_SESSION_PREFIX}-" || true)"
  if [ -z "$sessions" ]; then
    echo "  No active agent sessions"
  else
    echo "$sessions" | while read -r session; do
      [ -n "$session" ] || continue
      local worktree
      worktree="$(worktree_for_session "$session")"
      echo -e "  ${CYAN}${session}${NC} ${GREEN}[RUNNING]${NC}"
      [ -n "$worktree" ] && echo "    Worktree: $worktree"
      [ -n "$worktree" ] && [ -f "$worktree/.claude/task_output.log" ] && echo "    Log: $worktree/.claude/task_output.log"
      echo ""
    done
  fi

  echo -e "${CYAN}=== Tournament Sessions ===${NC}"
  tmux ls 2>/dev/null | cut -d: -f1 | grep "^tournament-" || echo "  None"
  echo ""

  echo -e "${CYAN}=== Postbox ===${NC}"
  if [ -f "$POSTBOX/tasks.json" ]; then
    echo "  Pending:     $(jq '.pending | length' "$POSTBOX/tasks.json" 2>/dev/null || echo 0)"
    echo "  In Progress: $(jq '.in_progress | length' "$POSTBOX/tasks.json" 2>/dev/null || echo 0)"
    echo "  Completed:   $(jq '.completed | length' "$POSTBOX/tasks.json" 2>/dev/null || echo 0)"
  else
    echo "  Postbox not initialized"
  fi
  echo ""
}

attach_agent() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo "Available sessions:"
    tmux ls 2>/dev/null | cut -d: -f1 | grep "$TMUX_SESSION_PREFIX" || true
    echo ""
    echo "Usage: $0 attach <agent-instance|full-session-name>"
    exit 1
  fi

  if tmux has-session -t "$target" 2>/dev/null; then
    tmux attach -t "$target"
    return 0
  fi

  local session
  session="$(latest_session_for_agent "$target")"
  if [ -z "$session" ]; then
    log_warn "No tmux session found for: $target"
    exit 1
  fi
  tmux attach -t "$session"
}

show_logs() {
  local target="${1:-}"
  local lines="${2:-50}"
  if [ -z "$target" ]; then
    echo "Usage: $0 logs <agent-instance|full-session-name> [lines]"
    exit 1
  fi

  local session="$target"
  if ! tmux has-session -t "$session" 2>/dev/null; then
    session="$(latest_session_for_agent "$target")"
  fi
  if [ -z "$session" ]; then
    log_warn "No session found for: $target"
    exit 1
  fi

  local worktree
  worktree="$(worktree_for_session "$session")"
  if [ -z "$worktree" ]; then
    log_warn "Could not find worktree for session: $session"
    exit 1
  fi

  local log_file="$worktree/.claude/task_output.log"
  if [ ! -f "$log_file" ]; then
    log_warn "No log file found: $log_file"
    exit 1
  fi

  echo "=== Logs for $session (last $lines lines) ==="
  tail -n "$lines" "$log_file"
}

watch_agents() {
  local interval="${1:-2}"
  echo "Monitoring agent activity (refresh every ${interval}s, Ctrl+C to stop)..."
  while true; do
    clear
    show_status
    sleep "$interval"
  done
}

cleanup_worktrees() {
  local include_tournament="${1:-false}"
  log_info "Cleaning up worktrees..."

  tmux ls 2>/dev/null | cut -d: -f1 | grep "^${TMUX_SESSION_PREFIX}-" | while read -r session; do
    [ -n "$session" ] || continue
    tmux kill-session -t "$session" 2>/dev/null || true
  done || true

  if [ "$include_tournament" = "true" ] || [ "$include_tournament" = "--all" ]; then
    tmux ls 2>/dev/null | cut -d: -f1 | grep "^tournament-" | while read -r session; do
      [ -n "$session" ] || continue
      tmux kill-session -t "$session" 2>/dev/null || true
    done || true
  fi

  git worktree list 2>/dev/null | grep "$WORKTREES_BASE" | awk '{print $1}' | while read -r wt; do
    [ -n "$wt" ] || continue
    git worktree remove --force "$wt" 2>/dev/null || true
  done || true

  git branch 2>/dev/null | grep "${BRANCH_PREFIX}/" | while read -r br; do
    br="$(echo "$br" | tr -d ' *')"
    [ -n "$br" ] || continue
    git branch -D "$br" 2>/dev/null || true
  done || true

  git worktree prune 2>/dev/null || true

  if [ -f "$POSTBOX/tasks.json" ]; then
    jq '.cancelled = (.cancelled // []) + (.in_progress | map(. + {"cancelled": now, "reason": "worktree cleanup"})) |
        .in_progress = [] |
        .pending = []' \
      "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
  fi

  log_success "Cleanup completed"
}

merge_agent() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo "Usage: $0 merge <agent-instance|full-session-name>"
    exit 1
  fi

  require_cmd git || exit 1
  require_cmd jq || exit 1

  local session="$target"
  if ! tmux has-session -t "$session" 2>/dev/null; then
    session="$(latest_session_for_agent "$target")"
  fi
  if [ -z "$session" ]; then
    log_warn "No session found for: $target"
    exit 1
  fi

  local worktree
  worktree="$(worktree_for_session "$session")"
  if [ -z "$worktree" ]; then
    log_warn "Could not find worktree for session: $session"
    exit 1
  fi

  cd "$worktree"

  local changed filtered
  changed="$(git diff --name-only 2>/dev/null || true)"
  filtered="$(echo "$changed" | grep -vE '^\.claude/' | grep -vE '^(dist|build|coverage|node_modules)/' || true)"

  if [ -z "$filtered" ]; then
    log_warn "No mergeable changes found (excluding .claude/ and build artifacts)."
    cd "$REPO_ROOT"
    exit 0
  fi

  echo "$filtered" | xargs git add 2>/dev/null || true
  git commit -m "feat(worktree): merge from $target" 2>/dev/null || true

  local commit_hash
  commit_hash="$(git rev-parse HEAD)"

  cd "$REPO_ROOT"
  log_info "Cherry-picking $commit_hash into main repo..."
  git cherry-pick "$commit_hash" 2>/dev/null || {
    log_warn "Cherry-pick failed. Resolve conflicts manually."
    exit 1
  }
  log_success "Merged changes successfully"
}

case "${1:-}" in
  spawn)
    spawn_agents "${2:-4}" "${3:-}"
    ;;
  list)
    list_worktrees
    ;;
  status)
    show_status
    ;;
  attach)
    attach_agent "${2:-}"
    ;;
  logs)
    show_logs "${2:-}" "${3:-50}"
    ;;
  watch)
    watch_agents "${2:-2}"
    ;;
  merge)
    merge_agent "${2:-}"
    ;;
  cleanup)
    cleanup_worktrees "${2:-false}"
    ;;
  *)
    echo "Claude Orchestrator - Worktree Manager"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  spawn <n> [task_id]            Create N worktrees (optional: N agents for one task)"
    echo "  list                          List active worktrees + tmux sessions"
    echo "  status                        Show detailed status"
    echo "  attach <agent|session>        Attach to tmux session (agent attaches latest)"
    echo "  logs <agent|session> [n]      Show last N log lines"
    echo "  watch [sec]                   Live monitor"
    echo "  merge <agent|session>         Merge agent's work into main (excludes .claude/)"
    echo "  cleanup [--all]               Remove orchestrator worktrees (--all includes tournament)"
    exit 1
    ;;
esac

