# Claude Orchestrator Hooks

This directory contains hooks configuration following the official Claude Code plugin standards.

## Structure

```
hooks/
└── hooks.json    # Hook definitions (Claude Code format)
```

## How Hooks Work

Hooks in Claude Code automatically execute shell commands in response to specific events. They are defined in `hooks.json` using the official Claude Code plugin format.

### Available Hook Types

1. **PreToolUse** - Triggers before any tool is used
2. **PostToolUse** - Triggers after a tool completes
3. **PreCommand** - Triggers before a command executes
4. **PostCommand** - Triggers after a command completes

### Hook Configuration Format

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "regex_pattern",
        "hooks": [
          {
            "type": "command",
            "command": "shell command to execute"
          }
        ]
      }
    ]
  }
}
```

### Matcher Patterns

- `".*"` - Matches all tools/commands
- `"write|edit|search_replace"` - Matches specific tools
- `"architect|implementer"` - Matches specific agents

### Available Variables

In hook commands, you can use:
- `{tool_name}` - Name of the tool being used
- `{command}` - Command being executed

## Current Hooks

### Logging Hooks

All tool usage is logged to `.claude/logs/hooks.log`:

```
2026-01-10T12:34:56+00:00 | PRE_TOOL | Tool: read_file
2026-01-10T12:34:56+00:00 | POST_TOOL | Tool: read_file completed
```

### File Modification Tracking

Special logging for file write/edit operations:

```
2026-01-10T12:35:00+00:00 | FILE_MODIFICATION | Tool: write preparing to modify files
2026-01-10T12:35:01+00:00 | FILE_MODIFIED | Tool: write modified files
```

### Terminal Command Tracking

Logs when terminal commands are about to execute:

```
2026-01-10T12:35:30+00:00 | TERMINAL_CMD | About to execute terminal command
```

### Agent Lifecycle

Tracks agent start and completion:

```
2026-01-10T12:36:00+00:00 | PRE_AGENT | Agent starting
2026-01-10T12:36:45+00:00 | POST_AGENT | Agent completed
```

### Automatic Memory Management

Post-agent hooks automatically evict old memory entries (older than 1 hour).

## Customizing Hooks

To add custom hooks, edit `hooks.json`:

1. Choose the appropriate hook type (PreToolUse, PostToolUse, etc.)
2. Define a matcher pattern for when it should trigger
3. Add command(s) to execute

### Example: Notify on Test Failures

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "run_terminal_cmd.*test",
        "hooks": [
          {
            "type": "command",
            "command": "if [ $? -ne 0 ]; then echo 'Tests failed!' | notify-send; fi"
          }
        ]
      }
    ]
  }
}
```

### Example: Auto-format Before Commits

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "git.*commit",
        "hooks": [
          {
            "type": "command",
            "command": "npm run format"
          }
        ]
      }
    ]
  }
}
```

## Security Considerations

⚠️ **Important**: Hooks execute arbitrary shell commands automatically. Always:

1. Verify commands before adding them
2. Use absolute paths for scripts
3. Avoid commands that require user input
4. Test hooks in a safe environment first
5. Review third-party hooks carefully

## Debugging Hooks

To debug hook execution:

1. Check `.claude/logs/hooks.log` for hook events
2. Test commands manually before adding to hooks
3. Use `echo` commands to verify hook triggering
4. Start with simple matchers (`".*"`) then narrow down

## Migration from Old Format

If you're upgrading from the old shell-script based hooks:

1. ✅ **Old**: `hooks/lifecycle/pre-agent.sh`
2. ✅ **New**: Defined in `hooks.json` with PreCommand matcher

The new format is:
- More maintainable (single JSON file)
- Follows Claude Code standards
- Automatically integrated with Claude Code
- Better error handling and logging

## References

- [Official Claude Code Hooks Documentation](https://docs.claude.com/ru/docs/claude-code/hooks)
- [Claude Code Plugin Guide](https://docs.claude.com/docs/claude-code/plugins)
