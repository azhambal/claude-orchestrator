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
         "$CLAUDE_DIR/docs"
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

# Copy utility scripts
mkdir -p "$CLAUDE_DIR/scripts/utils"
cp "$ORCHESTRATOR_DIR/scripts/utils/"*.py "$CLAUDE_DIR/scripts/utils/" 2>/dev/null || true

# Copy plugin metadata and hooks configuration
mkdir -p "$CLAUDE_DIR/.claude-plugin"
cp "$ORCHESTRATOR_DIR/.claude-plugin/plugin.json" "$CLAUDE_DIR/.claude-plugin/" 2>/dev/null || true
cp "$ORCHESTRATOR_DIR/hooks/hooks.json" "$CLAUDE_DIR/hooks/" 2>/dev/null || true

log_success "Templates and utilities copied"

# ============================================
# Step 3: Run deep analysis with Opus
# ============================================
log_info "Running deep analysis with Opus + ultrathink..."
log_warn "This may take 2-5 minutes and consume significant tokens"

cd "$TARGET_REPO"

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
#   task <description>  - Create and execute a task
#   parallel <n>        - Run n agents in parallel worktrees
#   status              - Show current state
#   clean               - Clean up worktrees

CLAUDE_DIR=".claude"
POSTBOX="$CLAUDE_DIR/postbox"

case "$1" in
    task)
        shift
        TASK_DESC="$*"
        TASK_ID="task-$(date +%s)"
        
        # Add to postbox
        jq --arg id "$TASK_ID" --arg desc "$TASK_DESC" \
            '.pending += [{"id": $id, "description": $desc, "created": now}]' \
            "$POSTBOX/tasks.json" > "$POSTBOX/tasks.json.tmp" && \
            mv "$POSTBOX/tasks.json.tmp" "$POSTBOX/tasks.json"
        
        echo "Task created: $TASK_ID"
        echo "Run: claude to start working on it"
        ;;
        
    parallel)
        N=${2:-2}
        echo "Starting $N parallel agents..."
        bash "$(dirname "$0")/.claude/scripts/worktree.sh" spawn "$N"
        ;;
        
    status)
        echo "=== Pending Tasks ==="
        jq -r '.pending[] | "[\(.id)] \(.description)"' "$POSTBOX/tasks.json" 2>/dev/null || echo "None"
        echo ""
        echo "=== In Progress ==="
        jq -r '.in_progress[] | "[\(.id)] \(.description) (agent: \(.agent))"' "$POSTBOX/tasks.json" 2>/dev/null || echo "None"
        echo ""
        echo "=== Completed Today ==="
        jq -r '.completed[] | select(.completed > (now - 86400)) | "[\(.id)] \(.description)"' "$POSTBOX/tasks.json" 2>/dev/null || echo "None"
        ;;
        
    clean)
        echo "Cleaning up worktrees..."
        bash "$(dirname "$0")/.claude/scripts/worktree.sh" cleanup
        ;;
        
    *)
        echo "Usage: $0 {task|parallel|status|clean}"
        exit 1
        ;;
esac
ENTRY_EOF

chmod +x "$TARGET_REPO/claude-orchestrate.sh"

# Copy worktree script
mkdir -p "$CLAUDE_DIR/scripts"
cp "$ORCHESTRATOR_DIR/scripts/worktree.sh" "$CLAUDE_DIR/scripts/" 2>/dev/null || \
    log_warn "worktree.sh not found, will create later"

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
echo "  3. Run: cd $TARGET_REPO && claude"
echo "  4. Or use: ./claude-orchestrate.sh task 'your task'"
echo ""
