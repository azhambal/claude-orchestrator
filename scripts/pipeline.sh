#!/bin/bash
# ============================================
# ACIP Pipeline - Architect-Critic-Implement Pipeline
# ============================================
# Implements a multi-phase development pipeline:
#   Phase 1: Architecture (Architect ↔ Critic loop)
#   Phase 2: Test Generation & Validation
#   Phase 3: Implementation (Implementer ↔ Tests loop)
#   Phase 4: Documentation
#
# Usage:
#   pipeline.sh run [n] "Task description"   # n=1 (default) single pipeline; n=2..4 tournament mode
#   pipeline.sh status                       # show single pipeline status
#   pipeline.sh resume                       # resume interrupted single pipeline
#   pipeline.sh tournament-status            # show tournament status
#   pipeline.sh tournament-select <pipeline> # select winner (e.g. pipeline-1)
#   pipeline.sh tournament-reject            # reject and cleanup tournament
#   pipeline.sh tournament-cleanup           # cleanup tournament worktrees/sessions
#
# Notes:
# - Designed to be installed into target repo at: .claude/scripts/pipeline.sh
# - Uses Claude Code CLI ("claude") by default.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$REPO_ROOT/.claude"
PIPELINE_DIR="$CLAUDE_DIR/pipeline"
CURRENT_DIR="$PIPELINE_DIR/current"

# Tournament directories
TOURNAMENT_DIR="$CLAUDE_DIR/tournament"
TOURNAMENT_CURRENT_DIR="$TOURNAMENT_DIR/current"
WORKTREES_BASE="${WORKTREES_BASE:-$REPO_ROOT/../.worktrees}"

# Tournament settings
MAX_WAIT_TIME="${MAX_WAIT_TIME:-7200}" # seconds

# Limits (override via env)
MAX_ARCHITECT_ITERATIONS="${MAX_ARCHITECT_ITERATIONS:-5}"
MAX_IMPLEMENT_ITERATIONS="${MAX_IMPLEMENT_ITERATIONS:-10}"

# Claude CLI config (override via env)
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-Read,Write,Edit,Bash,Grep,Glob}"

MODEL_ARCHITECT="${MODEL_ARCHITECT:-opus}"
MODEL_CRITIC="${MODEL_CRITIC:-sonnet}"
MODEL_TESTGEN="${MODEL_TESTGEN:-sonnet}"
MODEL_VALIDATOR="${MODEL_VALIDATOR:-sonnet}"
MODEL_IMPLEMENTER="${MODEL_IMPLEMENTER:-sonnet}"
MODEL_DOC_WRITER="${MODEL_DOC_WRITER:-sonnet}"

# Tournament models
MODEL_SPEC_GEN="${MODEL_SPEC_GEN:-sonnet}"
MODEL_COMPREHENSIVE="${MODEL_COMPREHENSIVE:-sonnet}"
MODEL_JUDGE="${MODEL_JUDGE:-opus}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() {
  echo -e "\n${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${MAGENTA}${BOLD}  PHASE $1: $2${NC}"
  echo -e "${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
}

log_tournament_phase() {
  echo -e "\n${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${MAGENTA}${BOLD}  TOURNAMENT PHASE $1: $2${NC}"
  echo -e "${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    return 1
  fi
}

validate_pipeline_count() {
  local n="${1:-}"
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    log_error "Invalid pipeline count: '$n' (expected an integer between 1 and 4)"
    return 1
  fi
  if [ "$n" -lt 1 ] || [ "$n" -gt 4 ]; then
    log_error "Invalid pipeline count: $n (must be between 1 and 4)"
    return 1
  fi
}

detect_main_branch() {
  if git show-ref --verify --quiet "refs/heads/main"; then
    echo "main"
  elif git show-ref --verify --quiet "refs/heads/master"; then
    echo "master"
  else
    echo "main"
  fi
}

has_file() { [ -f "$REPO_ROOT/$1" ]; }
has_dir() { [ -d "$REPO_ROOT/$1" ]; }

detect_tests_dir() {
  if [ -n "${PIPELINE_TESTS_DIR:-}" ]; then
    echo "$REPO_ROOT/${PIPELINE_TESTS_DIR#/}"
    return
  fi
  for d in tests test __tests__ spec; do
    if [ -d "$REPO_ROOT/$d" ]; then
      echo "$REPO_ROOT/$d"
      return
    fi
  done
  echo "$REPO_ROOT/tests"
}

detect_source_dir() {
  if [ -n "${PIPELINE_SOURCE_DIR:-}" ]; then
    echo "$REPO_ROOT/${PIPELINE_SOURCE_DIR#/}"
    return
  fi
  for d in src lib app; do
    if [ -d "$REPO_ROOT/$d" ]; then
      echo "$REPO_ROOT/$d"
      return
    fi
  done
  echo "$REPO_ROOT"
}

