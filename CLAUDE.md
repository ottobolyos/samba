# ServerContainers/Samba CLAUDE.md

## Repository Purpose

Docker container for Samba server with support for Active Directory, Avahi (zeroconf), and WSDD2 (Windows network discovery). Provides multi-architecture builds for x86_64, arm64, and arm platforms on both Alpine and Ubuntu base images.

## Key Files

### Build Scripts
- `build_ubuntu.sh:1-209` - Ubuntu image builder with multi-variant support
  - Supports help via `-h` or `--help` flags (lines 59-65)
  - Help function at lines 20-55
  - Builds 5 image variants: ad, avahi, full, only, wsdd2
  - Multi-platform builds: linux/amd64, linux/arm/v7, linux/arm/v8, linux/arm64
- `build.sh` - Alpine image builder
- `generate-variants.sh` - Generates variant configurations
- `get-version.sh` - Retrieves version information

### Runtime Scripts
- `scripts/entrypoint_ubuntu.sh` - Ubuntu container entrypoint
  - User/group creation (lines 118-176)
  - Active Directory configuration (lines 183-255)
  - AD DNS registration with host override support (lines 236-252)
  - Avahi/zeroconf setup (lines 258-312)
  - Service management and optional service disabling (lines 392-404)
  - Samba volume configuration (lines 315-405)

### Docker Configuration
- `ubuntu.dockerfile` - Ubuntu-based Dockerfile
- `Dockerfile` - Alpine-based Dockerfile
- `docker-compose.yml:28-31` - Example composition with HOST_IP/HOST_HOSTNAME example

### Configuration
- `config/` - Runtime configuration templates
- `smb.conf` - Samba configuration template

### Documentation
- `README.md:241-256` - Environment variables including HOST_IP, HOST_HOSTNAME, and WINBIND_DISABLE
- `TROUBLESHOOTING.md` - Common issues and solutions
- `CHANGELOGS.md` - Historical changes

## Build Workflow

Reference: `build_ubuntu.sh:69-209`

1. Detect Samba and Ubuntu versions from base image
2. Create version tag: `u<ubuntu-version>-s<samba-version>`
3. Setup buildx with QEMU for multi-arch
4. Build selected variants with appropriate feature flags
5. Push to registry (unless `no-push` specified)
6. Cleanup dangling images and builder instance

## Image Variants

Configuration arrays: `build_ubuntu.sh:149-158`

- `ad` - Active Directory support only
- `avahi` - Zeroconf/Bonjour support only
- `full` - All features enabled (default)
- `only` - Minimal smbd-only build
- `wsdd2` - Windows Service Discovery only

## Build Script Options

Reference: `build_ubuntu.sh:29-40`

- `force` - Build regardless of commit age
- `no-push` - Local build without registry push
- `plain-log` - Plain format build progress
- `use-cache` - Enable Docker build cache

## Required Environment

- `DOCKER_REGISTRY` - Registry and organization (e.g., 'ghcr.io/servercontainers')

## Active Directory Features

### DNS Registration

Reference: `scripts/entrypoint_ubuntu.sh:236-252`

The container supports two modes for Active Directory DNS registration:

**Container DNS Registration (default):**
- Registers container's own hostname and IP in AD DNS
- Used when HOST_IP and HOST_HOSTNAME are not set
- Command: `net ads dns register`

**Host DNS Registration (optional):**
- Registers Docker host's hostname and IP in AD DNS instead
- Enabled by setting both HOST_IP and HOST_HOSTNAME environment variables
- Useful for NAS devices running Samba in containers
- Command: `net ads dns register "$HOST_HOSTNAME" "$HOST_IP"`
- Warning issued if only one variable is set

Configuration examples in README.md and docker-compose.yml

## Service Management

Reference: `scripts/entrypoint_ubuntu.sh:392-404`

The container supports optional disabling of specific services via environment variables:

**NETBIOS_DISABLE:**
- Disables the NetBIOS name service (nmbd)
- Removes `/container/config/runit/nmbd`

**WINBIND_DISABLE:**
- Disables the winbind service in AD-enabled containers
- Removes `/container/config/runit/winbind`
- Allows using AD features without winbind
- Reference: `README.md:253-256`

**AVAHI_DISABLE:**
- Disables internal Avahi service
- Checked in conjunction with AVAHI_INSTALL and external Avahi mount

