#!/bin/bash
# ============================================
# Claude Orchestrator - Worktree Manager
# ============================================
# Manages git worktrees for parallel Claude Code agents
#
# Usage:
#   worktree.sh spawn <count>     - Create N worktrees with agents
#   worktree.sh list              - List active worktrees
#   worktree.sh attach <name>     - Attach to a worktree's Claude session
#   worktree.sh cleanup           - Remove all orchestrator worktrees
#   worktree.sh status            - Show status of all agents

set -e

# Configuration
WORKTREES_BASE="../.worktrees"
BRANCH_PREFIX="claude"
REPO_NAME=$(basename "$(pwd)")
POSTBOX=".claude/postbox"
TMUX_SESSION_PREFIX="claude-agent"

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

# ============================================
# spawn - Create worktrees and start agents
# ============================================
spawn_agents() {
    local COUNT=${1:-2}
    local AGENTS=("tester" "linter" "reviewer" "implementer")
    
    log_info "Spawning $COUNT parallel agents..."
    
    # Ensure we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warn "Not in a git repository!"
        exit 1
    fi
    
    # Create worktrees base directory
    mkdir -p "$WORKTREES_BASE"
    
    # Get pending tasks
    PENDING_TASKS=$(jq -r '.pending[].id' "$POSTBOX/tasks.json" 2>/dev/null | head -n "$COUNT")
    
    local i=0
    for AGENT in "${AGENTS[@]}"; do
        if [ $i -ge "$COUNT" ]; then
            break
        fi
        
        TIMESTAMP=$(date +%s)
        WORKTREE_NAME="${REPO_NAME}-${AGENT}-${TIMESTAMP}"
        WORKTREE_PATH="$WORKTREES_BASE/$WORKTREE_NAME"
        BRANCH_NAME="${BRANCH_PREFIX}/${AGENT}-${TIMESTAMP}"
        
        log_info "Creating worktree for $AGENT: $WORKTREE_NAME"
        
        # Create branch and worktree
        git branch "$BRANCH_NAME" HEAD 2>/dev/null || true
        git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
        
        # Copy necessary files to worktree
        cp -r .claude "$WORKTREE_PATH/" 2>/dev/null || true
        
        # Get task for this agent (if any)
        TASK_ID=$(echo "$PENDING_TASKS" | sed -n "$((i+1))p")
        TASK_DESC=""
        if [ -n "$TASK_ID" ]; then
            TASK_DESC=$(jq -r --arg id "$TASK_ID" '.pending[] | select(.id == $id) | .description' "$POSTBOX/tasks.json")
            
            # Move task to in_progress
            jq --arg id "$TASK_ID" --arg agent "$AGENT" \
                '(.pending[] | select(.id == $id)) as $task | 
                 .pending = [.pending[] | select(.id != $id)] |
                 .in_progress += [$task + {"agent": $agent, "started": now}]' \
                "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && \
                mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
        fi
        
        # Create agent-specific prompt
        AGENT_PROMPT="You are the $AGENT agent. "
        case "$AGENT" in
            tester)
                AGENT_PROMPT+="Focus on running tests, identifying failures, and ensuring test coverage."
                ;;
            linter)
                AGENT_PROMPT+="Focus on code quality, linting, formatting, and style consistency."
                ;;
            reviewer)
                AGENT_PROMPT+="Review recent changes, identify issues, suggest improvements."
                ;;
            implementer)
                AGENT_PROMPT+="Implement features and fix bugs based on task descriptions."
                ;;
        esac
        
        if [ -n "$TASK_DESC" ]; then
            AGENT_PROMPT+=" Your current task: $TASK_DESC"
        fi
        
        # Start Claude in tmux session
        TMUX_NAME="${TMUX_SESSION_PREFIX}-${AGENT}"
        
        log_info "Starting Claude in tmux session: $TMUX_NAME"
        
        tmux new-session -d -s "$TMUX_NAME" -c "$WORKTREE_PATH" \
            "claude --dangerously-skip-permissions -p '$AGENT_PROMPT Start by reading CLAUDE.md and understanding your role.'; exec bash" \
            2>/dev/null || log_warn "tmux session $TMUX_NAME may already exist"
        
        log_success "Agent $AGENT spawned in $WORKTREE_PATH"
        
        i=$((i + 1))
    done
    
    echo ""
    log_success "Spawned $i agents"
    echo ""
    echo "To attach to an agent:"
    echo "  tmux attach -t ${TMUX_SESSION_PREFIX}-<agent>"
    echo ""
    echo "To list all sessions:"
    echo "  tmux ls"
}

# ============================================
# list - Show active worktrees
# ============================================
list_worktrees() {
    log_info "Active worktrees:"
    echo ""
    
    git worktree list | while read -r line; do
        WORKTREE_PATH=$(echo "$line" | awk '{print $1}')
        BRANCH=$(echo "$line" | awk '{print $3}' | tr -d '[]')
        
        if [[ "$WORKTREE_PATH" == *"$WORKTREES_BASE"* ]]; then
            # Check if tmux session exists
            AGENT=$(basename "$WORKTREE_PATH" | sed 's/.*-\([^-]*\)-[0-9]*/\1/')
            TMUX_NAME="${TMUX_SESSION_PREFIX}-${AGENT}"
            
            if tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
                STATUS="${GREEN}[RUNNING]${NC}"
            else
                STATUS="${YELLOW}[STOPPED]${NC}"
            fi
            
            echo -e "  $STATUS $BRANCH"
            echo -e "         ${CYAN}$WORKTREE_PATH${NC}"
        fi
    done
}

