#!/bin/bash
# ============================================
# Pipeline Monitor - Real-time status checker
# ============================================
# Usage: pipeline-monitor.sh [interval|once]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CURRENT_DIR="$REPO_ROOT/.claude/pipeline/current"
INTERVAL=${1:-2}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

check_pipeline_status() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Pipeline Monitor - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ! -f "$CURRENT_DIR/task.json" ]; then
        echo -e "${YELLOW}No active pipeline${NC}"
        return
    fi

    TASK_ID=$(jq -r '.id // "unknown"' "$CURRENT_DIR/task.json" 2>/dev/null || echo "unknown")
    TASK_DESC=$(jq -r '.description // "unknown"' "$CURRENT_DIR/task.json" 2>/dev/null || echo "unknown")
    STATUS=$(jq -r '.status // "unknown"' "$CURRENT_DIR/task.json" 2>/dev/null || echo "unknown")
    PHASE=$(jq -r '.phase // 0' "$CURRENT_DIR/task.json" 2>/dev/null || echo "0")
    ARCH_ITER=$(jq -r '.architect_iteration // 0' "$CURRENT_DIR/task.json" 2>/dev/null || echo "0")
    IMPL_ITER=$(jq -r '.implement_iteration // 0' "$CURRENT_DIR/task.json" 2>/dev/null || echo "0")

    echo -e "${BLUE}Task:${NC} $TASK_ID"
    echo -e "${BLUE}Description:${NC} ${TASK_DESC:0:80}"
    echo -e "${BLUE}Status:${NC} $STATUS"
    echo -e "${BLUE}Phase:${NC} $PHASE"
    echo -e "${BLUE}Architect Iter:${NC} $ARCH_ITER"
    echo -e "${BLUE}Implement Iter:${NC} $IMPL_ITER"
    echo ""

    echo -e "${CYAN}Artifacts:${NC}"
    [ -d "$CURRENT_DIR/architecture" ] && echo "  Architecture: $(ls -1 "$CURRENT_DIR/architecture"/*.md 2>/dev/null | wc -l)"
    [ -d "$CURRENT_DIR/reviews" ] && echo "  Reviews:       $(ls -1 "$CURRENT_DIR/reviews"/*.md 2>/dev/null | wc -l)"
    [ -d "$CURRENT_DIR/tests" ] && echo "  Test reports:  $(ls -1 "$CURRENT_DIR/tests"/*.md 2>/dev/null | wc -l)"
    echo ""

    # Show latest test output if present
    if [ -f "$CURRENT_DIR/tests/last_test_output.log" ]; then
        echo -e "${CYAN}Last test output (tail):${NC}"
        tail -10 "$CURRENT_DIR/tests/last_test_output.log" 2>/dev/null | sed 's/^/  /' || true
        echo ""
    fi

    echo -e "${CYAN}Commands:${NC}"
    echo "  ./claude-orchestrate.sh pipeline-status"
    echo "  tail -f .claude/pipeline/current/tests/last_test_output.log"
    echo ""
}

if [ "$INTERVAL" = "0" ] || [ "$INTERVAL" = "once" ]; then
    check_pipeline_status
else
    while true; do
        check_pipeline_status
        sleep "$INTERVAL"
    done
fi

