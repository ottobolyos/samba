#!/usr/bin/env python3
"""
Claude Code StatusLine Script - Cross-platform Python version
Provides comprehensive session information in a clean format.
Works on Windows, macOS, and Linux without shell dependencies.
"""
import sys
import json
import os
import re
from pathlib import Path
import subprocess
from typing import Tuple, Dict, Any

# ANSI color codes
COLORS = {
    'RESET': '\033[0m',
    'PROGRESS_GREEN': '\033[38;5;114m',  # AAD94C green
    'PROGRESS_ORANGE': '\033[38;5;215m',  # FFB454 orange
    'PROGRESS_RED': '\033[38;5;203m',  # F26D78 red
    'GRAY': '\033[38;5;242m',  # Dim gray
    'TEXT': '\033[38;5;250m',  # BFBDB6 light gray
    'CYAN': '\033[38;5;111m',  # 59C2FF entity blue
    'DAIC_PURPLE': '\033[38;5;183m',  # D2A6FF constant purple
    'DAIC_GREEN': '\033[38;5;114m',  # AAD94C string green
    'YELLOW': '\033[38;5;215m',  # FFB454 func orange
    'GREEN': '\033[38;5;114m',  # AAD94C green
    'RED': '\033[38;5;203m',  # F26D78 red
}

# Unicode characters with fallbacks for Windows/legacy terminals
UNICODE_CHARS = {
    'filled': ('█', '#'),
    'empty': ('░', '-'),
    'pencil': ('✎', '*'),
}

# Token limit constants
CONTEXT_LIMIT = 160000  # 160k usable for 200k standard context window
DEFAULT_TOKENS = 17900
AVG_TOKENS_PER_MSG = 3600
CHARS_PER_TOKEN = 3.5

# Compiled regex for efficient status matching
STATUS_DONE_PATTERN = re.compile(r'status:\s*(done|completed)', re.IGNORECASE)

def get_unicode_char(char_type: str) -> str:
    """Get Unicode character with fallback for legacy terminals."""
    try:
        # Try to encode Unicode character
        char = UNICODE_CHARS[char_type][0]
        char.encode(sys.stdout.encoding or 'utf-8')
        return char
    except (UnicodeEncodeError, AttributeError, LookupError):
        # Fallback to ASCII if Unicode not supported
        return UNICODE_CHARS[char_type][1]

def find_project_root() -> Path:
    """Find project root by looking for .claude directory."""
    current = Path.cwd()
    while current.parent != current:
        if (current / ".claude").exists():
            return current
        current = current.parent
    return Path.cwd()

