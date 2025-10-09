# Task Completion Protocol

When a task meets its success criteria:

## 1. Pre-Completion Checks

Verify before proceeding:
- [ ] All success criteria checked off in task file
- [ ] No unaddressed work remaining
- [ ] All sub-tasks completed (if applicable)


### Check for Sub-Tasks
```bash
# Check if task has sub-tasks directory
TASK_NAME=$(jq -r .task .claude/state/current_task.json)
if [[ -d "sessions/tasks/${TASK_NAME}" ]]; then
	echo "Found sub-tasks directory. Checking completion status..."
	# Verify all sub-tasks are marked as completed
	for subtask in sessions/tasks/${TASK_NAME}/*.md; do
		if [[ -f "$subtask" ]]; then
			status=$(grep "^status:" "$subtask" | awk '{print $2}')
			if [[ "$status" != "completed" ]]; then
				echo "Error: Sub-task $(basename "$subtask") is not completed (status: $status)"
				echo "All sub-tasks must be completed before task completion"
				exit 1
			fi
		fi
	done
	echo "All sub-tasks are completed"
fi
```

**NOTE**: Do NOT commit yet - agents will modify files

## 2. Run Completion Agents

Delegate to specialized agents in this order:
```markdown
1. code-review agent - Review all implemented code for security/quality
   Include: Changed files, task context, implementation approach

2. service-documentation agent - Update CLAUDE.md files
   Include: List of services modified during task

3. logging agent - Finalize task documentation
   Include: Task completion summary, final status
```

## 3. Task Archival

After agents complete:
```bash
# Update task file status to 'completed'
# Move to done/ directory
# Update task file status to 'completed'
# Update merged date in frontmatter if applicable
TASK_NAME=$(jq -r '.task' .claude/state/current_task.json)
sed -i 's/^status:.*/status: completed/' "sessions/tasks/${TASK_NAME}.md"
if grep -q '^merged:' "sessions/tasks/${TASK_NAME}.md"; then
	sed -i "s/^merged:.*/merged: $(date +%Y-%m-%d)/" "sessions/tasks/${TASK_NAME}.md"
fi

# Move to done/ directory
mv "sessions/tasks/${TASK_NAME}.md" sessions/tasks/done/

# If sub-tasks directory exists, move it too:
if [[ -d "sessions/tasks/${TASK_NAME}" ]]; then
	mv "sessions/tasks/${TASK_NAME}/" sessions/tasks/done/
fi
```

## 4. Clear Task State

```bash
# Clear task state (but keep file)
cat > .claude/state/current_task.json << 'EOF'
{
  "task": null,
  "branch": null,
  "services": [],
  "updated": "$(date +%Y-%m-%d)"
}
EOF
```

## 5. Git Operations (Commit & Push/PR)

### Configuration Variables
```bash
# Read task frontmatter for issue tracking
TASK_NAME=$(jq -r .task .claude/state/current_task.json)
ISSUE_NUMBER=$(grep "^issue_number:" "sessions/tasks/${TASK_NAME}.md" | awk '{print $2}')
PR_NUMBER=$(grep "^pr_number:" "sessions/tasks/${TASK_NAME}.md" | awk '{print $2}')
DRAFT_MR=$(grep "^draft_mr:" "sessions/tasks/${TASK_NAME}.md" | awk '{print $2}')
```

### Step 1: Review Unstaged Changes

```bash
# Check for any unstaged changes
git status -s


# If changes exist, commit all changes (`git add -A`)
```

### Step 2: Handle Sub-Task Commits (if applicable)

```bash
# If sub-tasks exist, create individual commits for each
if [[ -d "sessions/tasks/${TASK_NAME}" ]]; then
	echo "Creating individual commits for sub-tasks..."
	for subtask in sessions/tasks/${TASK_NAME}/*.md; do
		if [[ -f "$subtask" ]]; then
			subtask_name=$(basename "$subtask" .md)
			# Stage related changes (you need to identify which files relate to each sub-task)
			echo "Creating commit for sub-task: $subtask_name"

			# Construct commit message
			COMMIT_MSG="feat($subtask_name): [description]"
			if [[ -n "$ISSUE_NUMBER" ]] && [[ "$ISSUE_NUMBER" != "null" ]]; then
				COMMIT_MSG="$COMMIT_MSG\n\nPart of #$ISSUE_NUMBER"
			fi

			# Note: User must manually stage and commit files for each sub-task
			echo "Please stage and commit files for sub-task: $subtask_name"
		fi
	done
fi
```

### Step 3: Determine Branch Type

1. Check the current branch name
2. Determine if this is a subtask or regular task:
   - **Subtask**: Branch name has pattern like `tt\d+[a-z]` (e.g., tt1a, tt234b)
   - **Regular task**: Branch name like `feature/*`, `fix/*`, or `tt\d+` (no letter)

