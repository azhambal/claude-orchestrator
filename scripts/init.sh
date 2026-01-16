#!/bin/bash
# ============================================
# Claude Orchestrator - Initialize Repository
# ============================================
# Usage: ./init.sh /path/to/your/repo
# 
# This script:
# 1. Creates .claude directory structure
# 2. Copies agent templates
# 3. Runs deep analysis with Opus + ultrathink
# 4. Generates customized CLAUDE.md and agents

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/repository"
    exit 1
fi

TARGET_REPO="$(cd "$1" && pwd)"
CLAUDE_DIR="$TARGET_REPO/.claude"

log_info "Initializing Claude Orchestrator in: $TARGET_REPO"

# ============================================
# Step 1: Create directory structure
# ============================================
log_info "Creating directory structure..."

# Create directories explicitly to ensure brace expansion works correctly
mkdir -p "$CLAUDE_DIR/agents" \
         "$CLAUDE_DIR/memory" \
         "$CLAUDE_DIR/postbox" \
         "$CLAUDE_DIR/docs" \
         "$CLAUDE_DIR/skills"
mkdir -p "$TARGET_REPO/../.worktrees"

# Initialize postbox
cat > "$CLAUDE_DIR/postbox/tasks.json" << 'EOF'
{
  "pending": [],
  "in_progress": [],
  "completed": []
}
EOF

cat > "$CLAUDE_DIR/postbox/results.json" << 'EOF'
{
  "results": []
}
EOF

log_success "Directory structure created"

# ============================================
# Step 1.5: Create Context Engineering structure
# ============================================
log_info "Setting up Context Engineering infrastructure..."

# Memory hierarchy
mkdir -p "$CLAUDE_DIR/memory/core" \
         "$CLAUDE_DIR/memory/working" \
         "$CLAUDE_DIR/memory/archival"

# Cache directory
mkdir -p "$CLAUDE_DIR/cache/hot" \
         "$CLAUDE_DIR/cache/warm" \
         "$CLAUDE_DIR/cache/metadata"

# Hooks structure
mkdir -p "$CLAUDE_DIR/hooks"

# Logs
mkdir -p "$CLAUDE_DIR/logs"

# Scripts for utilities
mkdir -p "$CLAUDE_DIR/scripts"

# Pipeline & tournament state dirs (runtime)
mkdir -p "$CLAUDE_DIR/pipeline/current" \
         "$CLAUDE_DIR/pipeline/history" \
         "$CLAUDE_DIR/tournament/current" \
         "$CLAUDE_DIR/tournament/history"

