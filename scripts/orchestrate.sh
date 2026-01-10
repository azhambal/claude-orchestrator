#!/bin/bash
# ============================================
# Claude Orchestrator - Main Autopilot Script
# ============================================
# 
# Full autopilot mode for Claude Code multi-agent system
#
# Usage:
#   ./orchestrate.sh run "task description"    # Run single task with agents
#   ./orchestrate.sh auto                      # Full autopilot mode
#   ./orchestrate.sh cycle                     # One improvement cycle
#   ./orchestrate.sh status                    # Show system status

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR=".claude"
POSTBOX="$CLAUDE_DIR/postbox"
MEMORY="$CLAUDE_DIR/memory"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ORCH]${NC} $1"; }
log_success() { echo -e "${GREEN}[ORCH]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ORCH]${NC} $1"; }
log_agent() { echo -e "${MAGENTA}[$1]${NC} $2"; }

# ============================================
# Helper: Run Claude with specific agent
# ============================================
run_agent() {
    local AGENT=$1
    local PROMPT=$2
    local MODEL=${3:-sonnet}
    local THINKING=${4:-think}
    
    log_agent "$AGENT" "Starting..."
    
    # Build the full prompt with agent context
    local AGENT_FILE="$CLAUDE_DIR/agents/${AGENT}.md"
    local FULL_PROMPT=""
    
    if [ -f "$AGENT_FILE" ]; then
        FULL_PROMPT="You are acting as the $AGENT agent. Read your instructions from @.claude/agents/${AGENT}.md first.

$THINKING about this task:

$PROMPT

After completing, write results to .claude/postbox/results.json"
    else
        FULL_PROMPT="$PROMPT"
    fi
    
    # Run Claude
    claude -p "$FULL_PROMPT" \
        --model "$MODEL" \
        --allowedTools "Read,Write,Edit,Bash,Grep,Glob" \
        --dangerously-skip-permissions \
        --output-format text 2>&1 | while read -r line; do
            echo -e "${CYAN}  │${NC} $line"
        done
    
    log_agent "$AGENT" "Completed"
}

# ============================================
# Helper: Add task to postbox
# ============================================
add_task() {
    local DESC=$1
    local AGENT=${2:-implementer}
    local PRIORITY=${3:-medium}
    local TASK_ID="task-$(date +%s)"
    
    # Ensure postbox exists
    mkdir -p "$POSTBOX"
    [ -f "$POSTBOX/tasks.json" ] || echo '{"pending":[],"in_progress":[],"completed":[]}' > "$POSTBOX/tasks.json"
    
    # Add task
    jq --arg id "$TASK_ID" \
       --arg desc "$DESC" \
       --arg agent "$AGENT" \
       --arg priority "$PRIORITY" \
       '.pending += [{
           "id": $id,
           "description": $desc,
           "agent": $agent,
           "priority": $priority,
           "created": now
       }]' "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && \
       mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
    
    echo "$TASK_ID"
}

# ============================================
# Helper: Get next pending task
# ============================================
get_next_task() {
    if [ -f "$POSTBOX/tasks.json" ]; then
        jq -r '.pending | sort_by(.priority) | .[0] // empty' "$POSTBOX/tasks.json"
    fi
}

# ============================================
# Helper: Move task to in_progress
# ============================================
start_task() {
    local TASK_ID=$1
    local AGENT=$2
    
    jq --arg id "$TASK_ID" --arg agent "$AGENT" \
       '(.pending[] | select(.id == $id)) as $task |
        .pending = [.pending[] | select(.id != $id)] |
        .in_progress += [$task + {"agent": $agent, "started": now}]' \
       "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && \
       mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
}

# ============================================
# Helper: Complete task
# ============================================
complete_task() {
    local TASK_ID=$1
    
    jq --arg id "$TASK_ID" \
       '(.in_progress[] | select(.id == $id)) as $task |
        .in_progress = [.in_progress[] | select(.id != $id)] |
        .completed += [$task + {"completed": now}]' \
       "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && \
       mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
}

