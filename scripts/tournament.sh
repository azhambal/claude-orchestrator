#!/bin/bash
# ============================================
# Tournament (Deprecated Wrapper)
# ============================================
# Tournament mode is now implemented inside: .claude/scripts/pipeline.sh
#
# This script is kept for backward compatibility.
#
# Usage:
#   tournament.sh run [n] "Task description"   # default n=4
#   tournament.sh status
#   tournament.sh select <pipeline-name>       # e.g. pipeline-1
#   tournament.sh reject
#   tournament.sh cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_SH="$SCRIPT_DIR/pipeline.sh"

case "${1:-}" in
  run)
    shift
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
      n="$1"
      shift
    else
      n=4
    fi
    bash "$PIPELINE_SH" run "$n" "$*"
    ;;
  status)
    bash "$PIPELINE_SH" tournament-status
    ;;
  select)
    bash "$PIPELINE_SH" tournament-select "${2:-}"
    ;;
  reject)
    bash "$PIPELINE_SH" tournament-reject
    ;;
  cleanup)
    bash "$PIPELINE_SH" tournament-cleanup
    ;;
  *)
    echo "Tournament (Deprecated Wrapper)"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  run [n] \"description\"   Run tournament with N pipelines (default: 4)"
    echo "  status                   Show current tournament status"
    echo "  select <pipeline>        Select and merge a passing pipeline (e.g. pipeline-1)"
    echo "  reject                   Reject all pipelines and cleanup"
    echo "  cleanup                  Clean up tournament worktrees"
    exit 1
    ;;
esac

