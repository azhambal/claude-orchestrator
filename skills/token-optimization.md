# Token Optimization Skill

## When to Apply
Apply these practices automatically in all operations.

## Rules

### Context Management
1. **Clear between tasks**: `/clear` after completing unrelated tasks
2. **Compact at 50%**: Run `/compact` when context exceeds 50K tokens
3. **Lazy load docs**: Only read docs/* files when needed

### Prompting
1. **Be specific**: Include exact file paths, line numbers
2. **One task per prompt**: Don't combine unrelated requests
3. **No repetition**: Don't re-explain context already in CLAUDE.md

### Reading Files
1. **Targeted reads**: Read specific functions, not whole files
2. **Use grep first**: Find what you need before reading
3. **Don't read node_modules, .git, build artifacts**

### Writing Output
1. **Summarize, don't paste**: "Fixed 5 issues" not full diff
2. **Structured results**: JSON in postbox, not prose
3. **No unnecessary confirmation**: Just do it

### Model Selection
| Task | Model | Why |
|------|-------|-----|
| Planning, architecture | opus | Deep thinking |
| Implementation | sonnet | Good balance |
| Quick checks | haiku | Fast, cheap |

### MCP Optimization
- Disable unused servers: `/mcp` → disable
- Check context usage: `/context`
- Consolidate similar tools

## Quick Checks

Before any operation, ask:
1. Is this file read necessary?
2. Can I use grep instead?
3. Is the output minimal?
4. Did I already know this?

## Anti-Patterns

❌ Reading entire codebase
❌ Pasting full files in context  
❌ Asking for confirmation after every step
❌ Verbose explanations when not requested
❌ Running all tools "just in case"