# ============================================
# attach - Attach to agent's tmux session
# ============================================
attach_agent() {
    local AGENT=$1
    
    if [ -z "$AGENT" ]; then
        echo "Available agents:"
        tmux ls 2>/dev/null | grep "$TMUX_SESSION_PREFIX" | sed 's/:.*//' | sed "s/$TMUX_SESSION_PREFIX-/  /"
        echo ""
        echo "Usage: $0 attach <agent>"
        exit 1
    fi
    
    TMUX_NAME="${TMUX_SESSION_PREFIX}-${AGENT}"
    
    if tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
        tmux attach -t "$TMUX_NAME"
    else
        log_warn "Session $TMUX_NAME not found"
        exit 1
    fi
}

# ============================================
# cleanup - Remove all orchestrator worktrees
# ============================================
cleanup_worktrees() {
    log_info "Cleaning up worktrees..."
    
    # Kill tmux sessions
    tmux ls 2>/dev/null | grep "$TMUX_SESSION_PREFIX" | cut -d: -f1 | while read -r session; do
        log_info "Killing tmux session: $session"
        tmux kill-session -t "$session" 2>/dev/null || true
    done
    
    # Remove worktrees
    git worktree list | grep "$WORKTREES_BASE" | awk '{print $1}' | while read -r wt; do
        log_info "Removing worktree: $wt"
        git worktree remove --force "$wt" 2>/dev/null || true
    done
    
    # Clean up branches
    git branch | grep "$BRANCH_PREFIX/" | while read -r branch; do
        log_info "Deleting branch: $branch"
        git branch -D "$branch" 2>/dev/null || true
    done
    
    # Prune worktree references
    git worktree prune
    
    log_success "Cleanup completed"
}

# ============================================
# status - Show status of all agents
# ============================================
show_status() {
    echo ""
    echo "=== Agent Status ==="
    echo ""
    
    tmux ls 2>/dev/null | grep "$TMUX_SESSION_PREFIX" | while read -r session; do
        SESSION_NAME=$(echo "$session" | cut -d: -f1)
        AGENT=$(echo "$SESSION_NAME" | sed "s/$TMUX_SESSION_PREFIX-//")
        
        # Get worktree path
        WORKTREE=$(git worktree list | grep "$AGENT" | head -1 | awk '{print $1}')
        
        # Check for recent activity
        if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
            LAST_MODIFIED=$(find "$WORKTREE" -type f -name "*.py" -o -name "*.ts" -o -name "*.js" -mmin -5 2>/dev/null | wc -l)
            
            if [ "$LAST_MODIFIED" -gt 0 ]; then
                ACTIVITY="${GREEN}[ACTIVE]${NC}"
            else
                ACTIVITY="${YELLOW}[IDLE]${NC}"
            fi
        else
            ACTIVITY="${RED}[UNKNOWN]${NC}"
        fi
        
        echo -e "  ${CYAN}$AGENT${NC} $ACTIVITY"
        echo "    Session: $SESSION_NAME"
        [ -n "$WORKTREE" ] && echo "    Worktree: $WORKTREE"
        echo ""
    done
    
    echo "=== Postbox Status ==="
    if [ -f "$POSTBOX/tasks.json" ]; then
        PENDING=$(jq '.pending | length' "$POSTBOX/tasks.json")
        IN_PROGRESS=$(jq '.in_progress | length' "$POSTBOX/tasks.json")
        COMPLETED=$(jq '.completed | length' "$POSTBOX/tasks.json")
        
        echo "  Pending: $PENDING"
        echo "  In Progress: $IN_PROGRESS"
        echo "  Completed: $COMPLETED"
    fi
    echo ""
}

# ============================================
# merge - Merge agent's work back to main
# ============================================
merge_agent() {
    local AGENT=$1
    
    if [ -z "$AGENT" ]; then
        echo "Usage: $0 merge <agent>"
        exit 1
    fi
    
    # Find the worktree
    WORKTREE=$(git worktree list | grep "$AGENT" | head -1 | awk '{print $1}')
    BRANCH=$(git worktree list | grep "$AGENT" | head -1 | awk '{print $3}' | tr -d '[]')
    
    if [ -z "$WORKTREE" ]; then
        log_warn "No worktree found for agent: $AGENT"
        exit 1
    fi
    
    log_info "Merging $BRANCH..."
    
    # Check for uncommitted changes in worktree
    cd "$WORKTREE"
    if ! git diff --quiet; then
        log_info "Committing pending changes..."
        git add -A
        git commit -m "chore($AGENT): auto-commit pending changes"
    fi
    
    # Go back to main repo and merge
    cd - > /dev/null
    git merge "$BRANCH" --no-edit || {
        log_warn "Merge conflict! Resolve manually."
        exit 1
    }
    
    log_success "Merged $BRANCH successfully"
}

# ============================================
# Main
# ============================================
case "$1" in
    spawn)
        spawn_agents "$2"
        ;;
    list)
        list_worktrees
        ;;
    attach)
        attach_agent "$2"
        ;;
    cleanup)
        cleanup_worktrees
        ;;
    status)
        show_status
        ;;
    merge)
        merge_agent "$2"
        ;;
    *)
        echo "Claude Orchestrator - Worktree Manager"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  spawn <n>      Create N worktrees with agents (default: 2)"
        echo "  list           List active worktrees"
        echo "  attach <name>  Attach to agent's tmux session"
        echo "  status         Show status of all agents"
        echo "  merge <name>   Merge agent's work back to main"
        echo "  cleanup        Remove all orchestrator worktrees"
        exit 1
        ;;
esac