def calculate_context(input_data: Dict[str, Any], project_root: Path) -> Tuple[str, int, int, int]:
    """Calculate context breakdown and progress."""
    transcript_path = input_data.get('transcript_path', '')

    # Use global constant for context limit
    context_limit = CONTEXT_LIMIT

    total_tokens = 0
    last_tokens = 0
    pending_tokens = 0

    # Find the most recent transcript file (in case provided path is stale)
    if transcript_path and os.path.exists(transcript_path):
        transcript_dir = os.path.dirname(transcript_path)
        try:
            # Get all .jsonl files in the transcript directory
            jsonl_files = [f for f in os.listdir(transcript_dir) if f.endswith('.jsonl')]
            if jsonl_files:
                # Sort by modification time, get most recent
                latest_file = max(
                    [os.path.join(transcript_dir, f) for f in jsonl_files],
                    key=os.path.getmtime
                )
                transcript_path = latest_file
        except:
            pass  # Use provided path as fallback

    # Use last assistant message from transcript - most accurate method
    if transcript_path and os.path.exists(transcript_path):
        try:
            with open(transcript_path, 'r') as f:
                lines = f.readlines()

            # Get assistant messages with usage and calculate token growth rate
            assistant_usages = []
            last_assistant_idx = -1

            for i, line in enumerate(lines):
                try:
                    data = json.loads(line.strip())
                    # Skip sidechain entries (subagent calls)
                    if data.get('isSidechain', False):
                        continue

                    # Look for assistant messages with usage data
                    if data.get('message', {}).get('role') == 'assistant':
                        usage = data.get('message', {}).get('usage')
                        if usage:
                            tokens = (
                                usage.get('input_tokens', 0) +
                                usage.get('cache_creation_input_tokens', 0) +
                                usage.get('cache_read_input_tokens', 0)
                            )
                            assistant_usages.append((i, tokens))
                            last_assistant_idx = i
                except:
                    continue

            # Calculate from last assistant message
            if assistant_usages:
                last_tokens = assistant_usages[-1][1]
                total_tokens = last_tokens

                # Estimate tokens per message from recent growth pattern
                if len(assistant_usages) >= 2:
                    # Calculate average token growth per message from last 3 assistant messages
                    recent = assistant_usages[-3:] if len(assistant_usages) >= 3 else assistant_usages
                    token_diffs = []
                    for i in range(1, len(recent)):
                        idx_diff = recent[i][0] - recent[i-1][0]
                        token_diff = recent[i][1] - recent[i-1][1]
                        if idx_diff > 0:
                            tokens_per_msg = token_diff / idx_diff
                            token_diffs.append(tokens_per_msg)

                    # Use average growth rate, or use constant if calculation fails
                    avg_tokens_per_msg = sum(token_diffs) / len(token_diffs) if token_diffs else AVG_TOKENS_PER_MSG
                else:
                    # Fallback: conservative estimate
                    avg_tokens_per_msg = AVG_TOKENS_PER_MSG

                # Add tokens for messages after last assistant response
                # Use actual content length to estimate tokens
                if last_assistant_idx >= 0:
                    for i in range(last_assistant_idx + 1, len(lines)):
                        try:
                            data = json.loads(lines[i].strip())
                            if data.get('isSidechain', False):
                                continue
                            content = data.get('message', {}).get('content', '')
                            # Estimate tokens from content length using constant
                            content_len = len(str(content))
                            pending_tokens += int(content_len / CHARS_PER_TOKEN)
                        except:
                            pass

                    total_tokens += pending_tokens
        except:
            pass

    # Default values when no transcript available
    if total_tokens == 0:
        total_tokens = DEFAULT_TOKENS
        last_tokens = DEFAULT_TOKENS

    # Calculate percentage
    progress_pct = min(100.0, (total_tokens * 100.0) / context_limit)
    progress_pct_int = int(progress_pct)

    # Format token counts
    formatted_tokens = f"{total_tokens // 1000}k"
    formatted_limit = f"{context_limit // 1000}k"

    # Create progress bar with Unicode fallback support
    filled_blocks = min(10, progress_pct_int // 10)
    empty_blocks = 10 - filled_blocks

    # Color codes based on usage
    if progress_pct_int < 50:
        bar_color = COLORS['PROGRESS_GREEN']
    elif progress_pct_int < 80:
        bar_color = COLORS['PROGRESS_ORANGE']
    else:
        bar_color = COLORS['PROGRESS_RED']

    # Get Unicode characters with fallbacks
    filled_char = get_unicode_char('filled')
    empty_char = get_unicode_char('empty')

    progress_bar = bar_color
    progress_bar += filled_char * filled_blocks
    progress_bar += COLORS['GRAY']
    progress_bar += empty_char * empty_blocks
    progress_bar += f"{COLORS['RESET']} {COLORS['TEXT']}{progress_pct:.1f}% ({formatted_tokens}/{formatted_limit}){COLORS['RESET']}"

    return progress_bar, total_tokens, last_tokens, pending_tokens

def get_current_task(project_root: Path) -> str:
    """Get current task with color."""
    task_file = project_root / ".claude" / "state" / "current_task.json"
    if task_file.exists():
        try:
            with open(task_file, 'r') as f:
                data = json.load(f)
                task_name = data.get('task', 'None')
                return f"{COLORS['CYAN']}Task: {task_name}{COLORS['RESET']}"
        except:
            pass

    return f"{COLORS['CYAN']}Task: None{COLORS['RESET']}"

def get_daic_mode(project_root: Path) -> str:
    """Get DAIC mode with color."""
    daic_file = project_root / ".claude" / "state" / "daic-mode.json"

    mode = "discussion"  # Default
    if daic_file.exists():
        try:
            with open(daic_file, 'r') as f:
                data = json.load(f)
                mode = data.get('mode', 'discussion')
        except:
            pass

    if mode == "discussion":
        return f"{COLORS['DAIC_PURPLE']}DAIC: Discussion{COLORS['RESET']}"
    else:
        return f"{COLORS['DAIC_GREEN']}DAIC: Implementation{COLORS['RESET']}"

def count_edited_files(project_root: Path) -> str:
    """Count edited files with color."""
    pencil = get_unicode_char('pencil')

    if (project_root / ".git").exists():
        try:
            # Run git status in the project directory
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=project_root,
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                # Count lines that start with A, M, AM, or .A, .M
                lines = result.stdout.strip().split('\n') if result.stdout.strip() else []
                modified_count = sum(1 for line in lines if line and (
                    line[0] in 'AM' or (len(line) > 1 and line[1] in 'AM')
                ))
                return f"{COLORS['YELLOW']}{pencil} {modified_count} files{COLORS['RESET']}"
        except:
            pass

    return f"{COLORS['YELLOW']}{pencil} 0 files{COLORS['RESET']}"

def get_git_info(project_root: Path) -> str:
    """Get git branch and status indicators."""
    if not (project_root / ".git").exists():
        return ""

    try:
        # Get branch name or commit hash
        branch_result = subprocess.run(
            ["git", "symbolic-ref", "--short", "HEAD"],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=5
        )

        if branch_result.returncode == 0:
            branch_name = branch_result.stdout.strip()
            branch_display = f"[{branch_name}]"
        else:
            # Detached HEAD - get commit hash
            hash_result = subprocess.run(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=project_root,
                capture_output=True,
                text=True,
                timeout=5
            )
            if hash_result.returncode == 0:
                commit_hash = hash_result.stdout.strip()
                branch_display = f"({commit_hash})"
            else:
                branch_display = "[unknown]"

        # Get status indicators
        indicators = []

        # Check for modified/untracked files
        status_result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=5
        )

        if status_result.returncode == 0:
            lines = status_result.stdout.strip().split('\n') if status_result.stdout.strip() else []
            has_modified = any(line and line[0] in 'AM' or (len(line) > 1 and line[1] in 'AM') for line in lines)
            has_untracked = any(line and line.startswith('??') for line in lines)

            if has_modified:
                indicators.append(f"{COLORS['YELLOW']}*{COLORS['RESET']}")
            if has_untracked:
                indicators.append(f"{COLORS['TEXT']}?{COLORS['RESET']}")

        # Check ahead/behind status
        upstream_result = subprocess.run(
            ["git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=5
        )

        if upstream_result.returncode == 0:
            counts = upstream_result.stdout.strip().split()
            if len(counts) == 2:
                behind = int(counts[0])
                ahead = int(counts[1])

                if ahead > 0 and behind > 0:
                    indicators.append(f"{COLORS['GREEN']}↑{ahead}{COLORS['RESET']}{COLORS['RED']}↓{behind}{COLORS['RESET']}")
                elif ahead > 0:
                    indicators.append(f"{COLORS['GREEN']}↑{ahead}{COLORS['RESET']}")
                elif behind > 0:
                    indicators.append(f"{COLORS['RED']}↓{behind}{COLORS['RESET']}")

        indicator_str = "".join(indicators) if indicators else ""
        return f"{COLORS['CYAN']}{branch_display}{COLORS['RESET']}{indicator_str}"

    except:
        return ""

def count_open_tasks(project_root: Path) -> str:
    """Count open tasks with color."""
    tasks_dir = project_root / "sessions" / "tasks"
    if tasks_dir.exists():
        open_count = 0
        for task_file in tasks_dir.glob("*.md"):
            if task_file.is_file():
                try:
                    with open(task_file, 'r') as f:
                        content = f.read()
                        # Check if status is not done or completed using compiled regex
                        if not STATUS_DONE_PATTERN.search(content):
                            open_count += 1
                except:
                    pass

        return f"{COLORS['CYAN']}[{open_count} open]{COLORS['RESET']}"

    return f"{COLORS['CYAN']}[0 open]{COLORS['RESET']}"

def main() -> None:
    """Main entry point."""
    # Read JSON input from stdin
    try:
        input_data = json.load(sys.stdin)
    except:
        # If JSON parsing fails, create minimal data
        input_data = {}

    # Get workspace directory
    cwd = input_data.get('workspace', {}).get('current_dir') or input_data.get('cwd', '')

    # Find project root
    if cwd:
        project_root = Path(cwd)
    else:
        project_root = find_project_root()

    # Calculate all components
    progress_info, total_tokens, last_tokens, pending_tokens = calculate_context(input_data, project_root)
    task_info = get_current_task(project_root)
    daic_info = get_daic_mode(project_root)
    files_info = count_edited_files(project_root)
    tasks_info = count_open_tasks(project_root)
    git_info = get_git_info(project_root)

    # Get model name with version and color
    model_name = input_data.get('model', {}).get('display_name', 'Claude')
    version = input_data.get('version', '')

    # Different colors for each part: model name | @ | version
    if version:
        model_info = f"{COLORS['CYAN']}{model_name}{COLORS['RESET']} {COLORS['GRAY']}@{COLORS['RESET']} {COLORS['GREEN']}{version}{COLORS['RESET']}"
    else:
        model_info = f"{COLORS['CYAN']}{model_name}{COLORS['RESET']}"

    # Get current working directory with color (same as percentage text)
    cwd = input_data.get('workspace', {}).get('current_dir') or input_data.get('cwd', '')
    if cwd:
        # Shorten very long paths
        cwd_display = cwd
        if len(cwd_display) > 60:
            parts = cwd_display.split('/')
            cwd_display = '.../' + '/'.join(parts[-3:])
    else:
        cwd_display = str(project_root)

    cwd_info = f"{COLORS['TEXT']}{cwd_display}{COLORS['RESET']}"

    # Build line 2
    line2_parts = [daic_info, files_info, tasks_info]
    line2 = " | ".join(line2_parts)

    # Output the statusline in three lines with color support
    # Line 1: Progress bar | Model | Current task
    # Line 2: DAIC mode | Files edited | Open tasks
    # Line 3: Git info | Working directory
    print(f"{progress_info} | {model_info} | {task_info}")
    print(line2)
    print(f"{git_info} | {cwd_info}")

if __name__ == "__main__":
    main()