All disable flags follow the pattern: set to any value to disable the service.

## Testing

Run build script with help: `./build_ubuntu.sh -h`

---

# Claude Code Sessions Guide

This section provides collaborative guidance and philosophy when using the Claude Code Sessions system.

## Collaboration Philosophy

**Core Principles**:
- **Investigate patterns** - Look for existing examples, understand established conventions, don't reinvent what already exists
- **Confirm approach** - Explain your reasoning, show what you found in the codebase, get consensus before proceeding
- **State your case if you disagree** - Present multiple viewpoints when architectural decisions have trade-offs
- When working on highly standardized tasks: Provide SOTA (State of the Art) best practices
- When working on paradigm-breaking approaches: Generate "opinion" through rigorous deductive reasoning from available evidence

## Task Management

### Best Practices
- One task at a time (check .claude/state/current_task.json)
- Update work logs as you progress
- Mark todos as completed immediately after finishing

### Quick State Checks
```bash
cat .claude/state/current_task.json  # Shows current task
git branch --show-current             # Current branch/task
```

### current_task.json Format

**ALWAYS use this exact format for .claude/state/current_task.json:**
```json
{
  "branch": "feature/branch", // Git branch (NOT "branch_name")
  "services": ["service1"],   // Array of affected services/modules
  "task": "task-name",        // Just the task name, NO path, NO .md extension
  "updated": "2025-08-27"     // Current date in YYYY-MM-DD format
}
```

**Common mistakes to avoid:**
- ❌ Using `"task_file"` instead of `"task"`
- ❌ Using `"branch_name"` instead of `"branch"`
- ❌ Including path like `"tasks/m-task.md"`
- ❌ Including `.md` file extension

## Using Specialized Agents

You have specialized subagents for heavy lifting. Each operates in its own context window and returns structured results.

### Prompting Agents

Agent descriptions will contain instructions for invocation and prompting. In general, it is safer to issue lightweight prompts. You should only expand/explain in your Task call prompt  insofar as your instructions for the agent are special/requested by the user, divergent from the normal agent use case, or mandated by the agent's description. Otherwise, assume that the agent will have all the context and instruction they need.

Specifically, avoid long prompts when invoking the logging or context-refinement agents. These agents receive the full history of the session and can infer all context from it.

### Available Agents

1. **context-gathering** - Creates comprehensive context manifests for tasks
   - Use when: Creating new task OR task lacks context manifest
   - ALWAYS provide the task file path so the agent can update it directly

2. **code-review** - Reviews code for quality and security
   - Use when: After writing significant code, before commits
   - Provide files and line ranges where code was implemented

3. **context-refinement** - Updates context with discoveries from work session
   - Use when: End of context window (if task continuing)

4. **logging** - Maintains clean chronological logs
   - Use when: End of context window or task completion

5. **service-documentation** - Updates service CLAUDE.md files
   - Use when: After service changes

### Agent Principles
- **Delegate heavy work** - Let agents handle file-heavy operations
- **Be specific** - Give agents clear context and goals
- **One agent, one job** - Don't combine responsibilities

## Code Philosophy

### Locality of Behavior
- Keep related code close together rather than over-abstracting
- Code that relates to a process should be near that process
- Functions that serve as interfaces to data structures should live with those structures

### Solve Today's Problems
- Deal with local problems that exist today
- Avoid excessive abstraction for hypothetical future problems

### Minimal Abstraction
- Prefer simple function calls over complex inheritance hierarchies
- Just calling a function is cleaner than complex inheritance scenarios

### Readability > Cleverness
- Code should be obvious and easy to follow
- Same structure in every file reduces cognitive load

## Shell Scripting Standards

### Script Header Requirements
- Always add script description at the top
- List all script dependencies with format: `- package_name (command1, command2)`
  Example: `- coreutils (cat, echo, ls)`
- List all used exit codes (`0` is reserved for success; `1` is reserved for unknown errors)

### Quoting Rules

- Prefer single quotes unless quoting variables or subcommands
- Literal strings, subcommands and variables must be always quoted
- Literal numbers must not be quoted when used on their own (i.e. when not part of a longer value)

### Help Function Behavior
- The function which outputs help message should not exit
- `$0 -h` should exit with `0`
- If an option is missing or is invalid, exit outside of the help function