### Step 4: Check for Super-repo Structure

```bash
# Check if we're in a super-repo with submodules
if [ -f .gitmodules ]; then
  echo "Super-repo detected with submodules"
  # Follow submodule commit ordering below
else
  echo "Standard repository"
  # Skip to step 4
fi
```

### Step 5: Commit and Create PR/MR

**IF SUPER-REPO**: Process from deepest submodules to super-repo

All commit messages should follow Commitlint format and semantic versioning (follow the Commitlint configuration if it exists in the codebase).

#### A. Deepest Submodules First (Depth 2+)
For any submodules within submodules:
1. Navigate to each modified deep submodule
2. Stage changes based on user preference from Step 1
3. Commit all changes with descriptive message (NO Claude attribution)
4. Merge based on branch type:
   - Subtask → merge into parent task branch
   - Regular task → merge into samba-ad
5. Push the merged branch

#### B. Direct Submodules (Depth 1)
For all modified direct submodules:
1. Navigate to each modified submodule
2. Stage changes based on user preference
3. Commit all changes with descriptive message (NO Claude attribution)
4. Merge based on branch type:
   - Subtask → merge into parent task branch
   - Regular task → merge into samba-ad
5. Push the merged branch

#### C. Super-repo (Root)
After ALL submodules are committed and merged:
1. Return to super-repo root
2. Stage changes based on user preference
3. Commit all changes with descriptive message (NO Claude attribution)
4. Merge based on branch type:
   - Subtask → merge into parent task branch
   - Regular task → merge into samba-ad
5. Push the merged branch

**IF STANDARD REPO**: Simple commit and merge
1. Stage changes based on user preference
2. Commit with descriptive message (NO Claude attribution)
3. Merge based on branch type (subtask → parent, regular → samba-ad)
4. Push the merged branch

### Special Cases

**Experiment branches:**
- Ask user whether to keep the experimental branch for reference
- If keeping: Just push branches without merging
- If not: Document findings first, then delete branches

**Research tasks (no branch):**
- No merging needed
- Just ensure findings are documented in task file

### Step 6: Create Pull Request or Merge Request

```bash
# Only after ALL sub-tasks are committed (if applicable)

# GitHub PR Creation
if [[ "$PLATFORM" == "github" ]]; then
	gh pr create \
		--title "[Task] $TASK_NAME" \
		--body "Fixes #$ISSUE_NUMBER" \
		--assignee @me
	# Note: Labels should be added manually by user

	# Store PR number in task frontmatter
	PR_URL=$(gh pr view --json url -q .url)
	PR_NUM=$(echo "$PR_URL" | grep -oE "[0-9]+$")
	sed -i "s/^pr_number:.*/pr_number: $PR_NUM/" "sessions/tasks/done/${TASK_NAME}.md"
fi

# GitLab MR Creation
if [[ "$PLATFORM" == "gitlab" ]]; then
	# Get current GitLab username (try API first, fall back to parsing auth status)
	GITLAB_USER=$(glab api user 2> /dev/null | jq -r .username 2> /dev/null || \
		glab auth status 2> /dev/null | grep -oP "Logged in to [^ ]+ as \K[^ ]+(?= )" | head -1 || \
		echo "")

	MR_FLAGS=""
	if [[ -n "$GITLAB_USER" ]]; then
		MR_FLAGS="--assignee $GITLAB_USER"
	fi
	if [[ "$DRAFT_MR" == "true" ]]; then
		MR_FLAGS="$MR_FLAGS --draft"
	fi

	glab mr create \
		--title "[Task] $TASK_NAME" \
		--description "Part of #$ISSUE_NUMBER" \
		$MR_FLAGS
	# Note: Labels should be added manually by user

	# Store MR number in task frontmatter
	MR_URL=$(glab mr view --web)
	MR_NUM=$(echo "$MR_URL" | grep -oE "[0-9]+$")
	sed -i "s/^pr_number:.*/pr_number: $MR_NUM/" "sessions/tasks/done/${TASK_NAME}.md"
fi
```

## 7. Select Next Task

Immediately after archival:
```bash
# List all tasks (simple and reliable)
ls -lA sessions/tasks/

# Present the list to user
echo "Task complete! Here are the remaining tasks:"
# User can see which are .md files vs directories vs symlinks
```

User selects next task:
- Switch to task branch: `git checkout [branch-name]`
- Update task state: Edit `.claude/state/current_task.json` with new task, branch, and services
- Follow task-startup.md protocol

If no tasks remain:
- Celebrate completion!
- Ask user what they want to tackle next
- Create new task following task-creation.md

## Important Notes

- NEVER skip the agent steps - they maintain system integrity
- Task files in done/ serve as historical record
- Completed experiments should document learnings even if code is discarded
- If task is abandoned incomplete, document why in task file before archiving
