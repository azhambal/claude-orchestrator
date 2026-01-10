# Git Workflow Skill

## Commit Messages

Use conventional commits:

```
<type>(<scope>): <description>

[optional body]
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code change (no new feature, no bug fix)
- `test`: Adding/updating tests
- `docs`: Documentation only
- `style`: Formatting, no code change
- `chore`: Maintenance tasks

### Examples
```
feat(auth): add JWT token refresh
fix(api): handle null response in user endpoint
test(auth): add integration tests for login flow
refactor(db): extract query builder to separate module
```

## Branch Naming

```
<type>/<description>

claude/feature-name      # Agent-created branches
feature/user-auth        # Human feature branches
fix/login-bug           # Bug fixes
```

## Workflow

### Before Starting Work
```bash
git fetch origin
git checkout main
git pull
git checkout -b <branch-name>
```

### During Work
```bash
# Stage specific files
git add path/to/file.py

# Commit often with clear messages
git commit -m "feat(scope): description"

# Push to remote
git push -u origin <branch-name>
```

### After Work
```bash
# Ensure tests pass
npm test  # or pytest, etc.

# Ensure lint passes
npm run lint

# Create PR or merge
```

## For Agents

### Auto-commit Pattern
```bash
# After making changes
git add -A
git commit -m "<type>(<agent>): <what was done>"
```

### Conflict Resolution
1. Don't auto-resolve conflicts
2. Report to architect
3. Let human decide

### Branch Per Agent
Each agent in worktree works on its own branch:
```
claude/tester-1234567890
claude/linter-1234567891
claude/implementer-1234567892
```
