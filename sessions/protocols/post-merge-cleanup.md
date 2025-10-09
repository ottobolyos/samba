# Post-Merge Cleanup Protocol

This protocol is executed after a PR/MR has been successfully merged.

## Prerequisites
- PR/MR has been merged to upstream/origin main branch
- Task has been marked as completed
- Current working directory is the project root

## Configuration
```bash
# Default upstream remote (can be overridden in task frontmatter)
UPSTREAM_REMOTE=${UPSTREAM_REMOTE:-upstream}
MAIN_BRANCH=${MAIN_BRANCH:-main}
```

## 1. Verify PR/MR Merge Status

```bash
# Read task information
TASK_NAME=$(jq -r '.task' .claude/state/current_task.json)
PR_NUMBER=$(grep '^pr_number:' "sessions/tasks/done/${TASK_NAME}.md" | awk '{print $2}')

# GitHub verification
if command -v gh &> /dev/null; then
	PR_STATUS=$(gh pr view "$PR_NUMBER" --json state -q .state 2> /dev/null || echo 'UNKNOWN')
	if [[ "$PR_STATUS" != 'MERGED' ]]; then
		echo "Warning: PR #$PR_NUMBER is not merged (status: $PR_STATUS)"
		echo 'Proceed with cleanup? (y/n)'
		read -r response
		[[ "$response" != 'y' ]] && exit 1
	fi
fi

# GitLab verification
if command -v glab &> /dev/null; then
	MR_STATUS=$(glab mr view "$PR_NUMBER" --output json | jq -r .state 2> /dev/null || echo 'UNKNOWN')
	if [[ "$MR_STATUS" != 'merged' ]]; then
		echo "Warning: MR !$PR_NUMBER is not merged (status: $MR_STATUS)"
		echo 'Proceed with cleanup? (y/n)'
		read -r response
		[[ "$response" != 'y' ]] && exit 1
	fi
fi
```

## 2. Update Local Main Branch

```bash
# Save current branch name
FEATURE_BRANCH=$(git branch --show-current)

# Switch to main branch
git checkout "$MAIN_BRANCH"

# Pull latest changes from upstream
if git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
	echo "Pulling from $UPSTREAM_REMOTE/$MAIN_BRANCH..."
	git pull "$UPSTREAM_REMOTE" "$MAIN_BRANCH"
else
	echo "Pulling from origin/$MAIN_BRANCH..."
	git pull origin "$MAIN_BRANCH"
fi
```

## 3. Push Main to Origin

```bash
# Push updated main to origin (if using upstream)
if git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
	echo 'Pushing updated main to origin...'
	git push origin "$MAIN_BRANCH"
fi
```

## 4. Delete Feature Branch

```bash
# Delete local feature branch
echo "Deleting local branch: $FEATURE_BRANCH"
git branch -D "$FEATURE_BRANCH"

# Delete remote feature branch (from origin)
echo "Deleting remote branch: origin/$FEATURE_BRANCH"
git push origin --delete "$FEATURE_BRANCH" 2> /dev/null || echo 'Remote branch already deleted or does not exist'
```

## 5. Clean Up Sub-Task Branches (if applicable)

```bash
# If sub-tasks directory exists in done/
if [[ -d "sessions/tasks/done/${TASK_NAME}" ]]; then
	echo 'Cleaning up sub-task branches...'
	for subtask in "sessions/tasks/done/${TASK_NAME}"/*.md; do
		if [[ -f "$subtask" ]]; then
			subtask_branch=$(grep '^branch:' "$subtask" | awk '{print $2}')
			if [[ -n "$subtask_branch" ]]; then
				echo "Deleting sub-task branch: $subtask_branch"
				git branch -D "$subtask_branch" 2> /dev/null || echo "Branch $subtask_branch not found locally"
				git push origin --delete "$subtask_branch" 2> /dev/null || echo "Remote branch $subtask_branch not found"
			fi
		fi
	done
fi
```

## 6. Archive Task Documentation

```bash
# Task files are already in sessions/tasks/done/
# Update the merged date if not already done
if ! grep -q "^merged: [0-9]" "sessions/tasks/done/${TASK_NAME}.md"; then
	sed -i "s/^merged:.*/merged: $(date +%Y-%m-%d)/" "sessions/tasks/done/${TASK_NAME}.md"
fi

echo "Task $TASK_NAME has been archived in sessions/tasks/done/"
```

## 7. Clear Task State

```bash
# Reset current task state
cat > .claude/state/current_task.json << EEOF
{
  "task": null,
  "branch": null,
  "services": [],
  "updated": "$(date +%Y-%m-%d)"
}
EEOF

echo 'Task state cleared'
```

## 8. Final Status Report

```bash
echo '========================================='
echo 'Post-merge cleanup completed successfully!'
echo '========================================='
echo "✓ Main branch updated from $UPSTREAM_REMOTE"
echo '✓ Main branch pushed to origin'
echo "✓ Feature branch $FEATURE_BRANCH deleted (local and remote)"
echo "✓ Task $TASK_NAME archived"
echo '✓ Task state cleared'
echo ''
echo 'Ready for next task!'
```

## Branch Tracking Configuration (One-time setup)

For projects using separate upstream and origin remotes:

```bash
# Configure main branch to track upstream for fetch, origin for push
git branch --set-upstream-to="${UPSTREAM_REMOTE}/${MAIN_BRANCH}" "${MAIN_BRANCH}"
git config "branch.${MAIN_BRANCH}.pushRemote" origin

echo "Branch tracking configured:"
echo "  Fetch from: ${UPSTREAM_REMOTE}/${MAIN_BRANCH}"
echo "  Push to: origin/${MAIN_BRANCH}"
```

## Error Handling

Exit codes:
- `0`: Success
- `1`: General error or user cancellation
- `2`: PR/MR not merged
- `3`: Git operation failed
- `4`: Required tools not found

## Notes

- This protocol assumes GitHub (gh) or GitLab (glab) CLI tools are installed
- The upstream remote defaults to 'upstream' but can be configured
- Sub-task branches are cleaned up automatically if they exist
- Always verifies merge status before proceeding with cleanup
- Maintains separation between upstream (fetch) and origin (push) when configured