# ============================================
# Command: run - Execute single task
# ============================================
cmd_run() {
    local TASK_DESC="$1"
    
    if [ -z "$TASK_DESC" ]; then
        echo "Usage: $0 run 'task description'"
        exit 1
    fi
    
    log_info "Starting task: $TASK_DESC"
    echo ""
    
    # Step 1: Architect plans the task
    log_info "Step 1/4: Architect planning..."
    run_agent "architect" "
Plan this task and break it into steps if needed:

$TASK_DESC

If this is a simple task, just proceed. If complex, create subtasks in the postbox.
Determine which agent(s) should handle this.
" "opus" "think hard"
    
    echo ""
    
    # Step 2: Implementer executes
    log_info "Step 2/4: Implementer executing..."
    run_agent "implementer" "
Execute this task:

$TASK_DESC

Follow the architect's plan if one was created.
Write clean code following project patterns.
" "sonnet" "think"
    
    echo ""
    
    # Step 3: Tester verifies
    log_info "Step 3/4: Tester verifying..."
    run_agent "tester" "
Verify the implementation for:

$TASK_DESC

Run relevant tests. Report any failures.
" "sonnet" "think"
    
    echo ""
    
    # Step 4: Critic reviews
    log_info "Step 4/4: Critic reviewing..."
    run_agent "critic" "
Review the completed work for:

$TASK_DESC

Evaluate quality. Note any improvements for future tasks.
" "sonnet" "think hard"
    
    echo ""
    log_success "Task completed!"
}

# ============================================
# Command: cycle - One improvement cycle
# ============================================
cmd_cycle() {
    log_info "Starting improvement cycle..."
    echo ""
    
    # Step 1: Linter fixes style
    log_info "Cycle 1/3: Linter checking code style..."
    run_agent "linter" "
Run linting and auto-fix what you can.
Report any issues that need manual attention.
"
    
    echo ""
    
    # Step 2: Tester checks health
    log_info "Cycle 2/3: Tester checking test health..."
    run_agent "tester" "
Run all tests. Report on:
- Overall pass rate
- Any flaky tests
- Coverage gaps
"
    
    echo ""
    
    # Step 3: Critic evaluates
    log_info "Cycle 3/3: Critic evaluating project health..."
    run_agent "critic" "
Review recent changes and project state.
- What's working well?
- What needs attention?
- Any patterns to improve?

Update learnings in .claude/memory/learnings.md
" "sonnet" "think hard"
    
    echo ""
    log_success "Improvement cycle completed!"
}

# ============================================
# Command: auto - Full autopilot
# ============================================
cmd_auto() {
    log_info "🤖 AUTOPILOT MODE ACTIVATED"
    log_warn "Running until all tasks complete or Ctrl+C"
    echo ""
    
    local CYCLES=0
    local MAX_CYCLES=10  # Safety limit
    
    while [ $CYCLES -lt $MAX_CYCLES ]; do
        CYCLES=$((CYCLES + 1))
        log_info "=== Autopilot Cycle $CYCLES ==="
        
        # Check for pending tasks
        NEXT_TASK=$(get_next_task)
        
        if [ -n "$NEXT_TASK" ] && [ "$NEXT_TASK" != "null" ]; then
            TASK_ID=$(echo "$NEXT_TASK" | jq -r '.id')
            TASK_DESC=$(echo "$NEXT_TASK" | jq -r '.description')
            TASK_AGENT=$(echo "$NEXT_TASK" | jq -r '.agent // "implementer"')
            
            log_info "Processing: $TASK_DESC"
            start_task "$TASK_ID" "$TASK_AGENT"
            
            # Run appropriate agent
            run_agent "$TASK_AGENT" "$TASK_DESC"
            
            complete_task "$TASK_ID"
            log_success "Task $TASK_ID completed"
        else
            log_info "No pending tasks. Running improvement cycle..."
            cmd_cycle
            
            # Check if cycle found new tasks
            NEXT_TASK=$(get_next_task)
            if [ -z "$NEXT_TASK" ] || [ "$NEXT_TASK" == "null" ]; then
                log_success "All tasks completed. Autopilot stopping."
                break
            fi
        fi
        
        echo ""
        sleep 2  # Brief pause between cycles
    done
    
    if [ $CYCLES -ge $MAX_CYCLES ]; then
        log_warn "Reached max cycles ($MAX_CYCLES). Stopping autopilot."
    fi
}

