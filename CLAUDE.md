# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Orchestrator is a multi-agent autopilot system for Claude Code that enables parallel autonomous development using specialized agents (Architect, Tester, Linter, Implementer, Critic) coordinated through a postbox communication system and git worktrees.

## Key Commands

```bash
# Initialization
~/claude-orchestrator/scripts/init.sh /path/to/repo     # Set up orchestrator in a project
chmod +x ~/claude-orchestrator/scripts/*.sh             # Make scripts executable

# Orchestration (from initialized project)
./claude-orchestrate.sh pipeline "task description"     # n=1 (default) single pipeline
./claude-orchestrate.sh pipeline 4 "task description"   # tournament mode (n=2..4)
./claude-orchestrate.sh pipeline-select pipeline-1      # Select winner after tournament
./claude-orchestrate.sh task 4 "description"            # Spawn N parallel agents for ONE task
./claude-orchestrate.sh status                          # Show current state
./claude-orchestrate.sh clean                           # Clean up worktrees + tournament sessions

# Worktrees (parallel execution)
./.claude/scripts/worktree.sh spawn 3                   # Create 3 parallel worktrees
./.claude/scripts/worktree.sh list                      # List active worktrees
./.claude/scripts/worktree.sh attach tester             # Attach to latest tester session
./.claude/scripts/worktree.sh status                    # Show agent status
./.claude/scripts/worktree.sh merge tester              # Merge agent's work
./.claude/scripts/worktree.sh cleanup                   # Remove all worktrees
```

## Architecture

### Agent System

Five specialized agents work autonomously:

- **Architect** (Opus): Strategic planning, task decomposition, documentation, ADRs
- **Implementer** (Sonnet): Feature implementation, bug fixes, follows patterns
- **Tester** (Sonnet): Test execution, failure analysis, coverage improvement
- **Linter** (Sonnet): Code quality, formatting, auto-fixes
- **Critic** (Sonnet): Quality review, pattern learning, prompt optimization

### Communication Flow

```
Task → Architect (plan) → Implementer (code) → Tester (verify) → Critic (review) → Done
                            ↓
                    Postbox (.claude/postbox/)
                    - tasks.json (pending/in_progress/completed)
                    - results.json (agent outputs)
```

### Directory Structure

When initialized in a project:
```
project/.claude/
├── .claude-plugin/        # Plugin metadata
│   └── plugin.json        # Plugin configuration
├── CLAUDE.md              # Project-specific config (auto-generated)
├── agents/                # Agent & subagent definitions
│   ├── architect.md       # Main agents
│   ├── implementer.md
│   ├── tester.md
│   ├── linter.md
│   ├── reviewer.md
│   ├── critic.md
│   ├── spec-generator.md
│   ├── comprehensive-tester.md
│   ├── judge.md
│   ├── validator.md
│   ├── code-analyzer.md   # Subagents (specialized)
│   ├── test-generator.md
│   └── doc-writer.md
├── skills/                # Best practices guides
├── memory/                # Persistent learnings
│   ├── analysis.json      # Repository analysis
│   ├── decisions.md       # Architecture Decision Records
│   └── learnings.md       # Patterns and improvements
├── postbox/               # Inter-agent communication
│   ├── tasks.json         # Task queue
│   └── results.json       # Agent outputs
├── pipeline/              # ACIP pipeline runtime artifacts (ignored by default)
│   ├── current/
│   └── history/
├── tournament/            # Tournament runtime artifacts (ignored by default)
│   ├── current/
│   └── history/
├── hooks/                 # Event hooks (Claude Code format)
│   ├── hooks.json         # Hook definitions
│   └── README.md          # Hook documentation
├── docs/                  # Detailed documentation
│   ├── ARCHITECTURE.md
│   └── WORKFLOWS.md
└── scripts/
    ├── worktree.sh        # Parallel worktree manager
    ├── pipeline.sh        # Pipeline (n=1) + Tournament (n=2..4)
    ├── tournament.sh      # Deprecated wrapper (kept for compatibility)
    └── pipeline-monitor.sh
```

## Core Workflows

### init.sh - Initialize Repository
1. Creates `.claude/` directory structure
2. Copies agent templates and configuration
3. Runs deep analysis with Opus + ultrathink
4. Generates customized CLAUDE.md and ARCHITECTURE.md
5. Creates `claude-orchestrate.sh` entry point

