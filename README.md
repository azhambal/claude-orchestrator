# Claude Orchestrator

> Multi-agent autopilot system for Claude Code

Turn Claude Code into an autonomous development team with specialized agents that work in parallel.

## Features

- 🤖 **5 Specialized Agents**: Architect, Tester, Linter, Implementer, Critic
- 🔄 **Full Autopilot**: Agents work autonomously until tasks complete
- 🌳 **Parallel Execution**: Run multiple agents in git worktrees
- 📬 **Postbox System**: File-based inter-agent communication
- 🧠 **Learning System**: Critic tracks patterns and improves prompts
- 💰 **Token Optimized**: Built-in practices for efficiency

## Quick Start

### 1. Install

```bash
# Clone the orchestrator
git clone https://github.com/your/claude-orchestrator.git ~/claude-orchestrator

# Make scripts executable
chmod +x ~/claude-orchestrator/scripts/*.sh
```

### 2. Initialize Your Project

```bash
cd /path/to/your/project
~/claude-orchestrator/scripts/init.sh .
```

This will:
- Analyze your repo with Opus + ultrathink
- Generate optimized CLAUDE.md
- Create agent configurations
- Set up postbox for communication

### 3. Run Tasks

```bash
# Single task with full agent pipeline
./claude-orchestrate.sh run "Add user authentication with JWT"

# Add task to queue
./claude-orchestrate.sh task "Fix login bug"

# Run improvement cycle (lint, test, review)
./claude-orchestrate.sh cycle

# Full autopilot mode
./claude-orchestrate.sh auto
```

### 4. Parallel Agents (Optional)

```bash
# Spawn 3 agents in separate worktrees
./claude-orchestrate.sh parallel 3

# Check status
./.claude/scripts/worktree.sh status

# Attach to specific agent
./.claude/scripts/worktree.sh attach tester

# Cleanup when done
./.claude/scripts/worktree.sh cleanup
```

## Architecture

```
your-project/
├── .claude/
│   ├── CLAUDE.md           # Project config (auto-generated)
│   ├── agents/             # Agent definitions
│   │   ├── architect.md
│   │   ├── tester.md
│   │   ├── linter.md
│   │   ├── implementer.md
│   │   └── critic.md
│   ├── skills/             # Reusable skills
│   ├── memory/             # Persistent learnings
│   │   ├── analysis.json
│   │   ├── decisions.md
│   │   └── learnings.md
│   ├── postbox/            # Inter-agent communication
│   │   ├── tasks.json
│   │   └── results.json
│   ├── docs/               # Detailed documentation
│   │   ├── ARCHITECTURE.md
│   │   └── WORKFLOWS.md
│   └── scripts/
│       └── worktree.sh
└── claude-orchestrate.sh   # Entry point
```

## Agents

| Agent | Model | Role |
|-------|-------|------|
| **Architect** | Opus | Planning, documentation, task decomposition |
| **Tester** | Sonnet | Run tests, analyze failures, improve coverage |
| **Linter** | Sonnet | Code style, formatting, auto-fixes |
| **Implementer** | Sonnet | Write code, fix bugs, refactor |
| **Critic** | Sonnet | Review work, track patterns, improve prompts |

## Workflow

```
┌─────────┐     ┌─────────────┐     ┌─────────────┐
│  Task   │────▶│  Architect  │────▶│ Implementer │
│  Input  │     │  (plan)     │     │  (code)     │
└─────────┘     └─────────────┘     └──────┬──────┘
                                          │
       ┌──────────────────────────────────┘
       ▼
┌─────────────┐     ┌─────────────┐     ┌─────────┐
│   Tester    │────▶│   Critic    │────▶│  Done   │
│  (verify)   │     │  (review)   │     │         │
└─────────────┘     └─────────────┘     └─────────┘
```

## Token Optimization

The system is built with token efficiency in mind:

1. **Tiered documentation**: CLAUDE.md is lean, details in docs/
2. **Model selection**: Opus for planning, Sonnet for execution
3. **Clear between tasks**: Fresh context for unrelated work
4. **Structured output**: JSON in postbox, not verbose prose
5. **Targeted reads**: Agents use grep before reading files

## Commands Reference

```bash
# Orchestration
./claude-orchestrate.sh run "description"    # Full agent pipeline
./claude-orchestrate.sh task "description"   # Add to queue
./claude-orchestrate.sh auto                 # Autopilot mode
./claude-orchestrate.sh cycle                # Improvement cycle
./claude-orchestrate.sh status               # Show status

# Worktrees (parallel)
./.claude/scripts/worktree.sh spawn 3        # Create 3 worktrees
./.claude/scripts/worktree.sh list           # List worktrees
./.claude/scripts/worktree.sh attach tester  # Attach to agent
./.claude/scripts/worktree.sh status         # Agent status
./.claude/scripts/worktree.sh merge tester   # Merge agent's work
./.claude/scripts/worktree.sh cleanup        # Remove all
```

## Customization

### Add Custom Agent

Create `.claude/agents/my-agent.md`:

```markdown
---
name: my-agent
description: What this agent does
model: sonnet
tools: Read, Write, Edit, Bash
---

# My Agent

Instructions for the agent...
```

### Add Project-Specific Rules

Edit `.claude/CLAUDE.md` to add project-specific instructions.

### Customize Postbox

Extend `tasks.json` schema for your workflow needs.

## Requirements

- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- Git 2.23+ (for worktrees)
- tmux (for parallel agents)
- jq (for JSON processing)
- Bash 4+

## Troubleshooting

### "Permission denied"
```bash
chmod +x ~/claude-orchestrator/scripts/*.sh
chmod +x ./claude-orchestrate.sh
```

### "tmux session not found"
```bash
# Check if tmux is installed
tmux -V

# List sessions
tmux ls
```

### "Agent not responding"
```bash
# Check worktree status
./.claude/scripts/worktree.sh status

# Attach and check
./.claude/scripts/worktree.sh attach <agent>
```

## Contributing

Contributions welcome! Areas of interest:
- New specialized agents
- Better token optimization
- Integration with more tools
- Test coverage

## License

MIT