### Formatting
- Use tabs for indentation
- Always add space between redirection operators and files: `2> /dev/null` not `2>/dev/null`
- This applies to all redirections: `>`, `>>`, `>>>`, `<`, `<<`, `<<<`, `&>`, `2>`, etc.

### Command Best Practices
- Avoid useless use of echo/cat
- Examples: Use `bc <<< "$SIZE_VALUE * 1048576"` instead of `echo "$SIZE_VALUE * 1048576" | bc`
- Use `[[ ]]` for conditional tests instead of `[ ]`
- Always quote variables: `"$variable"` not `$variable`
- Use `$()` for command substitution, not backticks

### Examples
```bash
# Good - direct input to bc
result=$(bc <<< "$size_value * 1048576")

# Bad - useless use of echo
result=$(echo "$size_value * 1048576" | bc)

# Good - proper quoting and modern syntax
if [[ -f "$filename" ]]; then
	content=$(cat "$filename")
fi

# Good - proper redirection spacing
command 2> /dev/null
command > output.txt
command &> all_output.txt
```

## Code Comments Standards

### Focus on Why, Not What Changed
- No comparison comments with previous implementations
- Focus on explaining **why** not **what changed**
- ❌ `// Changed from using echo | bc to bc <<<`
- ✅ `// Use here-string to avoid subprocess overhead`

### Exception for Critical Issues
- Document critical bugs/limitations with context
- Explain the issue and why current approach is necessary
- Example: `// Using workaround for CVE-2024-1234 until upstream fix available`

## Protocol Management

### CRITICAL: Protocol Recognition Principle

**When the user mentions protocols:**

1. **EXPLICIT requests → Read protocol first, then execute**
   - Clear commands like "let's compact", "complete the task", "create a new task"
   - Read the relevant protocol file immediately and proceed

2. **VAGUE indications → Confirm first, read only if confirmed**
   - Ambiguous statements like "I think we're done", "context seems full"
   - Ask if they want to run the protocol BEFORE reading the file
   - Only read the protocol file after they confirm

**Never attempt to run protocols from memory. Always read the protocol file before executing.**

### Protocol Files and Recognition

These protocols guide specific workflows:

1. **sessions/protocols/task-creation.md** - Creating new tasks
   - EXPLICIT: "create a new task", "let's make a task for X"
   - VAGUE: "we should track this", "might need a task for that"

2. **sessions/protocols/task-startup.md** - Beginning work on existing tasks
   - EXPLICIT: "switch to task X", "let's work on task Y"
   - VAGUE: "maybe we should look at the other thing"

3. **sessions/protocols/task-completion.md** - Completing and closing tasks
   - EXPLICIT: "complete the task", "finish this task", "mark it done"
   - VAGUE: "I think we're done", "this might be finished"

4. **sessions/protocols/context-compaction.md** - Managing context window limits
   - EXPLICIT: "let's compact", "run context compaction", "compact and restart"
   - VAGUE: "context is getting full", "we're using a lot of tokens"

### Behavioral Examples

**Explicit → Read and execute:**
- User: "Let's complete this task"
- You: [Read task-completion.md first] → "I'll complete the task now. Running the logging agent..."

**Vague → Confirm before reading:**
- User: "I think we might be done here"
- You: "Would you like me to run the task completion protocol?"
- User: "Yes"
- You: [NOW read task-completion.md] → "I'll complete the task now..."

<!-- nx configuration start-->
<!-- Leave the start & end comments to automatically receive updates. -->

# General Guidelines for working with Nx

- When running tasks (for example build, lint, test, e2e, etc.), always prefer running the task through `nx` (i.e. `nx run`, `nx run-many`, `nx affected`) instead of using the underlying tooling directly
- You have access to the Nx MCP server and its tools, use them to help the user
- When answering questions about the repository, use the `nx_workspace` tool first to gain an understanding of the workspace architecture where applicable.
- When working in individual projects, use the `nx_project_details` mcp tool to analyze and understand the specific project structure and dependencies
- For questions around nx configuration, best practices or if you're unsure, use the `nx_docs` tool to get relevant, up-to-date docs. Always use this instead of assuming things about nx configuration
- If the user needs help with an Nx configuration or project graph error, use the `nx_workspace` tool to get any errors

<!-- nx configuration end-->