### pipeline.sh - Pipeline (Single + Tournament)
- `pipeline.sh run [n] "desc"` where **n=1** (default) runs a single ACIP pipeline, **n=2..4** runs tournament mode
- Single pipeline phases:
  - Phase 1: Architecture (Architect ↔ Critic loop)
  - Phase 2: Test generation & validation
  - Phase 3: Implementation (Implementer ↔ tests loop)
  - Phase 4: Documentation
- Tournament mode adds:
  - Spec tests → parallel pipelines → comprehensive tests → validation → judge → human selection

### tournament.sh - Deprecated Wrapper
- Kept for backward compatibility; delegates to `pipeline.sh`
- Phase 1: Architecture (Architect ↔ Critic loop)
- Phase 2: Test generation & validation
- Phase 3: Implementation (Implementer ↔ tests loop)
- Phase 4: Documentation

### worktree.sh - Parallel Agents
- Creates git worktrees for isolated parallel work
- Spawns agents in tmux sessions with branch per agent
- Manages task assignment from postbox
- Handles merging and cleanup

### orchestrate.sh - Autopilot (Optional/Legacy)
- A separate autopilot loop (architect→implementer→tester→critic) lives in `.claude/scripts/orchestrate.sh`
- Not exposed as top-level `claude-orchestrate.sh` commands by default to avoid name conflicts

## Agent Guidelines

### Architect
- Keep CLAUDE.md under 100 lines (details go to docs/)
- Write ADRs to `.claude/memory/decisions.md`
- Create structured tasks in postbox with acceptance criteria
- Use "think hard" for planning, "ultrathink" for major decisions

### Implementer
- Read existing code patterns before implementing
- Match existing style exactly
- Make minimal, focused changes
- Run tests and linting before reporting
- Write results to postbox with verification details

### Tester
- Detect test framework from project files
- Run tests using project's test command
- Write new tests following existing patterns
- Report failures with root cause analysis

### Linter
- Auto-fix safe issues (formatting, imports)
- Never auto-fix logic changes
- Categorize issues by severity (error/warning/style)
- Commit only linting changes separately

### Critic
- Evaluate completed work against acceptance criteria
- Track patterns in `.claude/memory/learnings.md`
- Suggest prompt improvements when issues repeat
- Use scores: correctness (40%), readability (20%), maintainability (20%), performance (10%), security (10%)

## Token Optimization

Built-in practices:
1. Tiered documentation: Lean CLAUDE.md, details in docs/
2. Model selection: Opus for planning, Sonnet for execution
3. /clear between unrelated tasks
4. Structured JSON in postbox, not verbose prose
5. Targeted reads using grep before full file reads
6. Lazy-load docs/ on demand

## Postbox Communication

### Task Format
```json
{
  "id": "task-{timestamp}",
  "agent": "implementer|tester|linter|critic",
  "description": "Clear, actionable description",
  "context": ["relevant/file/paths"],
  "acceptance_criteria": ["specific criteria"],
  "priority": "high|medium|low",
  "depends_on": ["task-id-if-any"]
}
```

### Result Format
```json
{
  "task_id": "task-xxx",
  "agent": "implementer",
  "status": "success|failure|partial",
  "summary": "Brief description",
  "details": {...},
  "completed_at": "ISO timestamp"
}
```

## Requirements

- Claude Code CLI
- Git 2.23+ (for worktrees)
- tmux (for parallel agents)
- jq (for JSON processing)
- Bash 4+

## Configuration

Main config: `config.yaml`
- Model allocation (Opus for analysis/architecture, Sonnet for workers)
- Thinking levels per task type
- Worktree settings (max_parallel: 3)
- Token optimization thresholds

## Hooks

Event-driven automation using official Claude Code hooks format:
- `hooks/hooks.json` - Hook definitions (PreToolUse, PostToolUse, PreCommand, PostCommand)
- Automatic logging of tool usage and agent lifecycle
- Memory management and cleanup
- See `hooks/README.md` for customization guide

## Subagents

Specialized AI assistants for focused tasks (Claude Code standard):
- **code-analyzer** - Analyzes code structure and dependencies before changes
- **test-generator** - Creates comprehensive test suites
- **doc-writer** - Writes technical documentation
- Claude automatically delegates based on task description
