# Claude Orchestrator

> Multi-agent autopilot system for Claude Code

Turn Claude Code into an autonomous development team with specialized agents that work in parallel.

## Features

- 🤖 **5 Specialized Agents**: Architect, Tester, Linter, Implementer, Critic
- 🔄 **Full Autopilot**: Agents work autonomously until tasks complete
- 🏁 **Tournament Mode**: Run multiple pipelines in parallel and select the best
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
# Single ACIP pipeline (default n=1)
./claude-orchestrate.sh pipeline "Fix login bug"

# Tournament mode (n=2..4)
./claude-orchestrate.sh pipeline 4 "Add user authentication with JWT"

# Select winner after tournament completes (example)
./claude-orchestrate.sh pipeline-select pipeline-1

# Spawn N parallel agents for ONE task (worktrees)
./claude-orchestrate.sh task 4 "Refactor module X"
```

### 4. Parallel Agents (Optional)

```bash
# Live monitor
./claude-orchestrate.sh watch

# List tmux sessions
tmux ls

# Attach to a session (session names include timestamps)
./.claude/scripts/worktree.sh attach <agent-instance>   # attaches latest
# or: tmux attach -t claude-agent-implementer-1-1700000000

# Cleanup (includes tournament sessions/worktrees)
./claude-orchestrate.sh clean
```

## Architecture

```
your-project/
├── .claude/
│   ├── .claude-plugin/     # Plugin metadata
│   │   └── plugin.json
│   ├── CLAUDE.md           # Project config (auto-generated)
│   ├── agents/             # Agent & subagent definitions
│   │   ├── architect.md    # Main agents
│   │   ├── tester.md
│   │   ├── linter.md
│   │   ├── implementer.md
│   │   ├── critic.md
│   │   ├── code-analyzer.md   # Subagents
│   │   ├── test-generator.md
│   │   └── doc-writer.md
│   ├── skills/             # Best practices (git-workflow, token-optimization)
│   ├── memory/             # Persistent learnings
│   │   ├── analysis.json
│   │   ├── decisions.md
│   │   └── learnings.md
│   ├── postbox/            # Inter-agent communication
│   │   ├── tasks.json
│   │   └── results.json
│   ├── pipeline/           # ACIP pipeline runtime artifacts (ignored by default)
│   │   ├── current/
│   │   └── history/
│   ├── tournament/         # Tournament runtime artifacts (ignored by default)
│   │   ├── current/
│   │   └── history/
│   ├── hooks/              # Event hooks (Claude Code format)
│   │   ├── hooks.json      # Hook definitions
│   │   └── README.md       # Hook documentation
│   ├── docs/               # Detailed documentation
│   │   ├── ARCHITECTURE.md
│   │   └── WORKFLOWS.md
│   └── scripts/
│       ├── worktree.sh
│       ├── pipeline.sh
│       └── pipeline-monitor.sh
└── claude-orchestrate.sh   # Entry point
```

## Agents & Subagents

### Main Agents

| Agent | Model | Role |
|-------|-------|------|
| **Architect** | Opus | Planning, documentation, task decomposition |
| **Tester** | Sonnet | Run tests, analyze failures, improve coverage |
| **Linter** | Sonnet | Code style, formatting, auto-fixes |
| **Implementer** | Sonnet | Write code, fix bugs, refactor |
| **Critic** | Sonnet | Review work, track patterns, improve prompts |

### Subagents (Specialized)

| Subagent | Model | Role |
|----------|-------|------|
| **code-analyzer** | Sonnet | Analyze code structure and dependencies |
| **test-generator** | Sonnet | Generate comprehensive test suites |
| **doc-writer** | Haiku | Create technical documentation |

Subagents run in isolated contexts and are automatically delegated by Claude based on task description.

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
# Pipeline (single by default)
./claude-orchestrate.sh pipeline "description"        # n=1 (default)

# Tournament mode (n=2..4)
./claude-orchestrate.sh pipeline 4 "description"
./claude-orchestrate.sh pipeline-tournament-status
./claude-orchestrate.sh pipeline-select pipeline-1
./claude-orchestrate.sh pipeline-reject

# Single pipeline utilities
./claude-orchestrate.sh pipeline-status
./claude-orchestrate.sh pipeline-resume
./claude-orchestrate.sh pipeline-monitor 2

# Worktrees (parallel)
./.claude/scripts/worktree.sh spawn 3        # Create 3 worktrees
./.claude/scripts/worktree.sh list           # List worktrees
./.claude/scripts/worktree.sh attach <agent> # Attach to latest session for agent
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

### Customize Hooks

Edit `.claude/hooks/hooks.json` to add event-driven automation:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "write|edit",
        "hooks": [
          {
            "type": "command",
            "command": "npm run lint"
          }
        ]
      }
    ]
  }
}
```

See `.claude/hooks/README.md` for details.

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