detect_js_pkg_manager() {
  if [ -f "$REPO_ROOT/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
    echo "pnpm"
  elif [ -f "$REPO_ROOT/yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
    echo "yarn"
  elif command -v npm >/dev/null 2>&1; then
    echo "npm"
  else
    echo ""
  fi
}

detect_test_cmd() {
  if [ -n "${PIPELINE_TEST_CMD:-}" ]; then
    echo "$PIPELINE_TEST_CMD"
    return
  fi

  if has_file "package.json"; then
    local pm
    pm="$(detect_js_pkg_manager)"
    if [ -n "$pm" ]; then
      echo "$pm test"
      return
    fi
  fi

  if has_file "pyproject.toml" || has_file "pytest.ini" || has_file "setup.cfg"; then
    if command -v pytest >/dev/null 2>&1; then
      echo "pytest"
      return
    fi
  fi

  if has_file "go.mod"; then
    if command -v go >/dev/null 2>&1; then
      echo "go test ./..."
      return
    fi
  fi

  if has_file "Cargo.toml"; then
    if command -v cargo >/dev/null 2>&1; then
      echo "cargo test"
      return
    fi
  fi

  if ls "$REPO_ROOT"/*.sln >/dev/null 2>&1 || ls "$REPO_ROOT"/*.csproj >/dev/null 2>&1; then
    if command -v dotnet >/dev/null 2>&1; then
      echo "dotnet test"
      return
    fi
  fi

  # Fallback
  echo ""
}

detect_typecheck_cmd() {
  if [ -n "${PIPELINE_TYPECHECK_CMD:-}" ]; then
    echo "$PIPELINE_TYPECHECK_CMD"
    return
  fi

  if has_file "package.json" && command -v jq >/dev/null 2>&1; then
    if jq -e '.scripts and (.scripts.typecheck != null)' "$REPO_ROOT/package.json" >/dev/null 2>&1; then
      local pm
      pm="$(detect_js_pkg_manager)"
      [ -n "$pm" ] && echo "$pm run typecheck" && return
    fi
  fi

  echo ""
}

run_claude_agent() {
  local agent="$1"
  local model="$2"
  local prompt="$3"

  local agent_file="$CLAUDE_DIR/agents/${agent}.md"
  local full_prompt="$prompt"

  if [ -f "$agent_file" ]; then
    full_prompt="You are acting as the ${agent} agent. Read your instructions from @.claude/agents/${agent}.md first.

${prompt}"
  fi

  "$CLAUDE_BIN" -p "$full_prompt" \
    --model "$model" \
    --allowedTools "$CLAUDE_ALLOWED_TOOLS" \
    --dangerously-skip-permissions \
    --output-format text
}

init_pipeline() {
  local task_desc="$1"
  local task_id="pipeline-$(date +%s)"

  log_info "Initializing pipeline: $task_id"
  mkdir -p "$CURRENT_DIR"
  rm -rf "$CURRENT_DIR"/*
  mkdir -p "$CURRENT_DIR"/{architecture,reviews,tests,logs}

  cat > "$CURRENT_DIR/task.json" <<EOF
{
  "id": "$task_id",
  "description": "$task_desc",
  "created": "$(date -Iseconds)",
  "status": "initialized",
  "phase": 0,
  "architect_iteration": 0,
  "implement_iteration": 0
}
EOF

  echo "$task_id"
}

update_status_str() {
  local field="$1"
  local value="$2"
  [ -f "$CURRENT_DIR/task.json" ] || return 0
  jq --arg field "$field" --arg value "$value" '.[$field] = $value' \
    "$CURRENT_DIR/task.json" > "$CURRENT_DIR/task.json.tmp"
  mv "$CURRENT_DIR/task.json.tmp" "$CURRENT_DIR/task.json"
}

update_status_num() {
  local field="$1"
  local value="$2"
  [ -f "$CURRENT_DIR/task.json" ] || return 0
  jq --arg field "$field" --argjson value "$value" '.[$field] = $value' \
    "$CURRENT_DIR/task.json" > "$CURRENT_DIR/task.json.tmp"
  mv "$CURRENT_DIR/task.json.tmp" "$CURRENT_DIR/task.json"
}

get_task_field() {
  local field="$1"
  jq -r ".$field" "$CURRENT_DIR/task.json" 2>/dev/null || true
}

run_typecheck_if_available() {
  local typecheck_cmd
  typecheck_cmd="$(detect_typecheck_cmd)"
  if [ -z "$typecheck_cmd" ]; then
    log_info "No typecheck command detected; skipping."
    return 0
  fi

  log_info "Running typecheck: $typecheck_cmd"
  cd "$REPO_ROOT"
  if bash -lc "$typecheck_cmd" 2>&1 | tee "$CURRENT_DIR/tests/typecheck.log"; then
    log_success "Typecheck passed"
    return 0
  fi
  log_warn "Typecheck failed (may be expected before implementation)"
  return 1
}

run_tests_and_capture() {
  local test_cmd
  test_cmd="$(detect_test_cmd)"
  mkdir -p "$CURRENT_DIR/tests"

  if [ -z "$test_cmd" ]; then
    log_warn "No test command detected; treating as pass."
    echo "No test command detected. Set PIPELINE_TEST_CMD to enable." > "$CURRENT_DIR/tests/last_test_output.log"
    return 0
  fi

  log_info "Running tests: $test_cmd"
  cd "$REPO_ROOT"

  set +e
  bash -lc "$test_cmd" >"$CURRENT_DIR/tests/last_test_output.log" 2>&1
  local exit_code=$?
  set -e

  if [ $exit_code -eq 0 ]; then
    log_success "Tests passed"
    return 0
  fi

  log_warn "Tests failed (exit code $exit_code)"
  return $exit_code
}

run_phase1_architecture() {
  log_phase "1" "ARCHITECTURE"

  local task_desc
  task_desc="$(get_task_field "description")"

  update_status_num "phase" 1
  update_status_str "status" "architecture"

  local iteration=1
  local verdict="NEEDS_WORK"

  while [ "$verdict" != "APPROVED" ] && [ $iteration -le "$MAX_ARCHITECT_ITERATIONS" ]; do
    log_info "Architecture iteration: $iteration / $MAX_ARCHITECT_ITERATIONS"
    update_status_num "architect_iteration" "$iteration"

    local arch_out="$CURRENT_DIR/architecture/v${iteration}.md"
    local review_out="$CURRENT_DIR/reviews/review-v${iteration}.md"
    local prev_review_ref=""

    if [ $iteration -gt 1 ]; then
      local prev="$CURRENT_DIR/reviews/review-v$((iteration-1)).md"
      if [ -f "$prev" ]; then
        prev_review_ref="Previous review feedback: @$prev (address ALL critical issues)."
      fi
    fi

    log_info "Running Architect..."
    run_claude_agent "architect" "$MODEL_ARCHITECT" "
Task:
$task_desc

$prev_review_ref

Create/Update an architecture document for this task for THIS repository.
Use project context files if available:
- @.claude/CLAUDE.md
- @.claude/docs/ARCHITECTURE.md
- @.claude/memory/analysis.json

Write the architecture document to: $arch_out

Requirements:
- Practical implementation plan (files/modules to touch)
- Public interfaces/contracts
- Data flow / dependencies
- Test strategy aligned with this repo's test framework
" 2>&1 | tee "$CURRENT_DIR/logs/architect-v${iteration}.log"

    log_info "Running Critic..."
    run_claude_agent "critic" "$MODEL_CRITIC" "
Review the architecture document at: @$arch_out

Write a review report to: $review_out

The review MUST include a line exactly in this format:
Verdict: APPROVED | APPROVED_WITH_MINOR | NEEDS_WORK

If NEEDS_WORK, list concrete issues and how to fix them.
" 2>&1 | tee "$CURRENT_DIR/logs/critic-v${iteration}.log"

    verdict="$(grep -oP 'Verdict:\s*\K(APPROVED|APPROVED_WITH_MINOR|NEEDS_WORK)' "$review_out" 2>/dev/null | head -1 || echo "NEEDS_WORK")"
    log_info "Critic verdict: ${YELLOW}${verdict}${NC}"

    if [ "$verdict" = "APPROVED" ] || [ "$verdict" = "APPROVED_WITH_MINOR" ]; then
      cp "$arch_out" "$CURRENT_DIR/architecture/final.md"
      log_success "Architecture accepted (v$iteration)"
      verdict="APPROVED"
      break
    fi

    iteration=$((iteration + 1))
  done

  if [ "$verdict" != "APPROVED" ]; then
    log_warn "Max iterations reached; using best-effort architecture (latest)."
    cp "$CURRENT_DIR/architecture/v$((iteration-1)).md" "$CURRENT_DIR/architecture/final.md"
  fi

  update_status_str "phase1_completed" "$(date -Iseconds)"
  return 0
}

run_phase2_tests() {
  log_phase "2" "TEST GENERATION"

  update_status_num "phase" 2
  update_status_str "status" "testing"

  local arch_doc="$CURRENT_DIR/architecture/final.md"
  if [ ! -f "$arch_doc" ]; then
    log_error "Architecture doc not found: $arch_doc"
    return 1
  fi

  local tests_dir
  tests_dir="$(detect_tests_dir)"
  mkdir -p "$tests_dir"

  log_info "Running Test Generator..."
  run_claude_agent "test-generator" "$MODEL_TESTGEN" "
Generate tests for this task using the project's existing test framework and conventions.

Architecture: @$arch_doc

Write tests into this directory (create files as needed): ${tests_dir#$REPO_ROOT/}

Rules:
- Follow existing test patterns and naming in this repo.
- Prefer black-box tests.
- Do NOT implement production code yet.
" 2>&1 | tee "$CURRENT_DIR/logs/test-generator.log"

  log_info "Running Validator..."
  run_claude_agent "validator" "$MODEL_VALIDATOR" "
Validate the tests generated for this task.

Architecture: @$arch_doc
Tests directory: ${tests_dir#$REPO_ROOT/}

Write a validation report to: $CURRENT_DIR/tests/validation-report.md
Include: Summary, Issues, Coverage gaps, Verdict: VALID or NEEDS_FIX

If minor issues are safe to fix, you may fix tests.
" 2>&1 | tee "$CURRENT_DIR/logs/validator.log"

  run_typecheck_if_available || true

  update_status_str "phase2_completed" "$(date -Iseconds)"
  return 0
}

run_phase3_implementation() {
  log_phase "3" "IMPLEMENTATION"

  update_status_num "phase" 3
  update_status_str "status" "implementing"

  local arch_doc="$CURRENT_DIR/architecture/final.md"
  if [ ! -f "$arch_doc" ]; then
    log_error "Architecture doc not found: $arch_doc"
    return 1
  fi

  local iteration=1
  local tests_pass=false

  while [ "$tests_pass" = "false" ] && [ $iteration -le "$MAX_IMPLEMENT_ITERATIONS" ]; do
    log_info "Implementation iteration: $iteration / $MAX_IMPLEMENT_ITERATIONS"
    update_status_num "implement_iteration" "$iteration"

    if run_tests_and_capture; then
      tests_pass=true
      break
    fi

    log_info "Running Implementer..."
    run_claude_agent "implementer" "$MODEL_IMPLEMENTER" "
Implement the solution so that tests pass.

Task:
$(get_task_field "description")

Architecture: @$arch_doc
Failing test output: @.claude/pipeline/current/tests/last_test_output.log

Rules:
- Follow repo conventions from @.claude/CLAUDE.md when available.
- Make minimal, focused changes.
- Prefer fixing production code; only adjust tests if they are clearly wrong.
" 2>&1 | tee "$CURRENT_DIR/logs/implementer-v${iteration}.log"

    iteration=$((iteration + 1))
  done

  if [ "$tests_pass" = "false" ]; then
    log_error "Max implementation iterations reached with failing tests."
    update_status_str "status" "implementation_stuck"
    return 1
  fi

  update_status_str "phase3_completed" "$(date -Iseconds)"
  update_status_str "status" "tests_passing"
  return 0
}

run_phase4_documentation() {
  log_phase "4" "DOCUMENTATION"

  update_status_num "phase" 4
  update_status_str "status" "documenting"

  local arch_doc="$CURRENT_DIR/architecture/final.md"
  local source_dir
  source_dir="$(detect_source_dir)"

  run_claude_agent "doc-writer" "$MODEL_DOC_WRITER" "
Document the work that was implemented for this task.

Task:
$(get_task_field "description")

Architecture: @$arch_doc

Focus:
- Update README / docs as appropriate
- Document public APIs and usage
- Note any trade-offs or follow-ups in .claude/memory/learnings.md if relevant

Use repo conventions from @.claude/CLAUDE.md when available.
" 2>&1 | tee "$CURRENT_DIR/logs/doc-writer.log"

  update_status_str "phase4_completed" "$(date -Iseconds)"
  update_status_str "status" "completed"
  log_success "Documentation step completed"
  return 0
}

archive_pipeline() {
  local task_id
  task_id="$(get_task_field "id")"
  if [ -z "$task_id" ] || [ "$task_id" = "null" ]; then
    return 0
  fi
  local archive_dir="$PIPELINE_DIR/history/$task_id"
  mkdir -p "$archive_dir"
  cp -r "$CURRENT_DIR"/* "$archive_dir/" 2>/dev/null || true
  log_info "Archived pipeline artifacts to: $archive_dir"
}

run_pipeline() {
  local task_desc="$1"
  if [ -z "$task_desc" ]; then
    log_error "Task description is required"
    echo "Usage: $0 run \"Task description\""
    exit 1
  fi

  require_cmd jq
  require_cmd "$CLAUDE_BIN"

  mkdir -p "$PIPELINE_DIR"/{current,history}

  echo ""
  echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║     ACIP Pipeline - Architect-Critic-Implement Pipeline       ║${NC}"
  echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local task_id
  task_id="$(init_pipeline "$task_desc")"
  log_info "Task ID: $task_id"
  log_info "Description: $task_desc"
  echo ""

  local start_time end_time duration
  start_time=$(date +%s)

  run_phase1_architecture
  run_phase2_tests
  run_phase3_implementation
  run_phase4_documentation

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  archive_pipeline

  echo ""
  echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║                    PIPELINE COMPLETED                         ║${NC}"
  echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  log_success "Task: $task_desc"
  log_success "Duration: ${duration}s"
  echo ""
}

show_status() {
  if [ ! -f "$CURRENT_DIR/task.json" ]; then
    log_info "No active pipeline"
    return 0
  fi

  echo ""
  echo -e "${CYAN}${BOLD}=== Pipeline Status ===${NC}"
  echo ""

  echo "Task ID: $(get_task_field "id")"
  echo "Description: $(get_task_field "description")"
  echo "Status: $(get_task_field "status")"
  echo "Phase: $(get_task_field "phase")"
  echo "Architect Iterations: $(get_task_field "architect_iteration")"
  echo "Implement Iterations: $(get_task_field "implement_iteration")"
  echo ""

  echo -e "${CYAN}Artifacts:${NC}"
  [ -d "$CURRENT_DIR/architecture" ] && echo "  Architecture: $(ls -1 "$CURRENT_DIR/architecture"/*.md 2>/dev/null | wc -l)"
  [ -d "$CURRENT_DIR/reviews" ] && echo "  Reviews:       $(ls -1 "$CURRENT_DIR/reviews"/*.md 2>/dev/null | wc -l)"
  [ -d "$CURRENT_DIR/tests" ] && echo "  Test reports:  $(ls -1 "$CURRENT_DIR/tests"/*.md 2>/dev/null | wc -l)"
  echo ""
}

resume_pipeline() {
  if [ ! -f "$CURRENT_DIR/task.json" ]; then
    log_error "No active pipeline to resume"
    exit 1
  fi

  require_cmd jq
  require_cmd "$CLAUDE_BIN"

  local phase
  phase="$(get_task_field "phase")"
  log_info "Resuming pipeline from phase $phase"

  case "$phase" in
    0|1)
      run_phase1_architecture
      run_phase2_tests
      run_phase3_implementation
      run_phase4_documentation
      ;;
    2)
      run_phase2_tests
      run_phase3_implementation
      run_phase4_documentation
      ;;
    3)
      run_phase3_implementation
      run_phase4_documentation
      ;;
    4)
      run_phase4_documentation
      ;;
    *)
      log_error "Unknown phase: $phase"
      exit 1
      ;;
  esac

  archive_pipeline
}

# ============================================
# Tournament mode - Parallel Pipeline Competition
# ============================================

init_tournament() {
  local task_desc="$1"
  local n_pipelines="$2"
  local tournament_id="tournament-$(date +%s)"

  log_info "Initializing tournament: $tournament_id"

  rm -rf "$TOURNAMENT_CURRENT_DIR"
  mkdir -p "$TOURNAMENT_CURRENT_DIR"/{spec-tests,comprehensive-tests,results,pipelines}

  cat > "$TOURNAMENT_CURRENT_DIR/tournament.json" <<EOF
{
  "id": "$tournament_id",
  "description": "$task_desc",
  "n_pipelines": $n_pipelines,
  "created": "$(date -Iseconds)",
  "status": "initialized",
  "phase": 0,
  "pipelines": [],
  "passing_pipelines": [],
  "recommended": null,
  "selected": null
}
EOF

  echo "$tournament_id"
}

update_tournament_str() {
  local field="$1"
  local value="$2"
  [ -f "$TOURNAMENT_CURRENT_DIR/tournament.json" ] || return 0
  jq --arg field "$field" --arg value "$value" '.[$field] = $value' \
    "$TOURNAMENT_CURRENT_DIR/tournament.json" > "$TOURNAMENT_CURRENT_DIR/tournament.json.tmp"
  mv "$TOURNAMENT_CURRENT_DIR/tournament.json.tmp" "$TOURNAMENT_CURRENT_DIR/tournament.json"
}

update_tournament_json() {
  local field="$1"
  local value_json="$2"
  [ -f "$TOURNAMENT_CURRENT_DIR/tournament.json" ] || return 0
  jq --arg field "$field" --argjson value "$value_json" '.[$field] = $value' \
    "$TOURNAMENT_CURRENT_DIR/tournament.json" > "$TOURNAMENT_CURRENT_DIR/tournament.json.tmp"
  mv "$TOURNAMENT_CURRENT_DIR/tournament.json.tmp" "$TOURNAMENT_CURRENT_DIR/tournament.json"
}

get_tournament_field() {
  local field="$1"
  jq -r ".$field" "$TOURNAMENT_CURRENT_DIR/tournament.json" 2>/dev/null || true
}

copy_claude_skeleton_to_worktree() {
  local worktree_path="$1"

  mkdir -p "$worktree_path/.claude"

  # Copy only stable config, not runtime artifacts
  [ -d "$CLAUDE_DIR/agents" ] && cp -r "$CLAUDE_DIR/agents" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$CLAUDE_DIR/scripts" ] && cp -r "$CLAUDE_DIR/scripts" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$CLAUDE_DIR/hooks" ] && cp -r "$CLAUDE_DIR/hooks" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$CLAUDE_DIR/.claude-plugin" ] && cp -r "$CLAUDE_DIR/.claude-plugin" "$worktree_path/.claude/" 2>/dev/null || true
  [ -f "$CLAUDE_DIR/settings.local.json" ] && cp "$CLAUDE_DIR/settings.local.json" "$worktree_path/.claude/" 2>/dev/null || true
  [ -d "$CLAUDE_DIR/postbox" ] && cp -r "$CLAUDE_DIR/postbox" "$worktree_path/.claude/" 2>/dev/null || true

  mkdir -p "$worktree_path/.claude/pipeline"/{current,history}
  mkdir -p "$worktree_path/.claude/tournament"/{current,history}
}

# Phase 0: Spec tests (acceptance criteria)
run_tournament_phase0_spec_tests() {
  log_tournament_phase "0" "SPECIFICATION TESTS"

  update_tournament_str "phase" "0"
  update_tournament_str "status" "generating_spec_tests"

  local task_desc
  task_desc="$(get_tournament_field "description")"

  rm -rf "$TOURNAMENT_CURRENT_DIR/spec-tests"/*
  mkdir -p "$TOURNAMENT_CURRENT_DIR/spec-tests"

  log_info "Generating acceptance criteria tests..."
  cd "$REPO_ROOT"
  run_claude_agent "spec-generator" "$MODEL_SPEC_GEN" "
Generate specification (acceptance criteria) tests for this task.

Task:
$task_desc

Output location (IMPORTANT):
- Write ALL files under: .claude/tournament/current/spec-tests/
- Mirror repo-relative paths inside this directory.
  Example: to create tests/tournament-spec/foo.test.ts, write:
  .claude/tournament/current/spec-tests/tests/tournament-spec/foo.test.ts

Rules:
- Follow this repo's test framework and conventions (inspect existing tests/config).
- Tests must define WHAT behavior is required, not HOW it's implemented.
- Do not write outside the spec-tests directory.
" 2>&1 | tee "$TOURNAMENT_CURRENT_DIR/spec-tests/spec-generator.log"

  local file_count
  file_count=$(find "$TOURNAMENT_CURRENT_DIR/spec-tests" -type f 2>/dev/null | wc -l)
  log_success "Generated $file_count spec file(s)"

  update_tournament_str "phase0_completed" "$(date -Iseconds)"
}

# Phase 1: Parallel pipelines
spawn_parallel_pipelines() {
  log_tournament_phase "1" "PARALLEL PIPELINES"

  update_tournament_str "phase" "1"
  update_tournament_str "status" "running_pipelines"

  local n_pipelines
  n_pipelines="$(get_tournament_field "n_pipelines")"

  local task_desc
  task_desc="$(get_tournament_field "description")"

  local tournament_id
  tournament_id="$(get_tournament_field "id")"

  local repo_name
  repo_name="$(basename "$REPO_ROOT")"

  mkdir -p "$WORKTREES_BASE"

  local pipeline_info="[]"

  cd "$REPO_ROOT"

  for i in $(seq 1 "$n_pipelines"); do
    local timestamp
    timestamp=$(date +%s)
    sleep 0.1

    local pipeline_name="pipeline-$i"
    local worktree_name="${repo_name}-tournament-${pipeline_name}-${timestamp}"
    local worktree_path="$WORKTREES_BASE/$worktree_name"
    local branch_name="tournament/$tournament_id/$pipeline_name"

    log_info "Creating worktree for $pipeline_name: $worktree_name"

    git branch "$branch_name" HEAD 2>/dev/null || true
    git worktree add "$worktree_path" "$branch_name"

    # Copy orchestrator skeleton
    copy_claude_skeleton_to_worktree "$worktree_path"

    # Copy spec tests into the worktree root (repo-relative)
    cp -r "$TOURNAMENT_CURRENT_DIR/spec-tests/." "$worktree_path/" 2>/dev/null || true

    local abs_worktree_path
    abs_worktree_path="$(cd "$worktree_path" && pwd)"

    local tmux_name="tournament-${tournament_id}-${pipeline_name}-${timestamp}"

    # Create runner script
    local pipeline_script="$worktree_path/.claude/run_tournament_pipeline.sh"
    cat > "$pipeline_script" <<SCRIPT_EOF
#!/bin/bash
set -e

cd "$abs_worktree_path"

echo "Starting tournament pipeline: $pipeline_name"
echo "Tournament: $tournament_id"
echo "Task: $task_desc"
echo ""

set +e
bash ".claude/scripts/pipeline.sh" run 1 "$task_desc" 2>&1 | tee ".claude/tournament_pipeline.log"
exit_code=\${PIPESTATUS[0]}
set -e

if [ \$exit_code -eq 0 ]; then
  echo "SUCCESS" > ".claude/tournament_status"
  echo "Pipeline $pipeline_name completed successfully"
else
  echo "FAILED" > ".claude/tournament_status"
  echo "Pipeline $pipeline_name failed with exit code \$exit_code"
fi

exit \$exit_code
SCRIPT_EOF
    chmod +x "$pipeline_script"

    log_info "Starting pipeline in tmux session: $tmux_name"
    tmux new-session -d -s "$tmux_name" -c "$abs_worktree_path" \
      "$pipeline_script; exec bash" 2>/dev/null || log_warn "tmux session $tmux_name may already exist"

    pipeline_info=$(echo "$pipeline_info" | jq \
      --arg name "$pipeline_name" \
      --arg path "$abs_worktree_path" \
      --arg branch "$branch_name" \
      --arg status "RUNNING" \
      --arg tmux "$tmux_name" \
      '. += [{"name": $name, "path": $path, "branch": $branch, "status": $status, "tmux_session": $tmux, "started": now, "completed": null}]')

    log_success "Spawned $pipeline_name in $worktree_path"
  done

  update_tournament_json "pipelines" "$pipeline_info"

  echo ""
  log_info "All pipelines spawned. Monitor: tmux ls | grep tournament-"
  echo ""

  wait_for_pipelines

  update_tournament_str "phase1_completed" "$(date -Iseconds)"
}

wait_for_pipelines() {
  local start_time
  start_time=$(date +%s)

  local n_pipelines
  n_pipelines="$(get_tournament_field "n_pipelines")"

  local all_done=false
  while [ "$all_done" = "false" ]; do
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - start_time))

    if [ $elapsed -gt "$MAX_WAIT_TIME" ]; then
      log_warn "Max wait time exceeded; some pipelines may still be running."
      break
    fi

    local completed=0 running=0 failed=0

    local pipelines_json
    pipelines_json="$(jq -c '.pipelines[]' "$TOURNAMENT_CURRENT_DIR/tournament.json" 2>/dev/null || true)"

    while IFS= read -r pipeline; do
      [ -n "$pipeline" ] || continue
      local p_tmux status_file
      p_tmux="$(echo "$pipeline" | jq -r '.tmux_session')"
      status_file="$(echo "$pipeline" | jq -r '.path')/.claude/tournament_status"

      if [ -f "$status_file" ]; then
        local st
        st="$(cat "$status_file" 2>/dev/null || echo "FAILED")"
        if [ "$st" = "SUCCESS" ]; then
          completed=$((completed + 1))
        else
          failed=$((failed + 1))
        fi
      else
        if tmux has-session -t "$p_tmux" 2>/dev/null; then
          running=$((running + 1))
        else
          failed=$((failed + 1))
        fi
      fi
    done <<< "$pipelines_json"

    local total_done
    total_done=$((completed + failed))

    echo -ne "\r[$(date '+%H:%M:%S')] Pipelines: ${GREEN}$completed completed${NC}, ${YELLOW}$running running${NC}, ${RED}$failed failed${NC} (elapsed: ${elapsed}s)    "

    if [ $total_done -ge "$n_pipelines" ]; then
      all_done=true
      echo ""
    else
      sleep 10
    fi
  done

  # Update pipeline statuses
  local updated="[]"
  local pipelines_json
  pipelines_json="$(jq -c '.pipelines[]' "$TOURNAMENT_CURRENT_DIR/tournament.json" 2>/dev/null || true)"
  while IFS= read -r pipeline; do
    [ -n "$pipeline" ] || continue
    local p_path status_file p_status
    p_path="$(echo "$pipeline" | jq -r '.path')"
    status_file="$p_path/.claude/tournament_status"
    if [ -f "$status_file" ]; then
      p_status="$(cat "$status_file" 2>/dev/null || echo "FAILED")"
    else
      p_status="FAILED"
    fi
    pipeline="$(echo "$pipeline" | jq --arg status "$p_status" '.status = $status | .completed = now')"
    updated="$(echo "$updated" | jq --argjson p "$pipeline" '. += [$p]')"
  done <<< "$pipelines_json"

  update_tournament_json "pipelines" "$updated"
  log_info "Pipeline execution phase completed"
}

# Phase 2: Comprehensive tests
run_tournament_phase2_comprehensive_tests() {
  log_tournament_phase "2" "COMPREHENSIVE TESTS"

  update_tournament_str "phase" "2"
  update_tournament_str "status" "generating_comprehensive_tests"

  local task_desc
  task_desc="$(get_tournament_field "description")"

  local impl_paths=()
  local pipelines_json
  pipelines_json="$(jq -c '.pipelines[] | select(.status == "SUCCESS")' "$TOURNAMENT_CURRENT_DIR/tournament.json" 2>/dev/null || true)"
  while IFS= read -r pipeline; do
    [ -n "$pipeline" ] || continue
    impl_paths+=("$(echo "$pipeline" | jq -r '.path')")
  done <<< "$pipelines_json"

  if [ ${#impl_paths[@]} -eq 0 ]; then
    log_warn "No successful pipelines; skipping comprehensive tests."
    return 1
  fi

  rm -rf "$TOURNAMENT_CURRENT_DIR/comprehensive-tests"/*
  mkdir -p "$TOURNAMENT_CURRENT_DIR/comprehensive-tests"

  local paths_block=""
  for p in "${impl_paths[@]}"; do
    paths_block="$paths_block
- $p"
  done

  log_info "Generating comprehensive tests from successful implementations..."
  cd "$REPO_ROOT"
  run_claude_agent "comprehensive-tester" "$MODEL_COMPREHENSIVE" "
Generate comprehensive tests by analyzing multiple successful implementations.

Task:
$task_desc

Candidate implementation roots:
$paths_block

Output location (IMPORTANT):
- Write ALL files under: .claude/tournament/current/comprehensive-tests/
- Mirror repo-relative paths inside this directory.
  Example: to create tests/tournament-comprehensive/foo.test.ts, write:
  .claude/tournament/current/comprehensive-tests/tests/tournament-comprehensive/foo.test.ts

Rules:
- Follow this repo's test framework and conventions.
- Focus on the union of public APIs and edge cases across implementations.
- Do not write outside the comprehensive-tests directory.
" 2>&1 | tee "$TOURNAMENT_CURRENT_DIR/comprehensive-tests/comprehensive-tester.log"

  local file_count
  file_count=$(find "$TOURNAMENT_CURRENT_DIR/comprehensive-tests" -type f 2>/dev/null | wc -l)
  log_success "Generated $file_count comprehensive file(s)"

  update_tournament_str "phase2_completed" "$(date -Iseconds)"
}

detect_tournament_test_cmd() {
  if [ -n "${TOURNAMENT_TEST_CMD:-}" ]; then
    echo "$TOURNAMENT_TEST_CMD"
    return
  fi
  if [ -f "$REPO_ROOT/package.json" ]; then
    if [ -f "$REPO_ROOT/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
      echo "pnpm test"
      return
    fi
    if [ -f "$REPO_ROOT/yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
      echo "yarn test"
      return
    fi
    if command -v npm >/dev/null 2>&1; then
      echo "npm test"
      return
    fi
  fi
  if command -v pytest >/dev/null 2>&1 && { [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/pytest.ini" ]; }; then
    echo "pytest"
    return
  fi
  if command -v go >/dev/null 2>&1 && [ -f "$REPO_ROOT/go.mod" ]; then
    echo "go test ./..."
    return
  fi
  if command -v cargo >/dev/null 2>&1 && [ -f "$REPO_ROOT/Cargo.toml" ]; then
    echo "cargo test"
    return
  fi
  echo ""
}

detect_tournament_lint_cmd() {
  if [ -n "${TOURNAMENT_LINT_CMD:-}" ]; then
    echo "$TOURNAMENT_LINT_CMD"
    return
  fi
  if [ -f "$REPO_ROOT/package.json" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.scripts and (.scripts.lint != null)' "$REPO_ROOT/package.json" >/dev/null 2>&1; then
      if [ -f "$REPO_ROOT/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
        echo "pnpm run lint"
        return
      fi
      if [ -f "$REPO_ROOT/yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
        echo "yarn lint"
        return
      fi
      if command -v npm >/dev/null 2>&1; then
        echo "npm run lint"
        return
      fi
    fi
  fi
  echo ""
}

# Phase 3: Validation
run_tournament_phase3_validation() {
  log_tournament_phase "3" "VALIDATION"

  update_tournament_str "phase" "3"
  update_tournament_str "status" "validating"

  local test_cmd lint_cmd
  test_cmd="$(detect_tournament_test_cmd)"
  lint_cmd="$(detect_tournament_lint_cmd)"

  local passing="[]"

  local pipelines_json
  pipelines_json="$(jq -c '.pipelines[] | select(.status == "SUCCESS")' "$TOURNAMENT_CURRENT_DIR/tournament.json" 2>/dev/null || true)"

  while IFS= read -r pipeline; do
    [ -n "$pipeline" ] || continue
    local p_name p_path
    p_name="$(echo "$pipeline" | jq -r '.name')"
    p_path="$(echo "$pipeline" | jq -r '.path')"

    log_info "Validating $p_name..."

    # Copy comprehensive tests into repo root of worktree (repo-relative)
    cp -r "$TOURNAMENT_CURRENT_DIR/comprehensive-tests/." "$p_path/" 2>/dev/null || true

    cd "$p_path"

    local test_result="PASS"
    local coverage="null"
    local lint_score="null"

    if [ -n "$test_cmd" ]; then
      set +e
      bash -lc "$test_cmd" >".claude/tournament_validation_tests.log" 2>&1
      local exit_code=$?
      set -e
      if [ $exit_code -ne 0 ]; then
        test_result="FAIL"
      fi
    else
      log_warn "No test command detected; assuming PASS for $p_name."
    fi

    if [ -n "$lint_cmd" ]; then
      set +e
      bash -lc "$lint_cmd" >".claude/tournament_validation_lint.log" 2>&1
      local lint_exit=$?
      set -e
      lint_score=$([ $lint_exit -eq 0 ] && echo "100" || echo "70")
    fi

    # Node-style coverage (best-effort)
    if [ -f "coverage/coverage-summary.json" ] && command -v jq >/dev/null 2>&1; then
      coverage="$(jq '.total.lines.pct // 0' coverage/coverage-summary.json 2>/dev/null || echo "0")"
    fi

    cd "$REPO_ROOT"

    mkdir -p "$TOURNAMENT_CURRENT_DIR/results"
    cat > "$TOURNAMENT_CURRENT_DIR/results/${p_name}-report.json" <<EOF
{
  "pipeline": "$p_name",
  "path": "$p_path",
  "test_result": "$test_result",
  "coverage": $coverage,
  "lint_score": $lint_score,
  "validated_at": "$(date -Iseconds)"
}
EOF

    if [ "$test_result" = "PASS" ]; then
      passing="$(echo "$passing" | jq --arg name "$p_name" '. += [$name]')"
      log_success "$p_name: PASS"
    else
      log_warn "$p_name: FAIL"
    fi
  done <<< "$pipelines_json"

  update_tournament_json "passing_pipelines" "$passing"
  log_info "$(echo "$passing" | jq 'length') pipeline(s) passed validation"

  update_tournament_str "phase3_completed" "$(date -Iseconds)"
}

# Phase 4: Judge
run_tournament_phase4_judge() {
  log_tournament_phase "4" "JUDGE SELECTION"

  update_tournament_str "phase" "4"
  update_tournament_str "status" "judging"

  local passing
  passing="$(get_tournament_field "passing_pipelines")"

  if [ "$passing" = "null" ] || [ "$passing" = "[]" ]; then
    log_error "No passing pipelines; cannot judge."
    update_tournament_str "status" "no_passing_pipelines"
    return 1
  fi

  local task_desc
  task_desc="$(get_tournament_field "description")"

  local impl_details=""
  for name in $(echo "$passing" | jq -r '.[]'); do
    local result_file="$TOURNAMENT_CURRENT_DIR/results/${name}-report.json"
    local p_path
    p_path="$(jq -r --arg n "$name" '.pipelines[] | select(.name == $n) | .path' "$TOURNAMENT_CURRENT_DIR/tournament.json")"
    local cov lint
    cov="$(jq -r '.coverage // "N/A"' "$result_file" 2>/dev/null || echo "N/A")"
    lint="$(jq -r '.lint_score // "N/A"' "$result_file" 2>/dev/null || echo "N/A")"
    impl_details="$impl_details
### $name
- Path: $p_path
- Coverage: $cov
- Lint: $lint
"
  done

  cd "$REPO_ROOT"
  run_claude_agent "judge" "$MODEL_JUDGE" "
Compare the passing tournament candidates and recommend the best one.

Task:
$task_desc

Passing candidates:
$impl_details

Validation results directory: @.claude/tournament/current/results

Write your report to: .claude/tournament/current/judge-recommendation.md
Your report MUST include exactly one line:
RECOMMENDED: pipeline-X
Or:
RECOMMENDED: NONE
" 2>&1 | tee "$TOURNAMENT_CURRENT_DIR/judge.log"

  local recommended
  recommended="$(grep -oP 'RECOMMENDED:\s*\K[^\s]+' "$TOURNAMENT_CURRENT_DIR/judge-recommendation.md" 2>/dev/null | head -1 || true)"

  if [ -n "$recommended" ]; then
    update_tournament_str "recommended" "$recommended"
    log_success "Judge recommends: $recommended"
  else
    log_warn "Judge did not provide a clear recommendation"
  fi

  update_tournament_str "phase4_completed" "$(date -Iseconds)"
}

# Phase 5: Human review
run_tournament_phase5_human_review() {
  log_tournament_phase "5" "HUMAN REVIEW"

  update_tournament_str "phase" "5"
  update_tournament_str "status" "awaiting_human_review"

  local task_desc recommended passing
  task_desc="$(get_tournament_field "description")"
  recommended="$(get_tournament_field "recommended")"
  passing="$(get_tournament_field "passing_pipelines")"

  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}                   TOURNAMENT RESULTS                        ${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo ""

  echo -e "${CYAN}Task:${NC} $task_desc"
  echo ""

  echo -e "${CYAN}Passing Pipelines:${NC}"
  for pipeline_name in $(echo "$passing" | jq -r '.[]'); do
    local result_file="$TOURNAMENT_CURRENT_DIR/results/${pipeline_name}-report.json"
    local cov lint
    cov="$(jq -r '.coverage // "N/A"' "$result_file" 2>/dev/null || echo "N/A")"
    lint="$(jq -r '.lint_score // "N/A"' "$result_file" 2>/dev/null || echo "N/A")"
    if [ "$pipeline_name" = "$recommended" ]; then
      echo -e "  ${GREEN}★ $pipeline_name${NC} (Coverage: $cov, Lint: $lint) ${GREEN}[RECOMMENDED]${NC}"
    else
      echo -e "  • $pipeline_name (Coverage: $cov, Lint: $lint)"
    fi
  done
  echo ""

  if [ -f "$TOURNAMENT_CURRENT_DIR/judge-recommendation.md" ]; then
    echo -e "${CYAN}Judge report (head):${NC}"
    head -20 "$TOURNAMENT_CURRENT_DIR/judge-recommendation.md" | sed 's/^/  /'
    echo ""
  fi

  echo "Commands:"
  echo "  ./claude-orchestrate.sh pipeline-select <pipeline>"
  echo "  ./claude-orchestrate.sh pipeline-reject"
  echo ""
}

archive_tournament() {
  local tournament_id
  tournament_id="$(get_tournament_field "id")"
  [ -n "$tournament_id" ] || return 0
  local archive_dir="$TOURNAMENT_DIR/history/$tournament_id"
  mkdir -p "$archive_dir"
  cp -r "$TOURNAMENT_CURRENT_DIR"/* "$archive_dir/" 2>/dev/null || true
  log_info "Archived tournament to: $archive_dir"
}

cleanup_tournament_worktrees() {
  log_info "Cleaning up tournament tmux sessions..."
  tmux ls 2>/dev/null | grep "tournament-" | cut -d: -f1 | while read -r session; do
    [ -n "$session" ] || continue
    tmux kill-session -t "$session" 2>/dev/null || true
  done || true

  log_info "Removing tournament worktrees..."
  git worktree list 2>/dev/null | grep "tournament-" | awk '{print $1}' | while read -r wt; do
    [ -n "$wt" ] || continue
    git worktree remove --force "$wt" 2>/dev/null || true
  done || true

  log_info "Deleting tournament branches..."
  git branch 2>/dev/null | grep "tournament/" | while read -r br; do
    br="$(echo "$br" | tr -d ' *')"
    [ -n "$br" ] || continue
    git branch -D "$br" 2>/dev/null || true
  done || true

  git worktree prune 2>/dev/null || true
  log_success "Tournament cleanup completed"
}

tournament_select_pipeline() {
  local pipeline_name="$1"
  if [ -z "$pipeline_name" ]; then
    log_error "Pipeline name required"
    exit 1
  fi

  local passing
  passing="$(get_tournament_field "passing_pipelines")"

  if ! echo "$passing" | jq -e --arg name "$pipeline_name" 'index($name) != null' >/dev/null 2>&1; then
    log_error "Pipeline '$pipeline_name' is not in passing list"
    echo "Passing: $(echo "$passing" | jq -r '.[]' | tr '\n' ' ')"
    exit 1
  fi

  local pipeline_path
  pipeline_path="$(jq -r --arg name "$pipeline_name" '.pipelines[] | select(.name == $name) | .path' "$TOURNAMENT_CURRENT_DIR/tournament.json")"

  if [ -z "$pipeline_path" ] || [ "$pipeline_path" = "null" ] || [ ! -d "$pipeline_path" ]; then
    log_error "Pipeline path not found for $pipeline_name"
    exit 1
  fi

  local base_branch
  base_branch="$(detect_main_branch)"

  log_info "Selecting $pipeline_name (base: $base_branch)"
  log_info "Copying changes from: $pipeline_path"

  cd "$pipeline_path"
  local base_commit
  base_commit="$(git merge-base HEAD "$base_branch" 2>/dev/null || true)"

  if [ -z "$base_commit" ]; then
    log_error "Could not determine merge-base vs $base_branch in $pipeline_name"
    exit 1
  fi

  local changes
  changes="$(git diff --name-status "$base_commit" HEAD 2>/dev/null || true)"

  cd "$REPO_ROOT"

  if [ -z "$changes" ]; then
    log_warn "No changes detected to merge"
  else
    echo "$changes" | while IFS=$'\t' read -r status a b; do
      # status can be: M path | A path | D path | R100 old new
      if [[ "$status" =~ ^R ]]; then
        local old_path="$a"
        local new_path="$b"
        # remove old, copy new
        if [ -n "$old_path" ] && [[ "$old_path" != .claude/* ]]; then
          [ -f "$old_path" ] && git rm -f "$old_path" 2>/dev/null || true
        fi
        if [ -n "$new_path" ] && [[ "$new_path" != .claude/* ]]; then
          mkdir -p "$(dirname "$new_path")"
          cp "$pipeline_path/$new_path" "$new_path" 2>/dev/null || true
          git add "$new_path" 2>/dev/null || true
        fi
        continue
      fi

      local path="$a"
      [ -n "$path" ] || continue

      # Never merge runtime orchestrator artifacts
      if [[ "$path" == .claude/* ]]; then
        continue
      fi
      if [[ "$path" == node_modules/* || "$path" == dist/* || "$path" == build/* || "$path" == coverage/* ]]; then
        continue
      fi

      case "$status" in
        D)
          [ -f "$path" ] && git rm -f "$path" 2>/dev/null || true
          ;;
        A|M)
          mkdir -p "$(dirname "$path")"
          cp "$pipeline_path/$path" "$path" 2>/dev/null || true
          git add "$path" 2>/dev/null || true
          ;;
        *)
          # default: treat as modify
          mkdir -p "$(dirname "$path")"
          cp "$pipeline_path/$path" "$path" 2>/dev/null || true
          git add "$path" 2>/dev/null || true
          ;;
      esac
    done

    git commit -m "feat(tournament): select $pipeline_name

Tournament: $(get_tournament_field 'id')
Task: $(get_tournament_field 'description')" 2>/dev/null || log_warn "Nothing to commit"
  fi

  update_tournament_str "selected" "$pipeline_name"
  update_tournament_str "status" "completed"
  update_tournament_str "completed_at" "$(date -Iseconds)"

  archive_tournament
  cleanup_tournament_worktrees

  log_success "Tournament completed. Selected: $pipeline_name"
}

tournament_reject_all() {
  log_info "Rejecting tournament..."
  update_tournament_str "status" "rejected"
  update_tournament_str "completed_at" "$(date -Iseconds)"
  archive_tournament
  cleanup_tournament_worktrees
  log_success "Tournament rejected and cleaned up"
}

show_tournament_status() {
  if [ ! -f "$TOURNAMENT_CURRENT_DIR/tournament.json" ]; then
    log_info "No active tournament"
    return 0
  fi

  echo ""
  echo -e "${CYAN}${BOLD}=== Tournament Status ===${NC}"
  echo ""

  echo "Tournament ID: $(get_tournament_field "id")"
  echo "Task: $(get_tournament_field "description")"
  echo "Status: $(get_tournament_field "status")"
  echo "Phase: $(get_tournament_field "phase")"
  echo "Pipelines: $(get_tournament_field "n_pipelines")"
  echo ""

  echo -e "${CYAN}Pipeline Status:${NC}"
  jq -r '.pipelines[] | "  \(.name): \(.status)"' "$TOURNAMENT_CURRENT_DIR/tournament.json" 2>/dev/null || true
  echo ""

  local passing
  passing="$(get_tournament_field "passing_pipelines")"
  if [ "$passing" != "null" ] && [ "$passing" != "[]" ]; then
    echo -e "${CYAN}Passing:${NC}"
    echo "$passing" | jq -r '.[] | "  • \(.)"' 2>/dev/null || true
    echo ""
  fi

  local recommended
  recommended="$(get_tournament_field "recommended")"
  if [ "$recommended" != "null" ] && [ -n "$recommended" ]; then
    echo -e "${GREEN}Recommended: $recommended${NC}"
    echo ""
  fi
}

run_tournament() {
  local task_desc="$1"
  local n_pipelines="${2:-4}"

  if [ -z "$task_desc" ]; then
    log_error "Task description is required"
    exit 1
  fi

  validate_pipeline_count "$n_pipelines"
  if [ "$n_pipelines" -lt 2 ]; then
    log_error "Tournament mode requires n between 2 and 4"
    exit 1
  fi

  require_cmd jq
  require_cmd git
  require_cmd tmux
  require_cmd "$CLAUDE_BIN"

  mkdir -p "$TOURNAMENT_DIR"/{current,history}

  echo ""
  echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║         TOURNAMENT PIPELINE - Parallel Competition            ║${NC}"
  echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  cd "$REPO_ROOT"

  local tournament_id
  tournament_id="$(init_tournament "$task_desc" "$n_pipelines")"
  log_info "Tournament ID: $tournament_id"
  log_info "Task: $task_desc"
  log_info "Pipelines: $n_pipelines"
  echo ""

  local start_time end_time duration
  start_time=$(date +%s)

  run_tournament_phase0_spec_tests
  spawn_parallel_pipelines
  run_tournament_phase2_comprehensive_tests || log_warn "Comprehensive tests phase had issues; continuing..."
  run_tournament_phase3_validation || log_warn "Validation phase had issues; continuing..."
  run_tournament_phase4_judge || log_warn "Judge phase had issues; continuing to human review..."
  run_tournament_phase5_human_review

  end_time=$(date +%s)
  duration=$((end_time - start_time))
  log_info "Tournament duration: ${duration}s"
}

case "${1:-}" in
  run)
    shift
    n=1
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
      n="$1"
      shift
    fi
    TASK_DESC="$*"
    if [ -z "$TASK_DESC" ]; then
      log_error "Task description is required"
      echo "Usage: $0 run [n] \"description\""
      exit 1
    fi

    validate_pipeline_count "$n"

    if [ "$n" -eq 1 ]; then
      run_pipeline "$TASK_DESC"
    else
      run_tournament "$TASK_DESC" "$n"
    fi
    ;;
  status)
    show_status
    ;;
  resume)
    resume_pipeline
    ;;
  tournament-status)
    require_cmd jq
    show_tournament_status
    ;;
  tournament-select)
    require_cmd jq
    require_cmd git
    tournament_select_pipeline "${2:-}"
    ;;
  tournament-reject)
    require_cmd jq
    require_cmd git
    require_cmd tmux
    cd "$REPO_ROOT"
    tournament_reject_all
    ;;
  tournament-cleanup)
    require_cmd git
    require_cmd tmux
    cd "$REPO_ROOT"
    cleanup_tournament_worktrees
    ;;
  *)
    echo "ACIP Pipeline - Single (n=1) + Tournament (n=2..4)"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  run [n] \"desc\"            Run pipeline (n=1) or tournament (n=2..4)"
    echo "  status                   Show current single pipeline status"
    echo "  resume                   Resume single pipeline from current phase"
    echo "  tournament-status        Show current tournament status"
    echo "  tournament-select <p>    Select and merge a passing pipeline (e.g. pipeline-1)"
    echo "  tournament-reject        Reject tournament and cleanup"
    echo "  tournament-cleanup       Cleanup tournament worktrees/sessions"
    echo ""
    echo "Environment overrides:"
    echo "  PIPELINE_TEST_CMD=...        Override test command"
    echo "  PIPELINE_TYPECHECK_CMD=...   Override typecheck command"
    echo "  PIPELINE_TESTS_DIR=...       Override tests directory (relative to repo root)"
    echo "  CLAUDE_BIN=claude            Claude CLI binary (default: claude)"
    echo "  WORKTREES_BASE=...           Tournament worktrees base dir (default: ../.worktrees)"
    echo "  TOURNAMENT_TEST_CMD=...      Override test command for tournament validation"
    echo "  TOURNAMENT_LINT_CMD=...      Override lint command for tournament validation"
    exit 1
    ;;
esac