# ============================================
# Command: status - Show system status
# ============================================
cmd_status() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Claude Orchestrator Status         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Postbox status
    if [ -f "$POSTBOX/tasks.json" ]; then
        PENDING=$(jq '.pending | length' "$POSTBOX/tasks.json")
        IN_PROGRESS=$(jq '.in_progress | length' "$POSTBOX/tasks.json")
        COMPLETED=$(jq '.completed | length' "$POSTBOX/tasks.json")
        
        echo -e "${BLUE}Tasks:${NC}"
        echo "  Pending:     $PENDING"
        echo "  In Progress: $IN_PROGRESS"
        echo "  Completed:   $COMPLETED"
    else
        echo -e "${YELLOW}Postbox not initialized${NC}"
    fi
    
    echo ""
    
    # Agents available
    echo -e "${BLUE}Agents:${NC}"
    for agent in "$CLAUDE_DIR/agents/"*.md; do
        if [ -f "$agent" ]; then
            name=$(basename "$agent" .md)
            echo "  ✓ $name"
        fi
    done
    
    echo ""
    
    # Recent activity
    if [ -f "$POSTBOX/results.json" ]; then
        echo -e "${BLUE}Recent Results:${NC}"
        jq -r '.results[-3:] | .[] | "  [\(.agent)] \(.status): \(.summary)"' "$POSTBOX/results.json" 2>/dev/null || echo "  No results yet"
    fi
    
    echo ""
    
    # Worktrees
    echo -e "${BLUE}Worktrees:${NC}"
    git worktree list 2>/dev/null | grep -v "$(pwd)" | while read -r line; do
        echo "  $line"
    done || echo "  None active"
    
    echo ""
}

# ============================================
# Command: parallel - Run agents in parallel
# ============================================
cmd_parallel() {
    local COUNT=${1:-2}
    
    log_info "Starting $COUNT parallel agents..."
    
    # Use worktree script
    if [ -f "$CLAUDE_DIR/scripts/worktree.sh" ]; then
        bash "$CLAUDE_DIR/scripts/worktree.sh" spawn "$COUNT"
    else
        log_warn "Worktree script not found. Run init.sh first."
        exit 1
    fi
}

# ============================================
# Main
# ============================================
case "$1" in
    run)
        shift
        cmd_run "$*"
        ;;
    cycle)
        cmd_cycle
        ;;
    auto)
        cmd_auto
        ;;
    status)
        cmd_status
        ;;
    parallel)
        cmd_parallel "$2"
        ;;
    task)
        shift
        TASK_ID=$(add_task "$*")
        echo "Created task: $TASK_ID"
        ;;
    *)
        echo "Claude Orchestrator - Autopilot System"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  run 'desc'    Execute a task with all agents"
        echo "  task 'desc'   Add task to queue"
        echo "  cycle         Run one improvement cycle"
        echo "  auto          Full autopilot mode"
        echo "  parallel <n>  Run N agents in parallel worktrees"
        echo "  status        Show system status"
        echo ""
        echo "Examples:"
        echo "  $0 run 'Add user authentication'"
        echo "  $0 task 'Fix login bug'"
        echo "  $0 auto"
        exit 1
        ;;
esac
