# Cross-Platform Command Reference

This document provides Windows PowerShell and macOS alternatives for bash commands used in the sessions protocols.

## Common Command Translations

### JSON Parsing (jq alternatives)

**Bash (Linux/macOS with jq):**
```bash
TASK_NAME=$(jq -r '.task' .claude/state/current_task.json)
```

**PowerShell (Windows):**
```powershell
$TASK_NAME = (Get-Content .claude/state/current_task.json | ConvertFrom-Json).task
```

**macOS (without jq - using Python):**
```bash
TASK_NAME=$(python3 -c "import json; print(json.load(open('.claude/state/current_task.json'))['task'])")
```

### Grep + Awk Pattern

**Bash:**
```bash
PR_NUMBER=$(grep '^pr_number:' "sessions/tasks/done/${TASK_NAME}.md" | awk '{print $2}')
```

**PowerShell:**
```powershell
$PR_NUMBER = (Select-String -Pattern '^pr_number:' "sessions/tasks/done/$TASK_NAME.md").Line.Split()[1]
```

**macOS (native):**
```bash
PR_NUMBER=$(grep '^pr_number:' "sessions/tasks/done/${TASK_NAME}.md" | cut -d' ' -f2)
```

### Conditionals

**Bash:**
```bash
if [[ -d "sessions/tasks/${TASK_NAME}" ]]; then
```

**PowerShell:**
```powershell
if (Test-Path "sessions/tasks/$TASK_NAME" -PathType Container) {
```

**macOS (native):**
```bash
if [ -d "sessions/tasks/${TASK_NAME}" ]; then
```

### Text Replacement (sed alternatives)

**Bash:**
```bash
sed -i "s/^merged:.*/merged: $(date +%Y-%m-%d)/" "sessions/tasks/${TASK_NAME}.md"
```

**PowerShell:**
```powershell
(Get-Content "sessions/tasks/$TASK_NAME.md") -replace '^merged:.*', "merged: $(Get-Date -Format yyyy-MM-dd)" | Set-Content "sessions/tasks/$TASK_NAME.md"
```

**macOS (BSD sed):**
```bash
sed -i '' "s/^merged:.*/merged: $(date +%Y-%m-%d)/" "sessions/tasks/${TASK_NAME}.md"
```

### Check Git Remote

**Bash:**
```bash
if git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
```

**PowerShell:**
```powershell
if (git remote | Where-Object { $_ -eq $UPSTREAM_REMOTE }) {
```

**macOS (native):**
```bash
if git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
```

### Date Format

**Bash:**
```bash
$(date +%Y-%m-%d)
```

**PowerShell:**
```powershell
$(Get-Date -Format yyyy-MM-dd)
```

**macOS (native):**
```bash
$(date +%Y-%m-%d)
```

## Git Commands (Cross-Platform)

Git commands work identically across all platforms:
- `git status`
- `git branch`
- `git checkout`
- `git pull`
- `git push`

## GitHub/GitLab CLI (Cross-Platform)

Both `gh` (GitHub CLI) and `glab` (GitLab CLI) work identically across all platforms:
- `gh pr create`
- `gh pr view`
- `glab mr create`
- `glab mr view`

## Notes

- **macOS**: Most bash commands work natively on macOS. The main difference is BSD vs GNU tools (e.g., `sed -i ''` vs `sed -i`)
- **Windows**: PowerShell provides native cmdlets for most operations. Alternatively, Git Bash or WSL can run bash scripts directly
- **Python fallback**: For complex operations, Python3 is available on all platforms and provides consistent behavior

## Recommended Approach

1. **Windows users**: Use PowerShell natively or Git Bash for full bash compatibility
2. **macOS users**: Most bash scripts work with minor adjustments (BSD tools)
3. **Cross-platform scripts**: Use Python for complex logic, native commands for simple operations