# Ignore runtime artifacts by default (safe even if repo doesn't commit .claude/)
if [ ! -f "$CLAUDE_DIR/.gitignore" ]; then
cat > "$CLAUDE_DIR/.gitignore" << 'GITIGNORE_EOF'
# Claude Orchestrator runtime artifacts
cache/
logs/
pipeline/current/
pipeline/history/
tournament/current/
tournament/history/
postbox/*.tmp
GITIGNORE_EOF
fi

# Initialize cache config
cat > "$CLAUDE_DIR/cache/config.json" << 'CACHE_EOF'
{
  "version": "1.0",
  "enabled": true,
  "max_hot_entries": 50,
  "hot_threshold": 3,
  "default_ttl": 3600,
  "auto_invalidate_on_file_change": true,
  "preload_on_agent_start": true
}
CACHE_EOF

log_success "Context Engineering structure created"

# ============================================
# Step 2: Copy base agent templates and utilities
# ============================================
log_info "Copying agent templates and utilities..."

# Copy agents
cp "$ORCHESTRATOR_DIR/agents/"*.md "$CLAUDE_DIR/agents/" 2>/dev/null || true

# Copy skills (best practices guides)
if [ -d "$ORCHESTRATOR_DIR/skills" ]; then
    mkdir -p "$CLAUDE_DIR/skills"
    cp "$ORCHESTRATOR_DIR/skills/"*.md "$CLAUDE_DIR/skills/" 2>/dev/null || true
fi

# Copy utility scripts
mkdir -p "$CLAUDE_DIR/scripts/utils"
cp "$ORCHESTRATOR_DIR/scripts/utils/"*.py "$CLAUDE_DIR/scripts/utils/" 2>/dev/null || true

# Copy plugin metadata and hooks configuration
mkdir -p "$CLAUDE_DIR/.claude-plugin"
cp "$ORCHESTRATOR_DIR/.claude-plugin/plugin.json" "$CLAUDE_DIR/.claude-plugin/" 2>/dev/null || true
cp "$ORCHESTRATOR_DIR/hooks/hooks.json" "$CLAUDE_DIR/hooks/" 2>/dev/null || true
cp "$ORCHESTRATOR_DIR/hooks/README.md" "$CLAUDE_DIR/hooks/" 2>/dev/null || true

# Copy default local settings (do not overwrite if project already has one)
if [ ! -f "$CLAUDE_DIR/settings.local.json" ] && [ -f "$ORCHESTRATOR_DIR/.claude/settings.local.json" ]; then
    cp "$ORCHESTRATOR_DIR/.claude/settings.local.json" "$CLAUDE_DIR/settings.local.json" 2>/dev/null || true
fi

# Copy orchestrator scripts into target repo (.claude/scripts/)
mkdir -p "$CLAUDE_DIR/scripts"
for f in worktree.sh pipeline.sh tournament.sh pipeline-monitor.sh orchestrate.sh; do
    if [ -f "$ORCHESTRATOR_DIR/scripts/$f" ]; then
        cp "$ORCHESTRATOR_DIR/scripts/$f" "$CLAUDE_DIR/scripts/" 2>/dev/null || true
    fi
done
chmod +x "$CLAUDE_DIR/scripts/"*.sh 2>/dev/null || true

log_success "Templates and utilities copied"

# ============================================
# Step 3: Run deep analysis with Opus
# ============================================
log_info "Running deep analysis with Opus + ultrathink..."
log_warn "This may take 2-5 minutes and consume significant tokens"

cd "$TARGET_REPO"

ANALYSIS_RAN=0

if ! command -v claude >/dev/null 2>&1; then
    log_warn "'claude' CLI not found. Skipping deep analysis (you can run it later)."
else

# Create analysis prompt
ANALYSIS_PROMPT=$(cat << 'PROMPT_EOF'
Ultrathink: Perform a comprehensive analysis of this repository.

## Your Task
Analyze this codebase and create optimized configuration files for Claude Code automation.

## Analysis Steps

1. **Identify Tech Stack**
   - Programming languages used
   - Frameworks and libraries
   - Build tools and package managers
   - Test frameworks
   - Linting/formatting tools

2. **Understand Project Structure**
   - Key directories and their purposes
   - Entry points
   - Configuration files
   - How modules are organized

3. **Detect Existing Patterns**
   - Coding conventions
   - Testing patterns
   - Git workflow (branches, commits)
   - CI/CD if present

4. **Identify Agent Needs**
   - Which specialized agents would help?
   - What tasks are repetitive?
   - What could be parallelized?

## Output Requirements

Create the following files by using the Write tool:

### 1. `.claude/CLAUDE.md` (max 100 lines)
Keep it LEAN. Include only:
- Project summary (2-3 sentences)
- Key commands (build, test, lint)
- Critical rules (max 5)
- Links to docs/ for details

### 2. `.claude/docs/ARCHITECTURE.md`
- Tech stack details
- Module breakdown
- Key dependencies
- Important patterns

### 3. `.claude/docs/WORKFLOWS.md`
- Common development tasks
- Testing procedures
- Deployment process (if detectable)

### 4. `.claude/agents/` - Update agent configs
For each agent file, add project-specific instructions in a "## Project-Specific" section.

### 5. `.claude/memory/analysis.json`
```json
{
  "analyzed_at": "<timestamp>",
  "tech_stack": {...},
  "structure": {...},
  "detected_patterns": {...},
  "recommended_agents": [...]
}
```

## Important Rules
- Be concise - every token counts
- Use bullet points, not prose
- Include actual file paths from this repo
- If unsure, note it rather than guess

Start by exploring the repository structure, then create the files.
PROMPT_EOF
)

# Run analysis with Opus
claude -p "$ANALYSIS_PROMPT" \
    --model opus \
    --allowedTools "Read,Write,Edit,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(head:*),Bash(grep:*),Glob,Grep" \
    --dangerously-skip-permissions \
    --output-format stream-json 2>&1 | while read -r line; do
        # Extract and display progress
        if echo "$line" | grep -q '"type":"assistant"'; then
            echo -n "."
        fi
    done

echo ""
log_success "Deep analysis completed"
ANALYSIS_RAN=1
fi

# ============================================
# Step 4: Validate generated files
# ============================================
log_info "Validating generated files..."

REQUIRED_FILES=(
    ".claude/CLAUDE.md"
    ".claude/docs/ARCHITECTURE.md"
    ".claude/memory/analysis.json"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$TARGET_REPO/$file" ]; then
        log_success "✓ $file"
    else
        log_warn "✗ $file (missing)"
        MISSING=$((MISSING + 1))
    fi
done

# Fallback: create minimal .claude/CLAUDE.md if analysis was skipped or failed
if [ ! -f "$TARGET_REPO/.claude/CLAUDE.md" ]; then
cat > "$TARGET_REPO/.claude/CLAUDE.md" <<EOF
# $(basename "$TARGET_REPO")

Auto-generated fallback by Claude Orchestrator (analysis step skipped or failed).

## Quick start

\`\`\`bash
./claude-orchestrate.sh status
./claude-orchestrate.sh pipeline "Describe your task"       # n=1 (default)
./claude-orchestrate.sh pipeline 4 "Describe your task"     # tournament mode (n=2..4)
\`\`\`

## Notes

- Edit this file after running analysis (requires \`claude\` CLI).
- Document project-specific build/test/lint commands here.
EOF
fi

# Optional: create root CLAUDE.md pointer (only if missing)
if [ ! -f "$TARGET_REPO/CLAUDE.md" ]; then
cat > "$TARGET_REPO/CLAUDE.md" <<'EOF'
# CLAUDE.md

This project is initialized with Claude Orchestrator.

- Project-specific rules and commands: `.claude/CLAUDE.md`
- Orchestrator entrypoint: `./claude-orchestrate.sh`
EOF
fi

# ============================================
# Step 5: Create orchestrator entry point
# ============================================
log_info "Creating orchestrator entry point..."

cat > "$TARGET_REPO/claude-orchestrate.sh" << 'ENTRY_EOF'
#!/bin/bash
# Claude Orchestrator Entry Point
# Usage: ./claude-orchestrate.sh <command> [args]
#
# Commands:
#
#  PIPELINE (single + tournament)
#   pipeline [n] "<desc>"         Run single pipeline (n=1) or tournament (n=2..4)
#   pipeline-status               Show single pipeline status
#   pipeline-resume               Resume interrupted single pipeline
#   pipeline-monitor [sec]        Monitor single pipeline artifacts
#
#  TOURNAMENT UTILITIES (after pipeline n>=2)
#   pipeline-tournament-status    Show current tournament status
#   pipeline-select <pipeline>    Select winner (e.g. pipeline-1)
#   pipeline-reject               Reject and cleanup tournament
#   pipeline-cleanup              Cleanup tournament worktrees/sessions
#
#  LEGACY ALIASES
#   tournament [n] "<desc>"       Deprecated alias for: pipeline [n]
#   tournament-status             Alias for: pipeline-tournament-status
#   tournament-select <pipeline>  Alias for: pipeline-select
#   tournament-reject             Alias for: pipeline-reject
#   tournament-cleanup            Alias for: pipeline-cleanup
#   pipeline-single "<desc>"      Deprecated alias for: pipeline 1
#
#  TASK WORKTREES (Legacy)
#   task [n_agents] "<desc>"      Create a task and spawn N parallel agents (default: 4)
#
#  UTILITIES
#   status                        Show overall status
#   watch [sec]                   Live monitor (worktrees)
#   logs <agent|session> [n]      Show agent logs
#   merge <agent|session>         Merge agent changes back to main
#   clean                         Cleanup worktrees (includes tournament)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR=".claude"
POSTBOX="$CLAUDE_DIR/postbox"

case "$1" in
    # ═══════════════════════════════════════════════════════════════
    # LEGACY ALIASES
    # ═══════════════════════════════════════════════════════════════
    tournament)
        # Deprecated alias for tournament run.
        # Use: ./claude-orchestrate.sh pipeline [n] "desc"
        shift
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            N_PIPELINES="$1"
            shift
        else
            N_PIPELINES=4
        fi
        TASK_DESC="$*"
        if [ -z "$TASK_DESC" ]; then
            echo "Error: Task description is required"
            echo "Usage: $0 pipeline [n] \"description\""
            exit 1
        fi
        if [ "$N_PIPELINES" -lt 2 ] || [ "$N_PIPELINES" -gt 4 ]; then
            echo "Error: n must be between 2 and 4 for tournament mode"
            exit 1
        fi
        echo "Deprecated: use '$0 pipeline $N_PIPELINES \"...\"'"
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" run "$N_PIPELINES" "$TASK_DESC"
        ;;

    tournament-status)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-status
        ;;

    tournament-select)
        if [ -z "$2" ]; then
            echo "Error: Pipeline name is required"
            echo "Usage: $0 tournament-select <pipeline>"
            exit 1
        fi
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-select "$2"
        ;;

    tournament-reject)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-reject
        ;;

    tournament-cleanup)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-cleanup
        ;;

    # ═══════════════════════════════════════════════════════════════
    # PIPELINE (single + tournament)
    # ═══════════════════════════════════════════════════════════════
    pipeline)
        shift
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            N_PIPELINES="$1"
            shift
        else
            N_PIPELINES=1
        fi
        TASK_DESC="$*"
        if [ -z "$TASK_DESC" ]; then
            echo "Error: Task description is required"
            echo "Usage: $0 pipeline [n] \"description\""
            echo "Constraints: n must be 1..4 (default: 1)"
            exit 1
        fi
        if [ "$N_PIPELINES" -lt 1 ] || [ "$N_PIPELINES" -gt 4 ]; then
            echo "Error: n must be between 1 and 4"
            exit 1
        fi
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" run "$N_PIPELINES" "$TASK_DESC"
        ;;

    pipeline-single)
        echo "Deprecated: use '$0 pipeline 1 \"...\"' (or omit n to default to 1)"
        shift
        TASK_DESC="$*"
        if [ -z "$TASK_DESC" ]; then
            echo "Error: Task description is required"
            echo "Usage: $0 pipeline-single \"description\""
            exit 1
        fi
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" run "1" "$TASK_DESC"
        ;;

    pipeline-status)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" status
        ;;

    pipeline-resume)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" resume
        ;;

    pipeline-monitor)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline-monitor.sh" "${2:-2}"
        ;;

    # ═══════════════════════════════════════════════════════════════
    # TOURNAMENT UTILITIES (aliases under "pipeline-*")
    # ═══════════════════════════════════════════════════════════════
    pipeline-tournament-status)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-status
        ;;

    pipeline-select)
        if [ -z "$2" ]; then
            echo "Error: Pipeline name is required"
            echo "Usage: $0 pipeline-select <pipeline>"
            exit 1
        fi
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-select "$2"
        ;;

    pipeline-reject)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-reject
        ;;

    pipeline-cleanup)
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-cleanup
        ;;

    # ═══════════════════════════════════════════════════════════════
    # TASKS → PARALLEL AGENTS (Legacy)
    # ═══════════════════════════════════════════════════════════════
    task)
        shift
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            N_AGENTS="$1"
            shift
        else
            N_AGENTS=4
        fi
        TASK_DESC="$*"
        if [ -z "$TASK_DESC" ]; then
            echo "Error: Task description is required"
            echo "Usage: $0 task [n_agents] \"description\""
            exit 1
        fi
        TASK_ID="task-$(date +%s)"
        echo "Creating task: $TASK_ID"
        echo "Description: $TASK_DESC"
        echo "Parallel agents: $N_AGENTS"
        echo ""
        jq --arg id "$TASK_ID" --arg desc "$TASK_DESC" \
            '.pending += [{"id": $id, "description": $desc, "created": now}]' \
            "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && \
            mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
        bash "$SCRIPT_DIR/.claude/scripts/worktree.sh" spawn "$N_AGENTS" "$TASK_ID"
        ;;

    # ═══════════════════════════════════════════════════════════════
    # STATUS & UTILITIES
    # ═══════════════════════════════════════════════════════════════
    status)
        echo "═══════════════════════════════════════════════════════════════"
        echo "  TOURNAMENT STATUS"
        echo "═══════════════════════════════════════════════════════════════"
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-status 2>/dev/null || echo "  No active tournament"
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  PIPELINE STATUS"
        echo "═══════════════════════════════════════════════════════════════"
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" status 2>/dev/null || echo "  No active pipeline"
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  TASK POSTBOX"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Pending:"
        jq -r '.pending[] | "  [\(.id)] \(.description)"' "$POSTBOX/tasks.json" 2>/dev/null || echo "  None"
        echo ""
        echo "In Progress:"
        jq -r '.in_progress[] | "  [\(.id)] \(.description) (agent: \(.agent))"' "$POSTBOX/tasks.json" 2>/dev/null || echo "  None"
        echo ""
        echo "Completed Today:"
        jq -r '.completed[] | select(.completed > (now - 86400)) | "  [\(.id)] \(.description)"' "$POSTBOX/tasks.json" 2>/dev/null || echo "  None"
        ;;

    watch)
        bash "$SCRIPT_DIR/.claude/scripts/worktree.sh" watch "$2"
        ;;

    logs)
        bash "$SCRIPT_DIR/.claude/scripts/worktree.sh" logs "$2" "$3"
        ;;

    merge)
        if [ -z "$2" ]; then
            echo "Error: Agent/session is required"
            echo "Usage: $0 merge <agent|session>"
            exit 1
        fi
        bash "$SCRIPT_DIR/.claude/scripts/worktree.sh" merge "$2"
        ;;

    clean)
        echo "Cleaning up all worktrees (including tournament)..."
        bash "$SCRIPT_DIR/.claude/scripts/worktree.sh" cleanup --all
        bash "$SCRIPT_DIR/.claude/scripts/pipeline.sh" tournament-cleanup 2>/dev/null || true
        ;;

    *)
        echo "Claude Orchestrator - Multi-Agent Development System"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  pipeline [n] \"desc\"              Run pipeline (n=1) or tournament (n=2..4)"
        echo "  pipeline-status                   Show single pipeline status"
        echo "  pipeline-resume                   Resume single pipeline"
        echo "  pipeline-monitor [sec]            Monitor single pipeline artifacts"
        echo "  pipeline-tournament-status        Show tournament status"
        echo "  pipeline-select <pipeline>        Select and merge a passing pipeline (e.g. pipeline-1)"
        echo "  pipeline-reject                   Reject tournament and cleanup"
        echo "  pipeline-cleanup                  Cleanup tournament worktrees/sessions"
        echo "  task [n] \"desc\"             Create task and spawn N agents"
        echo "  status                       Show status"
        echo "  watch [sec]                  Live monitor"
        echo "  logs <agent|session> [n]     Show agent logs"
        echo "  merge <agent|session>        Merge agent work back"
        echo "  clean                        Cleanup worktrees"
        exit 1
        ;;
esac
ENTRY_EOF

chmod +x "$TARGET_REPO/claude-orchestrate.sh"

log_success "Orchestrator entry point created"

# ============================================
# Final Summary
# ============================================
echo ""
echo "============================================"
log_success "Claude Orchestrator initialized!"
echo "============================================"
echo ""
echo "Created structure:"
find "$CLAUDE_DIR" -type f | head -20 | sed 's|'"$TARGET_REPO"'/||'
echo ""
echo "Next steps:"
echo "  1. Review .claude/CLAUDE.md"
echo "  2. Customize agents in .claude/agents/"
echo "  3. Try single pipeline: ./claude-orchestrate.sh pipeline \"Your task\""
echo "  4. Try tournament mode: ./claude-orchestrate.sh pipeline 4 \"Your task\""
echo ""
