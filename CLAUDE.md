# CLAUDE.md

This file provides guidance to Claude Code when working with the Claude Code Delegation System.

---

## CRITICAL: Delegation Policy

**MANDATORY IMMEDIATE DELEGATION ON TOOL BLOCK**

When ANY tool is blocked by the delegation policy hook:

1. **DO NOT try alternative approaches** (different tools, workarounds, etc.)
2. **DO NOT explain what you tried** - just delegate immediately
3. **IMMEDIATELY use `/delegate <task>`** on first tool block
4. **The entire user request must be delegated**, not just the blocked tool

### Recognition Pattern

```
Error: PreToolUse:* hook error: [...] 🚫 Tool blocked by delegation policy
Tool: <ToolName>

⚠️ STOP: Do NOT try alternative tools.
✅ REQUIRED: Use /delegate command immediately:
   /delegate <full task description>
```

When you see this error pattern, **stop immediately** and delegate the entire task.

### Correct vs Incorrect Examples

**Example - WRONG:**
```
❌ Read blocked → Try Glob → Glob blocked → Try Grep → Grep blocked → Finally delegate
```

**Example - CORRECT:**
```
✅ Read blocked → Immediately use: /delegate <full task description>
```

### The Delegation Flow

```mermaid
flowchart TD
    Start([User Request]) --> Attempt[Attempt Tool Use]
    Attempt --> Hook{PreToolUse Hook}

    Hook -->|Allowed Tool| Execute[Execute Tool]
    Hook -->|Blocked Tool| Error[Block with Error Message]

    Error --> Stop[STOP Immediately]
    Stop --> Delegate[Use /delegate command]

    Delegate --> Register[Hook Registers Session]
    Register --> Orchestrator[delegation-orchestrator Analyzes]
    Orchestrator --> Select[Select Specialized Agent]
    Select --> Agent[Agent Executes Task]
    Agent --> Results[Return Results]

    Execute --> Results
```

### Key Points

- **First tool block = immediate delegation** - Don't try alternatives
- **Delegate the entire user request** - Not just the blocked operation
- **Follow the error message instructions** - They tell you exactly what to do
- **Session registration happens automatically** - First `/delegate` marks session as delegated
- **Specialized agents handle execution** - Orchestrator routes to expert agents

---

## Commands

### Installation

```bash
# Copy configuration to Claude Code directory
cp -r src/agents src/commands src/hooks src/system-prompts src/scripts src/settings.json ~/.claude/

# Make hooks executable
chmod +x ~/.claude/hooks/PreToolUse/require_delegation.sh
chmod +x ~/.claude/hooks/UserPromptSubmit/clear-delegation-sessions.sh
chmod +x ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh
chmod +x ~/.claude/hooks/stop/python_stop_hook.sh
chmod +x ~/.claude/scripts/statusline.sh

# Verify installation
ls -la ~/.claude/hooks/PreToolUse/require_delegation.sh
```

### Usage

**Single-Step Delegation:**
```bash
/delegate Create a calculator module with add, subtract, multiply, divide functions
```

**Multi-Step Workflows (with orchestration):**
```bash
claude --append-system-prompt "$(cat ~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md)" \
  "Create calculator.py with tests and verify they pass"
```

**Read-Only Questions:**
```bash
/ask How does the authentication system work?
/ask What database is configured? haiku
/ask Explain the API architecture opus
```

**Pre-Commit Quality Checks:**
```bash
/pre-commit
/pre-commit haiku
```

The `/pre-commit` command runs comprehensive code quality checks before committing:
- **Python validation:** Ruff linting and Pyright type checking
- **Security scanning:** Critical vulnerability detection
- **Hook testing:** Validates all hook scripts for syntax and security
- **Standards compliance:** Enforces project coding standards

### Debug Commands

**Enable Debug Logging:**
```bash
export DEBUG_DELEGATION_HOOK=1
tail -f /tmp/delegation_hook_debug.log
```

**Emergency Bypass (Disable Delegation):**
```bash
export DELEGATION_HOOK_DISABLE=1
claude "your command"
```

**Check Delegation State:**
```bash
cat .claude/state/delegated_sessions.txt
```

---

## Architecture Overview

### Comprehensive Hook System

The delegation system uses a comprehensive 6-hook architecture to enforce policies, manage state, and provide observability:

#### 1. SessionStart Hook

**Location:** `src/hooks/SessionStart/log_session_start.sh`

**Trigger:** Beginning of each Claude Code session (main or subagent)

**Functions:**
- Logs session initialization to `/tmp/claude_session_log.txt`
- Records session ID, timestamp, and session type (main vs subagent)
- Initializes session-specific state tracking
- Sets up environment for delegation policy enforcement

**Key Data Logged:**
```
[2025-01-11 14:30:22] SESSION_START session_id=sess_abc123 type=main
```

#### 2. UserPromptSubmit Hook

**Location:** `src/hooks/UserPromptSubmit/clear-delegation-sessions.sh`

**Trigger:** Before each user message is processed

**Functions:**
- Clears delegation state file (`.claude/state/delegated_sessions.txt`)
- Resets privilege escalation (no persistent delegation across prompts)
- Ensures fresh enforcement per user message
- Logs prompt submission events

**Critical Security Feature:** Prevents privilege persistence - each user prompt starts with clean slate.

#### 3. PreToolUse Hook

**Location:** `src/hooks/PreToolUse/require_delegation.sh`

**Trigger:** Before EVERY tool invocation

**Functions:**
- Enforces delegation policy allowlist
- Blocks non-allowed tools with error message
- Registers session ID when delegation begins (`Task`/`SlashCommand` invoked)
- Checks session registry for delegation privileges
- Logs all tool access attempts (when DEBUG_DELEGATION_HOOK=1)

**Allowlist:**
- `AskUserQuestion` - Always allowed (read-only questions)
- `TodoWrite` - Always allowed (task tracking)
- `SlashCommand` - Always allowed, triggers session registration
- `Task`/`SubagentTask`/`AgentTask` - Always allowed, triggers session registration

**All other tools:** BLOCKED unless session is registered in `.claude/state/delegated_sessions.txt`

**Session Registration Flow:**
```
1. User invokes /delegate or Task tool
2. PreToolUse hook detects Task/SlashCommand
3. Hook writes session ID to .claude/state/delegated_sessions.txt
4. All subsequent tools in this session are allowed
5. UserPromptSubmit hook clears file on next user prompt
```

#### 4. PostToolUse Hook

**Location:** `src/hooks/PostToolUse/python_posttooluse_hook.sh`

**Trigger:** After Python file Write/Edit operations

**Functions:**
- Validates Python code against project standards
- Runs critical security checks (exec, eval, hardcoded secrets)
- Executes Ruff linting (syntax, security, quality)
- Runs Pyright type checking (basic mode)
- Blocks operations that violate standards

**Validation Stages:**
1. **Critical Security Check** (fast pattern matching)
   - exec(), eval() usage
   - Hardcoded passwords/secrets
   - Unsafe serialization (pickle, marshal)
   - Insecure random (random vs secrets)
   - TLS verification disabled
   - Unsafe YAML loading

2. **Ruff Validation** (comprehensive linting)
   - Modern type hints (list[T] vs List[T])
   - No print statements (use logging)
   - Import management
   - Error handling best practices
   - Security patterns (SQL/command injection)

3. **Pyright Type Checking** (type safety)
   - Type annotation correctness
   - Type compatibility
   - Missing type hints

See APPENDIX: Python Coding Standards for complete rules.

#### 5. SubagentStop Hook

**Location:** `src/hooks/SubagentStop/log_subagent_stop.sh`

**Trigger:** When a subagent (Task-spawned agent) completes

**Functions:**
- Logs subagent completion to `/tmp/claude_session_log.txt`
- Records exit status, execution duration
- Updates parallel execution state (`.claude/state/active_delegations.json`)
- Cleans up subagent-specific resources
- Tracks wave completion for parallel workflows

**Key Data Logged:**
```
[2025-01-11 14:32:15] SUBAGENT_STOP session_id=sess_def456 parent=sess_abc123 duration=113s exit_code=0
```

**Parallel Workflow Integration:**
- Removes subagent from `active_delegations.json`
- Triggers wave synchronization check
- Aggregates context for next wave

#### 6. Stop Hook

**Location:** `src/hooks/stop/python_stop_hook.sh`

**Trigger:** End of main Claude Code session

**Functions:**
- Logs session termination to `/tmp/claude_session_log.txt`
- Cleans up temporary state files
- Archives session data for debugging
- Removes stale delegation registrations (>1 hour old)
- Performs final validation of parallel workflow state

**Key Data Logged:**
```
[2025-01-11 14:35:00] SESSION_STOP session_id=sess_abc123 duration=278s
```

### Hook Lifecycle

**Complete execution flow:**

```
SessionStart (initialize)
         ↓
UserPromptSubmit (clear delegation state)
         ↓
Main Claude receives message
         ↓
PreToolUse (check/block tools, register session)
         ↓
Tool executes
         ↓
PostToolUse (validate Python code if Write/Edit)
         ↓
SubagentStop (if subagent completes)
         ↓
Stop (cleanup on session exit)
```

**Parallel Workflow Lifecycle:**

```
SessionStart (main session)
         ↓
UserPromptSubmit (clear state)
         ↓
/delegate triggers PreToolUse → registers session
         ↓
Task tool spawns Wave 1 subagents (parallel)
         ↓
Each subagent:
  SessionStart → PreToolUse → Execute → PostToolUse → SubagentStop
         ↓
Wave 1 synchronization: Wait for all SubagentStop events
         ↓
Wave 2 spawns (if exists)
         ↓
Stop (main session cleanup)
```

### Agent Orchestration

The system uses a two-stage delegation architecture:

**Stage 1: Orchestration (Analysis & Planning)**
- **Agent:** `delegation-orchestrator`
- **Location:** `~/.claude/agents/delegation-orchestrator.md`
- **Responsibilities:**
  - Task complexity analysis (single-step vs multi-step)
  - Agent selection via keyword matching (≥2 matches threshold)
  - Configuration loading from agent `.md` files
  - Prompt construction with agent system prompts
  - Context passing template creation for multi-step workflows
  - Execution mode selection (sequential vs parallel)

**Stage 2: Execution (Delegation)**
- **Process:**
  - Parse orchestrator's recommendation
  - Extract delegation prompt from code fences
  - Spawn specialized agent via `Task` tool
  - Capture results and pass context to next phase (if multi-step)
  - Update TodoWrite task list after each phase

**Complete Flow:**
```mermaid
flowchart TD
    User[User Request] --> Hook[PreToolUse Hook Blocks]
    Hook --> Policy[CLAUDE.md Policy Enforces]
    Policy --> Delegate[Use /delegate]

    Delegate --> Register[Hook Registers Session]
    Register --> Spawn[Spawn delegation-orchestrator]

    Spawn --> Analyze{Analyze Complexity}
    Analyze -->|Single-Step| SingleAgent[Select Specialized Agent]
    Analyze -->|Multi-Step| MultiPhase[Decompose into Phases]

    SingleAgent --> LoadConfig[Load Agent Config]
    LoadConfig --> BuildPrompt[Build Delegation Prompt]
    BuildPrompt --> Return[Return Recommendation]

    MultiPhase --> MapAgents[Map Phases to Agents]
    MapAgents --> Dependencies{Analyze Dependencies}

    Dependencies -->|Dependent| Sequential[Sequential Execution Plan]
    Dependencies -->|Independent| Parallel[Parallel Execution Plan]

    Sequential --> BuildTemplates[Build Context Templates]
    Parallel --> BuildWaves[Build Wave Execution Plan]

    BuildTemplates --> Return
    BuildWaves --> Return

    Return --> Execute[Execute via Task Tool]
    Execute --> Results[Return Results to User]
```

### State Management

**Session Registry** (`.claude/state/delegated_sessions.txt`)
- **Format:** One session ID per line
- **Lifecycle:** Created on first delegation, cleared on next user prompt
- **Cleanup:** Sessions older than 1 hour automatically removed
- **Purpose:** Tracks which sessions have delegation privileges

**Active Delegations** (`.claude/state/active_delegations.json`)
- **Format:** JSON with workflow_id, active_delegations array
- **Purpose:** Track concurrent subagent sessions in parallel workflows
- **Schema version:** 2.0

**State Machine:**
```
[User Prompt] → [Clear State] → [Main Claude Receives]
      ↓
[Attempt Tool] → [PreToolUse Hook]
      ↓
Is session in delegated_sessions.txt?
      ├─ YES → Allow tool
      └─ NO → Is tool in allowlist?
            ├─ YES (Task/SlashCommand) → Register session, allow
            ├─ YES (TodoWrite/AskUserQuestion) → Allow
            └─ NO → BLOCK
```

### Session Inheritance Mechanism

The delegation system uses **session inheritance** to propagate tool access privileges from parent (main) Claude session to subagents:

**How It Works:**

1. **Parent Session Registration**
   - User invokes `/delegate` command
   - PreToolUse hook detects `SlashCommand` invocation
   - Parent session ID written to `.claude/state/delegated_sessions.txt`
   - Parent session now has delegation privileges

2. **Subagent Spawning**
   - Parent session uses `Task` tool to spawn subagent
   - Subagent receives NEW session ID (different from parent)
   - PreToolUse hook detects `Task` invocation
   - Subagent session ID written to `.claude/state/delegated_sessions.txt`

3. **Privilege Inheritance**
   - Subagent's session ID is registered during spawning
   - Subagent can use all tools (Read, Write, Edit, Bash, etc.)
   - Subagent can spawn nested subagents (recursively inherits)
   - Each nested level registers its session ID

4. **Lifecycle Management**
   - All session IDs persist in file until UserPromptSubmit hook
   - SubagentStop hook updates parallel execution state
   - Stop hook cleans up stale sessions (>1 hour old)
   - UserPromptSubmit clears ALL registrations on next user prompt

**Key Security Properties:**

- **No persistent privilege:** Sessions cleared on each user prompt
- **Explicit delegation:** Tools blocked by default, allowed only after `/delegate`
- **Transparent logging:** All session registrations logged (DEBUG mode)
- **Recursive safety:** Nested subagents inherit but can't escalate further

**Example Session Tree:**

```
Main Session (sess_abc123)
  └─ registers: sess_abc123
      ├─ Subagent A (sess_def456)
      │   └─ registers: sess_def456
      │       ├─ Tool access: ✓ (inherited)
      │       └─ Nested Subagent (sess_ghi789)
      │           └─ registers: sess_ghi789
      │               └─ Tool access: ✓ (inherited)
      └─ Subagent B (sess_jkl012)
          └─ registers: sess_jkl012
              └─ Tool access: ✓ (inherited)

delegated_sessions.txt contents:
sess_abc123
sess_def456
sess_ghi789
sess_jkl012
```

**State File Format:**

```bash
# .claude/state/delegated_sessions.txt
sess_abc123
sess_def456
sess_jkl012

# Each line is a session ID with delegation privileges
# File cleared on next UserPromptSubmit hook
```

### StatusLine System

The delegation system includes a **real-time status display** that provides visibility into workflow execution state, active delegations, and system health.

#### Overview

**StatusLine** is a dynamic status bar displayed at the top of the Claude Code terminal interface. It updates in real-time to show:
- Current workflow execution mode (sequential vs parallel)
- Active subagent count and wave information
- Memory pressure and resource limits
- Recent warnings and errors
- System health indicators

**Visibility:** Always displayed during delegation workflows, automatically updated by hooks.

#### Script

**Location:** `src/scripts/statusline.sh`

**Functions:**
- Reads state files (`.claude/state/active_delegations.json`, memory metrics)
- Formats status information with color-coding
- Displays in compact, single-line format
- Updates on hook triggers (SessionStart, SubagentStop, etc.)

**Invocation:**
```bash
# Called automatically by hooks
~/.claude/scripts/statusline.sh

# Manual invocation for debugging
bash ~/.claude/scripts/statusline.sh
```

#### Display Components

**1. Workflow Mode Indicator**
```
[SEQ] - Sequential execution mode
[PAR] - Parallel execution mode (with wave info)
```

**2. Active Delegations Counter**
```
Active: 2/4 - 2 subagents running, max 4 concurrent
Wave 1 - Currently executing Wave 1 phases
```

**3. Memory Pressure Indicator**
```
Mem: OK - Memory usage normal
Mem: WARN - Approaching limit (80-95%)
Mem: CRIT - Critical memory pressure (>95%)
```

**4. Recent Events**
```
Last: Subagent-A completed (113s)
Last: Wave 1 sync complete
```

**5. Complete Example**
```
[PAR] Active: 2/4 Wave 1 | Mem: OK | Last: Phase-A completed (113s)
```

#### Configuration

StatusLine behavior is controlled by environment variables:

**MEMORY_LIMIT**
- **Purpose:** Maximum memory (MB) allowed for parallel execution
- **Default:** 8192 (8GB)
- **Usage:** `export MEMORY_LIMIT=4096`
- **Effect:** Limits concurrent subagent spawning based on available memory

**MEMORY_AGGRESSIVE**
- **Purpose:** Enable aggressive memory management (kill subagents on pressure)
- **Values:** 0 (disabled, default), 1 (enabled)
- **Usage:** `export MEMORY_AGGRESSIVE=1`
- **Effect:** Automatically terminates lowest-priority subagents when memory >95%

**MAX_PARALLEL_TASKS**
- **Purpose:** Maximum concurrent subagents in parallel execution
- **Default:** 4
- **Usage:** `export MAX_PARALLEL_TASKS=2`
- **Effect:** Limits Wave execution to N concurrent subagents

**Example Configuration:**
```bash
# Conservative resource limits
export MEMORY_LIMIT=4096          # 4GB max
export MAX_PARALLEL_TASKS=2       # 2 concurrent subagents
export MEMORY_AGGRESSIVE=0        # No auto-kill

# Aggressive parallel execution
export MEMORY_LIMIT=16384         # 16GB max
export MAX_PARALLEL_TASKS=8       # 8 concurrent subagents
export MEMORY_AGGRESSIVE=1        # Auto-kill on pressure
```

#### Integration

**Hook Integration:**

1. **SessionStart Hook:** Displays initial status
2. **PreToolUse Hook:** Updates on delegation start
3. **SubagentStop Hook:** Updates on subagent completion, wave sync
4. **Stop Hook:** Clears status on session exit

**Example Flow:**

```
[User starts workflow]
SessionStart → StatusLine: [SEQ] Active: 0/4 | Mem: OK

[Delegation begins]
PreToolUse → StatusLine: [SEQ] Active: 1/4 | Mem: OK | Last: delegation-orchestrator started

[Parallel waves spawn]
Task spawns Wave 1 → StatusLine: [PAR] Active: 3/4 Wave 1 | Mem: OK

[Memory pressure detected]
Memory >80% → StatusLine: [PAR] Active: 3/4 Wave 1 | Mem: WARN

[Subagent completes]
SubagentStop → StatusLine: [PAR] Active: 2/4 Wave 1 | Mem: OK | Last: Phase-A completed (113s)

[Wave synchronization]
All Wave 1 complete → StatusLine: [PAR] Active: 0/4 Wave 2 | Mem: OK | Last: Wave 1 sync complete

[Session ends]
Stop → StatusLine cleared
```

#### State Files

StatusLine reads from:

1. **`.claude/state/active_delegations.json`**
   - Workflow mode (sequential/parallel)
   - Active subagent count
   - Current wave number
   - Subagent metadata (agent name, start time)

2. **Memory Metrics** (system calls)
   - Available memory (via `sysctl` or `/proc/meminfo`)
   - Process memory usage (via `ps`)
   - Memory pressure calculation

3. **Session Log** (`/tmp/claude_session_log.txt`)
   - Recent events (last 5 entries)
   - Subagent completion times
   - Error messages

#### Usage Examples

**During Development:**
```bash
# Monitor status in separate terminal
watch -n 1 ~/.claude/scripts/statusline.sh

# Check current state
cat .claude/state/active_delegations.json
```

**Debugging Memory Issues:**
```bash
# Enable memory warnings
export MEMORY_LIMIT=4096

# Run workflow and monitor
claude --append-system-prompt "$(cat ~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md)" \
  "Analyze codebase AND design API AND write docs"

# StatusLine will show memory pressure warnings
```

**Optimizing Parallelism:**
```bash
# Start conservative
export MAX_PARALLEL_TASKS=2

# Observe StatusLine during execution
# If memory OK and phases independent, increase:
export MAX_PARALLEL_TASKS=4
```

#### Troubleshooting

**StatusLine Not Updating:**

```bash
# Check script permissions
ls -la ~/.claude/scripts/statusline.sh
chmod +x ~/.claude/scripts/statusline.sh

# Check state file exists
ls -la .claude/state/active_delegations.json

# Verify hooks are calling statusline
grep statusline ~/.claude/hooks/*/*.sh
```

**Incorrect Memory Readings:**

```bash
# Test memory detection
bash -c '
  if [[ "$OSTYPE" == "darwin"* ]]; then
    vm_stat | grep "Pages free"
  else
    free -m
  fi
'

# Verify MEMORY_LIMIT is set
echo $MEMORY_LIMIT
```

**StatusLine Shows Wrong Wave:**

```bash
# Check active_delegations.json schema
cat .claude/state/active_delegations.json | jq .

# Verify SubagentStop hook is updating state
tail -f /tmp/claude_session_log.txt | grep SUBAGENT_STOP
```

---

## Agent Capabilities

### 11 Specialized Agents

The system provides domain-expert agents with keyword-based activation:

| Agent | Keywords | Capabilities |
|-------|----------|--------------|
| **delegation-orchestrator** | delegate, orchestrate, route task | Meta-agent for task analysis and routing |
| **codebase-context-analyzer** | analyze, understand, explore, architecture, patterns, structure, dependencies | Read-only code exploration and architecture analysis |
| **tech-lead-architect** | design, approach, research, evaluate, best practices, architect, scalability, security | Solution design and architectural decisions |
| **task-completion-verifier** | verify, validate, test, check, review, quality, edge cases | Testing, QA, validation |
| **code-cleanup-optimizer** | refactor, cleanup, optimize, improve, technical debt, maintainability | Refactoring and code quality improvement |
| **code-reviewer** | review, code review, critique, feedback, assess quality, evaluate code | Code review and quality assessment |
| **devops-experience-architect** | setup, deploy, docker, CI/CD, infrastructure, pipeline, configuration | Infrastructure, deployment, containerization |
| **documentation-expert** | document, write docs, README, explain, create guide, documentation | Documentation creation and maintenance |
| **dependency-manager** | dependencies, packages, requirements, install, upgrade, manage packages | Dependency management (Python/UV focused) |
| **task-decomposer** | plan, break down, subtasks, roadmap, phases, organize, milestones | Project planning and task breakdown |
| **phase-validator** | validate, verify phase, check completion, phase criteria | Phase completion validation, deliverable verification |

### Agent Selection Algorithm

**From delegation-orchestrator:**

1. **Extract Keywords:** Parse task description (case-insensitive), tokenize into words
2. **Count Matches:** For each agent, count activation keyword matches in task
3. **Apply Threshold:** Select agent with ≥2 keyword matches (highest count wins)
4. **Record Rationale:** Document which keywords matched

**Examples:**

**Task:** "Analyze the authentication system architecture"
- Keywords in task: "analyze", "authentication", "system", "architecture"
- codebase-context-analyzer matches: analyze=1, architecture=1 = **2 matches**
- **Selected:** codebase-context-analyzer

**Task:** "Refactor auth module to improve maintainability"
- Keywords in task: "refactor", "improve", "maintainability"
- code-cleanup-optimizer matches: refactor=1, improve=1, maintainability=1 = **3 matches**
- **Selected:** code-cleanup-optimizer

**Task:** "Create a new utility function"
- No agent reaches 2 matches
- **Selected:** general-purpose (no specialized agent)

### Agent Configuration Loading

**Step-by-step process:**

1. **Construct Path:** `~/.claude/agents/{agent-name}.md`
2. **Load File:** Use Read tool to load agent file
3. **Parse Structure:**
   - Lines 1-N (between `---` markers): YAML frontmatter (metadata)
   - Lines N+1 to EOF: System prompt content
4. **Extract System Prompt:** Everything after second `---` marker becomes agent's instructions
5. **Construct Delegation Prompt:**

**For specialized agent:**
```
[Agent System Prompt from file]

---

TASK: [User's task description with objectives]
```

**For general-purpose:**
```
[User's task description with objectives]
```

### Agent Tool Restrictions

Each specialized agent has a **restricted tool set** to ensure they operate within their domain expertise and don't exceed their intended scope:

**Tool Restriction Enforcement:**
- Agents declare allowed tools in frontmatter (`tools: ["Tool1", "Tool2"]`)
- Delegation orchestrator validates tool usage
- Agents attempting disallowed tools receive error messages
- Critical for security and domain separation

**Common Tool Sets:**

**Read-Only Agents** (codebase-context-analyzer, code-reviewer):
```yaml
tools: ["Read", "Glob", "Grep", "Bash"]
```
- Can explore codebase, search files, run read-only commands
- **Cannot** modify files (no Write, Edit)
- **Cannot** spawn subagents (no Task)

**Implementation Agents** (code-cleanup-optimizer, devops-experience-architect):
```yaml
tools: ["Read", "Write", "Edit", "Glob", "Grep", "Bash"]
```
- Can read and modify files
- Can run terminal commands
- **Cannot** spawn subagents (prevents recursive delegation)

**Meta-Agents** (delegation-orchestrator, task-decomposer):
```yaml
tools: ["Read", "Task", "TodoWrite"]
```
- Can spawn subagents (Task)
- Can manage task lists (TodoWrite)
- Can read agent configurations
- **Cannot** modify code directly (delegates to implementation agents)

**Verification Agents** (task-completion-verifier, phase-validator):
```yaml
tools: ["Read", "Bash", "Glob", "Grep"]
```
- Can read files and run tests
- Can execute validation commands
- **Cannot** modify implementation (ensures objectivity)
- **Cannot** spawn subagents (prevents test manipulation)

**Example Restriction Enforcement:**

**Scenario:** codebase-context-analyzer attempts to use Write tool

```
Agent: codebase-context-analyzer
Attempted Tool: Write
Allowed Tools: ["Read", "Glob", "Grep", "Bash"]

Error: Tool 'Write' not allowed for agent 'codebase-context-analyzer'
Allowed tools: Read, Glob, Grep, Bash

Suggestion: This is a read-only analysis agent. To modify files:
1. Complete your analysis
2. Return findings to main Claude
3. Main Claude will delegate to implementation agent (e.g., code-cleanup-optimizer)
```

**Why Tool Restrictions Matter:**

1. **Security:** Prevents agents from exceeding intended permissions
2. **Separation of Concerns:** Analysis agents don't modify code, implementation agents don't spawn subagents
3. **Clarity:** Clear boundaries prevent confusion about agent roles
4. **Auditability:** Tool usage patterns reveal agent behavior
5. **Error Prevention:** Agents can't accidentally trigger recursive delegation loops

**Tool Allowlist Reference:**

| Agent | Read | Write | Edit | Bash | Glob | Grep | Task | TodoWrite |
|-------|------|-------|------|------|------|------|------|-----------|
| **delegation-orchestrator** | ✓ | - | - | - | - | - | ✓ | ✓ |
| **codebase-context-analyzer** | ✓ | - | - | ✓ | ✓ | ✓ | - | - |
| **tech-lead-architect** | ✓ | ✓ | - | ✓ | ✓ | ✓ | - | - |
| **task-completion-verifier** | ✓ | - | - | ✓ | ✓ | ✓ | - | - |
| **code-cleanup-optimizer** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | - |
| **code-reviewer** | ✓ | - | - | ✓ | ✓ | ✓ | - | - |
| **devops-experience-architect** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | ✓ |
| **documentation-expert** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | - |
| **dependency-manager** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | - |
| **task-decomposer** | ✓ | - | - | - | - | - | - | ✓ |
| **phase-validator** | ✓ | - | - | ✓ | ✓ | ✓ | - | - |

**Note:** All agents have implicit access to `AskUserQuestion` for clarifications.

---

## Workflow Guidelines

### Simple Workflow Pattern

**Pattern Recognition:**
- Single action: "Create calculator.py"
- Single deliverable: "Analyze the authentication system"
- No sequential connectors: No "and then", "with", "after that"

**CRITICAL:** ALL workflows include automatic verification phases. Even simple tasks follow a 2-phase minimum:
- **Phase 1:** Implementation (create, build, design, refactor, etc.)
- **Phase 2:** Verification (validate implementation meets acceptance criteria)

**Execution Sequence:**
```
1. User: /delegate "Refactor auth module"
2. PreToolUse hook: Allow (SlashCommand), Register session
3. /delegate spawns delegation-orchestrator
4. Orchestrator analyzes: Simple workflow, keywords "refactor" → code-cleanup-optimizer
5. Orchestrator creates 2 phases:
   - Phase 1: Refactoring implementation (code-cleanup-optimizer)
   - Phase 2: Verification (task-completion-verifier or phase-validator)
6. Orchestrator loads agent configs and constructs prompts
7. Orchestrator returns recommendation with both phases
8. Main Claude spawns code-cleanup-optimizer for Phase 1
9. Phase 1 executes refactoring
10. Verification phase auto-injected: Phase 2 validates changes
11. Results returned to user with verification verdict
```

**TodoWrite IS Required** - All workflows use TodoWrite to track both implementation and verification phases.

### Multi-Step Workflow Detection

**Multi-step indicators (from WORKFLOW_ORCHESTRATOR.md):**

**Sequential Connectors:**
- "and then", "then", "after that", "next", "followed by"
- "once", "when done", "after"

**Compound Indicators:**
- "with [noun]" (e.g., "create app with tests")
- "and [verb]" (e.g., "design and implement")
- "including [noun]" (e.g., "build service including API docs")

**Multiple Distinct Verbs:**
- "read X and analyze Y and create Z"
- "create A, write B, update C"

**Phase Markers:**
- "first... then...", "start by... then..."
- "begin with... after that..."

### Sequential Execution (Dependent Phases)

**When to use:**
- Phase 2 reads files created by Phase 1
- Phases modify same file
- Phase dependencies require ordered execution
- API rate limits require sequential calls

**Example: "Create calculator.py with tests and verify they pass"**

**Dependency analysis:**
- Phase 1: Create calculator.py
- Phase 2: Write tests (needs calculator.py path from Phase 1)
- Phase 3: Run tests (needs tests from Phase 2)
- **Decision:** Sequential (Phase 2 depends on Phase 1, Phase 3 depends on Phase 2)

**Execution sequence:**
```
1. WORKFLOW_ORCHESTRATOR detects: "with tests" and "verify" (multi-step)
2. TodoWrite creates task list:
   - Phase 1: Create calculator.py (pending → in_progress)
   - Phase 2: Write tests (pending)
   - Phase 3: Verify tests pass (pending)
3. /delegate [full task]
4. delegation-orchestrator analyzes:
   - Multi-step detected
   - Phase 1 → general-purpose
   - Phase 2 → task-completion-verifier
   - Phase 3 → task-completion-verifier
   - Dependency: Sequential (Phase 2 needs Phase 1's file)
5. Phase 1 executes: calculator.py created at /path/to/calculator.py
6. Context captured: File path, functions implemented
7. TodoWrite update: Phase 1 complete, Phase 2 in_progress
8. Phase 2 prompt: "Write tests for /path/to/calculator.py"
9. Phase 2 executes: Tests created at /path/to/test_calculator.py
10. TodoWrite update: Phase 2 complete, Phase 3 in_progress
11. Phase 3 executes: Tests run and verified
12. TodoWrite update: Phase 3 complete
13. Summary provided with all file paths
```

**Context passing protocol:**
```
Context from Phase 1:
- Created file: /absolute/path/to/calculator.py
- Implemented functions: add, subtract, multiply, divide
- Key decision: Used type hints for Python 3.12+
- Issue encountered: None
```

### Parallel Execution (Independent Phases)

**When to use:**
- Phases operate on different files/systems
- No data dependencies between phases
- Resource isolation (no file conflicts)
- Time-intensive phases (>60 seconds each)

**Example: "Analyze authentication system AND design payment API"**

**Dependency analysis:**
- Phase A (auth analysis): Operates on auth code
- Phase B (payment design): Operates on payment requirements
- **No data dependencies:** Phase B doesn't need Phase A's output
- **Resource isolation:** Different files/domains
- **Decision:** Parallel execution (Wave 1)

**Execution sequence:**
```
1. delegation-orchestrator detects: "AND" (explicit parallel hint), independent domains
2. Dependency analysis: No conflicts detected
3. Orchestrator creates parallel execution plan:
   Wave 1 (Parallel): [Phase A, Phase B]
   Expected time savings: ~50% (4min vs 8min sequential)
4. Main Claude spawns BOTH agents simultaneously:
   - Task tool call 1: codebase-context-analyzer (Phase A)
   - Task tool call 2: tech-lead-architect (Phase B)
5. Phase A and Phase B execute concurrently
6. Wave synchronization: Wait for BOTH to complete
7. Context aggregation:
   From Phase A: /path/to/auth-analysis.md, JWT pattern, security requirements
   From Phase B: /path/to/payment-design.md, API endpoints, integration points
8. TodoWrite update: Both phases complete
9. If Wave 2 exists (e.g., integration phase):
   - Aggregated context passed to Wave 2 phases
   - Wave 2 executes after Wave 1 completion
```

**Parallel execution state** (`.claude/state/active_delegations.json`):
```json
{
  "version": "2.0",
  "workflow_id": "wf_20250111_143022",
  "execution_mode": "parallel",
  "active_delegations": [
    {
      "delegation_id": "deleg_20250111_143022_001",
      "phase_id": "phase_a",
      "session_id": "sess_abc123",
      "wave": 1,
      "status": "active",
      "started_at": "2025-01-11T14:30:22Z",
      "agent": "codebase-context-analyzer"
    },
    {
      "delegation_id": "deleg_20250111_143023_002",
      "phase_id": "phase_b",
      "session_id": "sess_def456",
      "wave": 1,
      "status": "active",
      "started_at": "2025-01-11T14:30:23Z",
      "agent": "tech-lead-architect"
    }
  ],
  "max_concurrent": 4
}
```

### Execution Mode Selection Logic

**Criteria for Parallel Execution:**
- Independence: No data dependencies between phases
- Resource isolation: Phases operate on different files/systems
- Time benefit: Expected time savings >30%
- No conflicts: No file modification or state mutation conflicts

**Criteria for Sequential Execution:**
- Data dependencies: Phase B reads files created by Phase A
- File conflicts: Both phases modify same file
- State conflicts: Both phases affect same system state
- API rate limits: Both phases call same external API
- Uncertainty: Conservative fallback when dependencies unclear

**Conservative Decision Rule:** "When in doubt, choose sequential."

### Context Passing Requirements

**Required context elements:**
- **File paths:** Always absolute paths (e.g., `/Users/user/project/calculator.py`)
- **Key decisions:** Framework choices, architectural patterns
- **Configurations:** Settings, environment variables
- **Issues encountered:** Blockers and resolutions
- **Specific artifacts:** References to files/objects for next phase

**Example context format:**
```
Context from Phase 1 (Research):
- Analyzed documentation at https://example.com/docs
- Key finding: Plugin system uses event-driven architecture
- Created research notes: /tmp/research_notes.md
- Decision: Use webhook pattern for notifications
- Issue: API rate limit (resolved with exponential backoff)
```

---

## Configuration

### Settings File Structure

**File:** `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/settings.json`

**Permissions (deny sensitive files):**
```json
{
  "permissions": {
    "deny": [
      "Read(**/.env*)",
      "Read(**/.pem*)",
      "Read(**/*.key)",
      "Read(**/secrets/**)",
      "Read(**/credentials/**)",
      "Read(**/.aws/**)",
      "Read(**/.ssh/**)",
      "Read(**/docker-compose*.yml)",
      "Read(**/config/database.yml)"
    ]
  }
}
```

**Hook Registration:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/PreToolUse/require_delegation.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/UserPromptSubmit/clear-delegation-sessions.sh",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

### Agent File Format

**Standard structure:**
```markdown
---
name: agent-name
description: Agent description
tools: ["Tool1", "Tool2"]
color: visualization-color
activation_keywords: ["keyword1", "keyword2"]
---

# Agent System Prompt

[Complete system prompt content - this entire section is the agent's instructions]
```

**Location pattern:** `~/.claude/agents/{agent-name}.md`

**Examples:**
- `~/.claude/agents/delegation-orchestrator.md`
- `~/.claude/agents/codebase-context-analyzer.md`
- `~/.claude/agents/tech-lead-architect.md`
- `~/.claude/agents/task-completion-verifier.md`
- (... 7 more agents)

### Environment Variables

The delegation system supports 6 environment variables for controlling behavior, resource limits, and debugging:

| Variable | Purpose | Default | Values | Effect |
|----------|---------|---------|--------|--------|
| **MEMORY_LIMIT** | Max memory (MB) for parallel execution | 8192 | Integer (MB) | Limits concurrent subagent spawning |
| **MEMORY_AGGRESSIVE** | Aggressive memory management | 0 | 0 (off), 1 (on) | Auto-kill subagents on pressure >95% |
| **MAX_PARALLEL_TASKS** | Max concurrent subagents | 4 | Integer (1-16) | Limits wave execution parallelism |
| **DEBUG_DELEGATION_HOOK** | Enable debug logging | 0 | 0 (off), 1 (on) | Logs to `/tmp/delegation_hook_debug.log` |
| **DELEGATION_HOOK_DISABLE** | Emergency bypass | 0 | 0 (on), 1 (off) | Disables delegation enforcement |
| **CLAUDE_PROJECT_DIR** | Override project directory | `$PWD` | Path | State file location override |

#### MEMORY_LIMIT

**Purpose:** Controls maximum memory (in MB) allowed for parallel workflow execution.

**How it works:**
- StatusLine monitors system memory via `vm_stat` (macOS) or `/proc/meminfo` (Linux)
- Before spawning Wave subagents, checks: `available_memory > MEMORY_LIMIT`
- If insufficient memory, delays subagent spawning until memory available
- Prevents system thrashing from excessive parallelism

**Usage:**
```bash
# Conservative (4GB limit)
export MEMORY_LIMIT=4096
claude --append-system-prompt "$(cat ~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md)" \
  "Analyze codebase AND design API AND write docs"

# Aggressive (16GB limit)
export MEMORY_LIMIT=16384
```

**When to adjust:**
- **Lower (2048-4096):** Laptop/limited RAM, prevent swapping
- **Default (8192):** Standard workstation (16GB RAM)
- **Higher (16384+):** Server/high-RAM workstation (32GB+ RAM)

**Example:**
```bash
# Check current memory
if [[ "$OSTYPE" == "darwin"* ]]; then
  vm_stat | grep "Pages free"
else
  free -m
fi

# Set conservative limit
export MEMORY_LIMIT=4096

# StatusLine will show warnings if memory approaches limit
```

#### MEMORY_AGGRESSIVE

**Purpose:** Enables aggressive memory management - automatically terminates lowest-priority subagents when memory pressure exceeds 95%.

**How it works:**
- SubagentStop hook monitors memory every 5 seconds
- If memory usage >95% of MEMORY_LIMIT:
  - Identifies lowest-priority active subagent (by wave, then start time)
  - Sends SIGTERM to subagent process
  - Logs termination to `/tmp/claude_session_log.txt`
  - Marks subagent as "killed" in `active_delegations.json`
- Allows high-priority phases to complete

**Usage:**
```bash
# Enable aggressive memory management
export MEMORY_AGGRESSIVE=1
export MEMORY_LIMIT=4096

# Run workflow - low-priority subagents killed if memory critical
claude --append-system-prompt "$(cat ~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md)" \
  "Large parallel workflow with 8 phases"
```

**Priority Calculation:**
- Wave 0 (implementation) > Wave 1 (verification)
- Earlier start time > later start time
- Read-only agents < write agents (read-only killed first)

**When to use:**
- **Enable (1):** Server environments, CI/CD pipelines, time-critical workflows
- **Disable (0):** Development, debugging, workflows where all phases critical

**Warning:** Killed subagents may leave incomplete work. Use with caution.

#### MAX_PARALLEL_TASKS

**Purpose:** Maximum number of concurrent subagents allowed in parallel execution waves.

**How it works:**
- Delegation orchestrator uses this value when scheduling waves
- Wave subagents spawn only if `active_count < MAX_PARALLEL_TASKS`
- Excess subagents queued until slot available
- StatusLine displays `Active: N/MAX_PARALLEL_TASKS`

**Usage:**
```bash
# Conservative parallelism (2 concurrent)
export MAX_PARALLEL_TASKS=2

# Moderate parallelism (4 concurrent, default)
export MAX_PARALLEL_TASKS=4

# Aggressive parallelism (8 concurrent)
export MAX_PARALLEL_TASKS=8
```

**When to adjust:**
- **Lower (1-2):** Limited CPU cores (dual-core), memory-intensive phases
- **Default (4):** Standard quad-core CPU
- **Higher (8-16):** Multi-core server (8+ cores), I/O-bound phases (API calls, file operations)

**Example:**
```bash
# Check CPU cores
sysctl -n hw.ncpu  # macOS
nproc              # Linux

# Set parallelism to match cores
export MAX_PARALLEL_TASKS=$(sysctl -n hw.ncpu)

# Run parallel workflow
claude --append-system-prompt "$(cat ~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md)" \
  "Analyze auth AND design API AND write docs AND setup CI"
```

**Performance Impact:**
- Too low: Underutilizes CPU, slower execution
- Too high: CPU thrashing, context switching overhead
- Optimal: Match to CPU cores, account for I/O vs CPU-bound work

#### DEBUG_DELEGATION_HOOK

**Purpose:** Enables detailed debug logging for delegation policy enforcement.

**How it works:**
- PreToolUse hook logs every tool invocation to `/tmp/delegation_hook_debug.log`
- Logs session ID, tool name, allowed/blocked status
- Logs session registration events
- Timestamped entries for troubleshooting

**Usage:**
```bash
# Enable debug logging
export DEBUG_DELEGATION_HOOK=1

# Run delegation workflow
/delegate "Create calculator.py"

# Tail debug log
tail -f /tmp/delegation_hook_debug.log
```

**Log Format:**
```
[2025-01-11 14:30:22] SESSION=sess_abc123 TOOL=Read STATUS=blocked
[2025-01-11 14:30:23] SESSION=sess_abc123 TOOL=SlashCommand STATUS=allowed (triggers registration)
[2025-01-11 14:30:23] SESSION=sess_abc123 REGISTERED (delegation privileges granted)
[2025-01-11 14:30:24] SESSION=sess_abc123 TOOL=Read STATUS=allowed (session registered)
```

**When to use:**
- Troubleshooting delegation policy issues
- Debugging hook execution failures
- Auditing tool access patterns
- Verifying session registration

**Disable after troubleshooting** to avoid log file growth.

#### DELEGATION_HOOK_DISABLE

**Purpose:** Emergency bypass to disable delegation enforcement (allows all tools without `/delegate`).

**How it works:**
- PreToolUse hook checks `DELEGATION_HOOK_DISABLE`
- If set to 1, all tools allowed regardless of session registration
- Delegation policy completely bypassed
- Session registry not updated

**Usage:**
```bash
# Emergency bypass (disable delegation enforcement)
export DELEGATION_HOOK_DISABLE=1

# Use tools directly without /delegate
claude "Create calculator.py"

# Re-enable delegation enforcement
export DELEGATION_HOOK_DISABLE=0
```

**When to use:**
- **Hook malfunction:** Delegation hook broken, need immediate access
- **Testing:** Validate workflows without delegation overhead
- **Migration:** Transitioning from non-delegated to delegated environment

**WARNING:**
- **Security risk:** Bypasses all delegation policies
- **Use sparingly:** Only for emergencies or testing
- **Re-enable immediately:** Don't leave disabled in production

**Alternative:** If delegation hook has issues, fix the hook rather than bypass:
```bash
# Diagnose hook issues
ls -la ~/.claude/hooks/PreToolUse/require_delegation.sh
chmod +x ~/.claude/hooks/PreToolUse/require_delegation.sh

# Test hook directly
bash ~/.claude/hooks/PreToolUse/require_delegation.sh
```

#### CLAUDE_PROJECT_DIR

**Purpose:** Override project directory for state file storage (`.claude/state/`).

**How it works:**
- Hooks check `CLAUDE_PROJECT_DIR` environment variable
- If set, use `$CLAUDE_PROJECT_DIR/.claude/state/` for state files
- If unset, use `$PWD/.claude/state/` (current working directory)
- Allows state persistence across directory changes

**Usage:**
```bash
# Set project directory override
export CLAUDE_PROJECT_DIR=/Users/user/my-project

# State files written to /Users/user/my-project/.claude/state/
/delegate "Create calculator.py"

# Verify state location
ls -la /Users/user/my-project/.claude/state/
```

**When to use:**
- **Multi-project workflows:** Working across multiple project directories
- **CI/CD environments:** Fixed state location regardless of build directory
- **Debugging:** Centralized state file location for inspection

**Default behavior:**
```bash
# Without CLAUDE_PROJECT_DIR
cd /Users/user/project-a
/delegate "Task A"
# State: /Users/user/project-a/.claude/state/

cd /Users/user/project-b
/delegate "Task B"
# State: /Users/user/project-b/.claude/state/
```

**With override:**
```bash
# With CLAUDE_PROJECT_DIR
export CLAUDE_PROJECT_DIR=/tmp/claude-state

cd /Users/user/project-a
/delegate "Task A"
# State: /tmp/claude-state/.claude/state/

cd /Users/user/project-b
/delegate "Task B"
# State: /tmp/claude-state/.claude/state/ (same location)
```

#### Environment Variable Configuration Examples

**Development Environment (conservative):**
```bash
export MEMORY_LIMIT=4096              # 4GB limit
export MEMORY_AGGRESSIVE=0            # No auto-kill
export MAX_PARALLEL_TASKS=2           # 2 concurrent subagents
export DEBUG_DELEGATION_HOOK=1        # Enable debug logging
export DELEGATION_HOOK_DISABLE=0      # Enforcement enabled
export CLAUDE_PROJECT_DIR=$PWD        # Use current directory
```

**Production Environment (aggressive):**
```bash
export MEMORY_LIMIT=16384             # 16GB limit
export MEMORY_AGGRESSIVE=1            # Auto-kill on pressure
export MAX_PARALLEL_TASKS=8           # 8 concurrent subagents
export DEBUG_DELEGATION_HOOK=0        # No debug logging (performance)
export DELEGATION_HOOK_DISABLE=0      # Enforcement enabled
export CLAUDE_PROJECT_DIR=/var/lib/claude  # Fixed state location
```

**CI/CD Environment:**
```bash
export MEMORY_LIMIT=8192              # 8GB limit
export MEMORY_AGGRESSIVE=1            # Auto-kill (time-critical)
export MAX_PARALLEL_TASKS=4           # 4 concurrent (CI runners often 4-core)
export DEBUG_DELEGATION_HOOK=0        # No debug logging
export DELEGATION_HOOK_DISABLE=0      # Enforcement enabled
export CLAUDE_PROJECT_DIR=$CI_PROJECT_DIR/.claude  # CI workspace
```

**Troubleshooting Environment:**
```bash
export MEMORY_LIMIT=8192              # Standard limit
export MEMORY_AGGRESSIVE=0            # No auto-kill (preserve errors)
export MAX_PARALLEL_TASKS=1           # Sequential only (isolate issues)
export DEBUG_DELEGATION_HOOK=1        # Full debug logging
export DELEGATION_HOOK_DISABLE=0      # Test with enforcement
export CLAUDE_PROJECT_DIR=$PWD        # Current directory
```

---

## Best Practices

### Delegation Patterns

1. **Always delegate immediately** when tools are blocked
   - Don't try alternative approaches
   - Don't explain what you tried
   - Use `/delegate <full task description>` immediately

2. **Use descriptive task descriptions** for better agent selection
   - Include relevant keywords to trigger specialized agents
   - Be specific about objectives and deliverables
   - Example: "Refactor authentication module to improve maintainability" triggers code-cleanup-optimizer

3. **Enable workflow orchestration** for multi-step tasks
   - Append WORKFLOW_ORCHESTRATOR system prompt
   - Ensures context passing between phases
   - Provides TodoWrite tracking

4. **Trust the orchestrator** for agent selection
   - Keyword matching algorithm is intelligent (≥2 matches)
   - Specialized agents have domain expertise
   - Falls back to general-purpose if no strong match

### Multi-Step Workflow Patterns

5. **Trust execution mode selection**
   - Orchestrator analyzes phase dependencies intelligently
   - Sequential: Phases with data dependencies
   - Parallel: Independent phases with resource isolation
   - Conservative fallback when uncertain

6. **Capture comprehensive context** between phases
   - File paths: Always absolute (e.g., `/Users/user/project/file.py`)
   - Key decisions: Framework choices, architecture patterns
   - Configurations: Settings, environment variables
   - Issues encountered: Blockers and resolutions

7. **Update TodoWrite after each phase/wave**
   - Provides transparency and progress tracking
   - Mark phases complete only when fully finished
   - Update status: pending → in_progress → completed

8. **Verify phase/wave results** before proceeding
   - Check that files were created at expected paths
   - Validate that decisions were implemented correctly
   - Ensure no errors occurred

9. **Use absolute paths** when referencing files
   - Example: `/Users/user/project/calculator.py`
   - Not: `./calculator.py` or `calculator.py`

10. **Understand execution modes**
    - Sequential: Phases execute one at a time with context passing
    - Parallel: Independent phases execute concurrently in waves
    - Wave synchronization: Wave N+1 waits for all Phase completions in Wave N

### Error Handling Patterns

11. **Stop at phase/wave failures**
    - Don't proceed if a phase fails or encounters errors
    - Review error messages and fix issues
    - Re-attempt failed phase with fixes

12. **Review orchestrator recommendations**
    - Understand execution mode (sequential vs parallel)
    - Verify phase dependencies make sense
    - Check agent selections are appropriate

13. **Use emergency bypass sparingly**
    - Only when delegation enforcement needs to be disabled
    - Example: Troubleshooting hook issues
    - Re-enable after troubleshooting complete

14. **Wave failure handling** (parallel mode)
    - Successful phases are preserved
    - Failed phases can be retried independently
    - Context from successful phases passed forward

### Agent Selection Patterns

15. **Include relevant keywords** in task descriptions
    - Example: "analyze architecture" → codebase-context-analyzer
    - Example: "refactor and optimize" → code-cleanup-optimizer
    - Example: "test and verify" → task-completion-verifier

16. **Check agent capabilities** in `src/commands/delegate.md`
    - Lists all 11 specialized agents
    - Shows activation keywords for each
    - Describes key capabilities and use cases

17. **Let orchestrator select agents**
    - Uses keyword matching with ≥2 match threshold
    - Considers match count (higher wins)
    - Falls back to general-purpose if no strong match

18. **Independence indicators** for parallel execution
    - Use "AND" (capitalized) to hint at parallel-safe phases
    - Example: "Analyze auth system AND design payment API"
    - Orchestrator analyzes dependencies to confirm

---

## Troubleshooting

### Tools Are Blocked But Delegation Fails

**Symptoms:**
- PreToolUse hook blocks tools correctly
- `/delegate` command doesn't work
- Orchestrator not found

**Diagnosis:**
```bash
# Check settings.json location
ls ~/.claude/settings.json

# Verify hook scripts are executable
ls -la ~/.claude/hooks/PreToolUse/require_delegation.sh

# Check agent files exist
ls ~/.claude/agents/
```

**Solutions:**
```bash
# Reinstall configuration
cp -r src/agents src/commands src/hooks src/system-prompts src/scripts src/settings.json ~/.claude/

# Make hooks executable
chmod +x ~/.claude/hooks/PreToolUse/require_delegation.sh
chmod +x ~/.claude/hooks/UserPromptSubmit/clear-delegation-sessions.sh
```

### Agent Not Found Error

**Symptoms:**
- `/delegate` executes but agent file not found
- Error: "Could not read agent configuration"

**Diagnosis:**
```bash
# List available agents
ls ~/.claude/agents/

# Check specific agent file
cat ~/.claude/agents/delegation-orchestrator.md
```

**Solutions:**
```bash
# Verify agent filename matches delegation request
# Agent files should be in ~/.claude/agents/
# Filenames should match agent names (kebab-case)

# Copy missing agents
cp src/agents/*.md ~/.claude/agents/
```

### Multi-Step Workflow Not Detected

**Symptoms:**
- Task has multiple steps but treated as single-step
- No TodoWrite task list created
- Context not passed between phases

**Diagnosis:**
```bash
# Check if WORKFLOW_ORCHESTRATOR system prompt is appended
# Task description should contain multi-step indicators
```

**Solutions:**
```bash
# Append WORKFLOW_ORCHESTRATOR system prompt
claude --append-system-prompt "$(cat ~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md)" \
  "Create calculator.py with tests and verify they pass"

# Use multi-step keywords in task description
# Sequential connectors: "and then", "with", "including"
# Compound indicators: "with [noun]", "and [verb]"
# Phase markers: "first... then...", "start by... then..."
```

### Debug Mode Not Working

**Symptoms:**
- `DEBUG_DELEGATION_HOOK=1` set but no log file
- Log file empty or not updating

**Diagnosis:**
```bash
# Check environment variable
echo $DEBUG_DELEGATION_HOOK

# Check log file location
ls -la /tmp/delegation_hook_debug.log

# Check hook script has debug code
grep DEBUG_HOOK ~/.claude/hooks/PreToolUse/require_delegation.sh
```

**Solutions:**
```bash
# Enable debug mode
export DEBUG_DELEGATION_HOOK=1

# Trigger a tool call to generate log entries
/delegate test task

# Tail log file
tail -f /tmp/delegation_hook_debug.log
```

### Session Registry Issues

**Symptoms:**
- Tools blocked even after successful delegation
- Session not registered in delegated_sessions.txt

**Diagnosis:**
```bash
# Check state directory exists
ls -la .claude/state/

# Check delegated sessions file
cat .claude/state/delegated_sessions.txt

# Check file age (auto-cleanup after 1 hour)
stat .claude/state/delegated_sessions.txt
```

**Solutions:**
```bash
# Manually create state directory if missing
mkdir -p .claude/state

# Clear stale sessions
rm -f .claude/state/delegated_sessions.txt

# Re-delegate to register session
/delegate <task>
```

### Parallel Execution Not Triggering

**Symptoms:**
- Task seems parallel-safe but executes sequentially
- No wave execution in active_delegations.json

**Diagnosis:**
```bash
# Check task description for parallel hints
# Look for "AND" (capitalized) keyword
# Verify phases are truly independent (no data dependencies)

# Check active delegations file
cat .claude/state/active_delegations.json
```

**Solutions:**
```bash
# Use explicit parallel indicators
# Example: "Analyze auth system AND design payment API"

# Verify phases are independent:
# - No data dependencies
# - Different files/resources
# - No file modification conflicts

# Trust orchestrator's conservative fallback
# Sequential is safer when dependencies unclear
```

### Hook Debugging Guide

This section provides comprehensive debugging procedures for all 6 delegation system hooks.

#### General Hook Debugging

**Step 1: Verify Hook Installation**

```bash
# Check all hooks are installed
ls -la ~/.claude/hooks/SessionStart/
ls -la ~/.claude/hooks/UserPromptSubmit/
ls -la ~/.claude/hooks/PreToolUse/
ls -la ~/.claude/hooks/PostToolUse/
ls -la ~/.claude/hooks/SubagentStop/
ls -la ~/.claude/hooks/stop/

# Check execute permissions
find ~/.claude/hooks -type f -name "*.sh" ! -perm -u+x

# Fix permissions if needed
find ~/.claude/hooks -type f -name "*.sh" -exec chmod +x {} \;
```

**Step 2: Test Hook Syntax**

```bash
# Test each hook for syntax errors
bash -n ~/.claude/hooks/SessionStart/log_session_start.sh
bash -n ~/.claude/hooks/UserPromptSubmit/clear-delegation-sessions.sh
bash -n ~/.claude/hooks/PreToolUse/require_delegation.sh
bash -n ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh
bash -n ~/.claude/hooks/SubagentStop/log_subagent_stop.sh
bash -n ~/.claude/hooks/stop/python_stop_hook.sh
```

**Step 3: Enable Debug Logging**

```bash
# Enable global debug logging
export DEBUG_DELEGATION_HOOK=1

# Each hook will log to /tmp/delegation_hook_debug.log
tail -f /tmp/delegation_hook_debug.log
```

**Step 4: Check Hook Registration**

```bash
# Verify hooks are registered in settings.json
cat ~/.claude/settings.json | jq '.hooks'

# Expected output should include all 6 hook types
```

#### SessionStart Hook Debugging

**Problem:** Session not logged at startup

**Diagnosis:**
```bash
# Check session log file exists
ls -la /tmp/claude_session_log.txt

# Check recent session starts
tail -20 /tmp/claude_session_log.txt | grep SESSION_START

# Manually trigger hook
export CLAUDE_SESSION_ID=test_session
bash ~/.claude/hooks/SessionStart/log_session_start.sh

# Verify test entry in log
grep test_session /tmp/claude_session_log.txt
```

**Common Issues:**
- **Log file permissions:** `chmod 666 /tmp/claude_session_log.txt`
- **CLAUDE_SESSION_ID not set:** Hook needs session ID from Claude Code
- **Hook not executable:** `chmod +x ~/.claude/hooks/SessionStart/log_session_start.sh`

#### UserPromptSubmit Hook Debugging

**Problem:** Delegation state not cleared between prompts

**Diagnosis:**
```bash
# Check state file before and after prompt
cat .claude/state/delegated_sessions.txt

# Manually trigger hook
bash ~/.claude/hooks/UserPromptSubmit/clear-delegation-sessions.sh

# Verify file cleared
cat .claude/state/delegated_sessions.txt  # Should be empty
```

**Common Issues:**
- **State directory doesn't exist:** `mkdir -p .claude/state`
- **File permissions:** `chmod 644 .claude/state/delegated_sessions.txt`
- **CLAUDE_PROJECT_DIR mismatch:** Verify `echo $CLAUDE_PROJECT_DIR`

#### PreToolUse Hook Debugging

**Problem:** Tools not blocked or session not registered

**Diagnosis:**
```bash
# Enable debug mode
export DEBUG_DELEGATION_HOOK=1

# Check allowlist configuration
grep -A 10 "ALLOWED_TOOLS" ~/.claude/hooks/PreToolUse/require_delegation.sh

# Manually test hook (requires tool name argument)
export CLAUDE_SESSION_ID=test_session
export CLAUDE_TOOL_NAME=Read
bash ~/.claude/hooks/PreToolUse/require_delegation.sh

# Check debug log
tail /tmp/delegation_hook_debug.log
```

**Common Issues:**
- **Allowlist too broad:** Verify ALLOWED_TOOLS array contains only intended tools
- **Session not registered:** Check `.claude/state/delegated_sessions.txt` has session ID
- **File path issues:** Verify script uses correct state file path

**Manual Session Registration Test:**
```bash
# Create test session
mkdir -p .claude/state
echo "test_session_123" > .claude/state/delegated_sessions.txt

# Test tool access with registered session
export CLAUDE_SESSION_ID=test_session_123
export CLAUDE_TOOL_NAME=Read
bash ~/.claude/hooks/PreToolUse/require_delegation.sh
# Should exit 0 (allowed)

# Test tool access with unregistered session
export CLAUDE_SESSION_ID=unregistered_session
bash ~/.claude/hooks/PreToolUse/require_delegation.sh
# Should exit 1 (blocked)
```

#### PostToolUse Hook Debugging

**Problem:** Python validation not running or failing incorrectly

**Diagnosis:**
```bash
# Check Python tools installed
which ruff
which pyright

# Test hook manually with Python file
export CLAUDE_TOOL_NAME=Write
export CLAUDE_TOOL_ARGUMENTS='{"file_path":"/tmp/test.py","content":"print(\"hello\")"}'
bash ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh

# Check exit code
echo $?  # 0 = success, 1 = validation failed

# Test critical security check
cat > /tmp/test_bad.py << 'EOF'
import pickle
data = pickle.loads(user_input)  # S301: Unsafe deserialization
EOF

export CLAUDE_TOOL_ARGUMENTS='{"file_path":"/tmp/test_bad.py"}'
bash ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh
# Should fail with S301 error
```

**Common Issues:**
- **Ruff not installed:** `uv tool install ruff` or `pip install ruff`
- **Pyright not installed:** `npm install -g pyright`
- **Tool name not Write/Edit:** Hook only runs for Write/Edit operations
- **JSON parsing error:** Verify CLAUDE_TOOL_ARGUMENTS is valid JSON

**Skip Specific Checks:**
```bash
# Skip Ruff validation
export CHECK_RUFF=0
bash ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh

# Skip Pyright validation
export CHECK_PYRIGHT=0
bash ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh
```

#### SubagentStop Hook Debugging

**Problem:** Subagent completion not logged or parallel state not updated

**Diagnosis:**
```bash
# Check session log for subagent stops
tail -50 /tmp/claude_session_log.txt | grep SUBAGENT_STOP

# Check parallel execution state
cat .claude/state/active_delegations.json | jq .

# Manually trigger hook
export CLAUDE_SESSION_ID=test_subagent
export CLAUDE_PARENT_SESSION_ID=test_parent
bash ~/.claude/hooks/SubagentStop/log_subagent_stop.sh

# Verify log entry
grep test_subagent /tmp/claude_session_log.txt
```

**Common Issues:**
- **Parent session ID missing:** Hook needs CLAUDE_PARENT_SESSION_ID
- **active_delegations.json corrupted:** Check JSON syntax with `jq`
- **Wave synchronization failure:** Verify all Wave N subagents have SUBAGENT_STOP entries

**Test Wave Synchronization:**
```bash
# Create test parallel workflow state
cat > .claude/state/active_delegations.json << 'EOF'
{
  "version": "2.0",
  "workflow_id": "test_workflow",
  "execution_mode": "parallel",
  "active_delegations": [
    {"delegation_id": "d1", "session_id": "s1", "wave": 1, "status": "active"},
    {"delegation_id": "d2", "session_id": "s2", "wave": 1, "status": "active"}
  ]
}
EOF

# Simulate first subagent stop
export CLAUDE_SESSION_ID=s1
bash ~/.claude/hooks/SubagentStop/log_subagent_stop.sh

# Check d1 marked complete
cat .claude/state/active_delegations.json | jq '.active_delegations[] | select(.delegation_id=="d1")'

# Simulate second subagent stop (should trigger wave sync)
export CLAUDE_SESSION_ID=s2
bash ~/.claude/hooks/SubagentStop/log_subagent_stop.sh

# Check both complete
cat .claude/state/active_delegations.json | jq '.active_delegations'
```

#### Stop Hook Debugging

**Problem:** Session cleanup not occurring

**Diagnosis:**
```bash
# Check session log for STOP entries
tail -50 /tmp/claude_session_log.txt | grep SESSION_STOP

# Check stale session cleanup
ls -la .claude/state/delegated_sessions.txt
stat .claude/state/delegated_sessions.txt  # Check file age

# Manually trigger hook
export CLAUDE_SESSION_ID=test_session
bash ~/.claude/hooks/stop/python_stop_hook.sh

# Verify log entry
grep "SESSION_STOP.*test_session" /tmp/claude_session_log.txt
```

**Common Issues:**
- **Hook not running on exit:** Verify hook registration in settings.json
- **Stale sessions not cleaned:** Check cleanup logic (removes sessions >1 hour old)
- **State validation errors:** Check parallel workflow state schema

**Test Stale Session Cleanup:**
```bash
# Create old session entry
mkdir -p .claude/state
echo "old_session_123" > .claude/state/delegated_sessions.txt

# Age the file (touch -t is macOS/BSD, use different method on Linux)
touch -t 202501010000 .claude/state/delegated_sessions.txt

# Run stop hook (should remove old session)
bash ~/.claude/hooks/stop/python_stop_hook.sh

# Verify file cleaned
cat .claude/state/delegated_sessions.txt  # Should be empty or removed
```

#### Integration Testing

**Complete Hook Lifecycle Test:**

```bash
# Enable debug logging
export DEBUG_DELEGATION_HOOK=1

# 1. SessionStart: Initialize
export CLAUDE_SESSION_ID=integration_test_001
bash ~/.claude/hooks/SessionStart/log_session_start.sh
grep SESSION_START /tmp/claude_session_log.txt | tail -1

# 2. UserPromptSubmit: Clear state
bash ~/.claude/hooks/UserPromptSubmit/clear-delegation-sessions.sh
cat .claude/state/delegated_sessions.txt  # Should be empty

# 3. PreToolUse: Block Read (not registered)
export CLAUDE_TOOL_NAME=Read
bash ~/.claude/hooks/PreToolUse/require_delegation.sh && echo "FAIL: Should block" || echo "PASS: Blocked"

# 4. PreToolUse: Allow SlashCommand (triggers registration)
export CLAUDE_TOOL_NAME=SlashCommand
bash ~/.claude/hooks/PreToolUse/require_delegation.sh && echo "PASS: Allowed" || echo "FAIL: Should allow"
cat .claude/state/delegated_sessions.txt  # Should contain integration_test_001

# 5. PreToolUse: Allow Read (now registered)
export CLAUDE_TOOL_NAME=Read
bash ~/.claude/hooks/PreToolUse/require_delegation.sh && echo "PASS: Allowed" || echo "FAIL: Should allow"

# 6. PostToolUse: Validate Python file
cat > /tmp/integration_test.py << 'EOF'
def hello() -> str:
    return "world"
EOF
export CLAUDE_TOOL_NAME=Write
export CLAUDE_TOOL_ARGUMENTS='{"file_path":"/tmp/integration_test.py"}'
bash ~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh && echo "PASS: Validation" || echo "FAIL: Validation"

# 7. SubagentStop: Log completion
export CLAUDE_PARENT_SESSION_ID=integration_test_001
export CLAUDE_SESSION_ID=integration_test_subagent
bash ~/.claude/hooks/SubagentStop/log_subagent_stop.sh
grep SUBAGENT_STOP /tmp/claude_session_log.txt | tail -1

# 8. Stop: Cleanup
export CLAUDE_SESSION_ID=integration_test_001
bash ~/.claude/hooks/stop/python_stop_hook.sh
grep SESSION_STOP /tmp/claude_session_log.txt | tail -1

# Verify complete lifecycle in debug log
tail -100 /tmp/delegation_hook_debug.log | grep integration_test
```

**Expected Output:**
```
SESSION_START session_id=integration_test_001
PASS: Blocked
PASS: Allowed
integration_test_001 (in delegated_sessions.txt)
PASS: Allowed
PASS: Validation
SUBAGENT_STOP session_id=integration_test_subagent parent=integration_test_001
SESSION_STOP session_id=integration_test_001
```

If any step fails, check:
1. Hook script syntax (`bash -n <script>`)
2. Permissions (`ls -la`, `chmod +x`)
3. Environment variables (`env | grep CLAUDE`)
4. Debug log (`tail /tmp/delegation_hook_debug.log`)

---

## File Reference

### Hook Scripts
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/hooks/PreToolUse/require_delegation.sh` - Tool blocking enforcement
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/hooks/UserPromptSubmit/clear-delegation-sessions.sh` - State cleanup
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/hooks/PostToolUse/python_posttooluse_hook.sh` - Post-tool operations
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/hooks/stop/python_stop_hook.sh` - Cleanup on exit

### Agent Configurations
- `~/.claude/agents/delegation-orchestrator.md` - Meta-agent for routing
- `~/.claude/agents/codebase-context-analyzer.md` - Code analysis (read-only)
- `~/.claude/agents/tech-lead-architect.md` - Solution design
- `~/.claude/agents/task-completion-verifier.md` - Testing, QA
- `~/.claude/agents/code-cleanup-optimizer.md` - Refactoring
- `~/.claude/agents/code-reviewer.md` - Code review
- `~/.claude/agents/devops-experience-architect.md` - Infrastructure, CI/CD
- `~/.claude/agents/documentation-expert.md` - Documentation
- `~/.claude/agents/dependency-manager.md` - Package management
- `~/.claude/agents/task-decomposer.md` - Project planning
- `~/.claude/agents/phase-validator.md` - Phase validation

### Command Definitions
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/commands/delegate.md` - Intelligent delegation command
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/commands/ask.md` - Read-only question answering
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/commands/pre-commit.md` - Pre-commit checks

### System Prompts
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/system-prompts/WORKFLOW_ORCHESTRATOR.md` - Multi-step workflow orchestration

### Configuration
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/src/settings.json` - Hook registration, permissions
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/CLAUDE.md` - Project delegation policy (this file)
- `/Users/nadavbarkai/dev/claude-code-workflow-orchestration/README.md` - User-facing documentation

### State Files (Runtime)
- `.claude/state/delegated_sessions.txt` - Session registry
- `.claude/state/active_delegations.json` - Parallel execution tracking

### Debug Logs
- `/tmp/delegation_hook_debug.log` - Hook debug output (when DEBUG_DELEGATION_HOOK=1)

---

## APPENDIX: Python Coding Standards

This appendix defines the coding standards enforced by the PostToolUse hook (`hooks/PostToolUse/python_posttooluse_hook.sh`) for this project.

### Python Version

**Required:** Python 3.12+

All code must use modern Python 3.12+ syntax and features.

### Type Annotations

#### Modern Type Hint Syntax (Required)

Use Python 3.10+ union syntax and built-in generics:

**✅ Correct:**
```python
def process(items: list[str]) -> dict[str, int]:
    """Process items and return counts."""
    return {item: len(item) for item in items}

def get_value(key: str) -> str | None:
    """Get value or None if not found."""
    return data.get(key)
```

**❌ Incorrect:**
```python
from typing import List, Dict, Optional, Union

def process(items: List[str]) -> Dict[str, int]:  # Don't use typing.List
    return {item: len(item) for item in items}

def get_value(key: str) -> Optional[str]:  # Use str | None instead
    return data.get(key)
```

#### Enforced Rules

- **UP006:** Use `list[T]` instead of `List[T]`
- **UP007:** Use `X | Y` instead of `Union[X, Y]` or `Optional[X]`
- **UP035:** Import replacements for deprecated typing features
- **UP037:** Remove quotes from type annotations (use `from __future__ import annotations` if needed)

### Logging Standards

#### No Print Statements in Production Code

Use the `logging` module for all output.

**✅ Correct:**
```python
import logging

logger = logging.getLogger(__name__)

def process_data(data: dict) -> None:
    logger.info("Processing data with %d items", len(data))
    logger.debug("Data contents: %s", data)
```

**❌ Incorrect:**
```python
def process_data(data: dict) -> None:
    print(f"Processing data with {len(data)} items")  # Blocked by T201
```

#### Exceptions

Print statements are allowed in:
- Test files (`test_*.py`, `**/tests/**/*.py`)
- CLI entry points (`cli.py`, `main.py`, `__main__.py`)

### Code Quality Standards

#### Import Management

- **F401:** Remove unused imports
- **F811:** No redefined imports
- **I001:** Sort imports (use `isort` or `ruff format`)

#### Error Handling

- **BLE001:** Don't use bare `except Exception:` - catch specific exceptions
- **TRY002:** Use `raise ... from ...` to preserve exception context
- **TRY400:** Include `exc_info=True` when logging errors

**✅ Correct:**
```python
try:
    result = dangerous_operation()
except ValueError as e:
    logger.error("Operation failed", exc_info=True)
    raise ProcessingError("Failed to process") from e
```

**❌ Incorrect:**
```python
try:
    result = dangerous_operation()
except Exception:  # Too broad
    logger.error("Operation failed")  # Missing exc_info
    raise ProcessingError("Failed")  # Missing 'from e'
```

### Security Standards

#### Critical Security Violations (Blocking)

The following patterns are **blocked** by the PostToolUse hook:

- **S102:** `exec()` usage
- **S307:** `eval()` usage
- **S105-S107:** Hardcoded passwords/secrets
- **S301-S302:** `pickle`/`marshal` usage (unsafe serialization)
- **S311:** Using `random` module for security purposes (use `secrets`)
- **S501:** `requests.get(verify=False)` - insecure TLS
- **S506:** `yaml.load()` without `Loader=` (use `safe_load`)

**✅ Correct:**
```python
import secrets
import yaml

# Generate secure random token
token = secrets.token_urlsafe(32)

# Load YAML safely
with open("config.yml") as f:
    config = yaml.safe_load(f)
```

**❌ Incorrect:**
```python
import random
import yaml

# Insecure random for security
token = ''.join(random.choices(string.ascii_letters, k=32))  # S311

# Unsafe YAML loading
with open("config.yml") as f:
    config = yaml.load(f)  # S506 - missing Loader
```

#### SQL Injection Prevention

Never concatenate SQL queries with string formatting:

**✅ Correct:**
```python
cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
```

**❌ Incorrect:**
```python
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")  # SQL injection
cursor.execute("SELECT * FROM users WHERE id = " + user_id)  # SQL injection
```

#### Command Injection Prevention

Use subprocess with list arguments, never shell=True with user input:

**✅ Correct:**
```python
subprocess.run(["git", "commit", "-m", message], check=True)
```

**❌ Incorrect:**
```python
os.system(f"git commit -m {message}")  # Command injection
subprocess.run(f"git commit -m {message}", shell=True)  # Command injection
```

### Performance Standards

- **PERF102:** Use comprehensions efficiently (avoid unnecessary calls)
- **PERF401:** Use list comprehensions instead of manual loops when appropriate

### Hook Enforcement

All standards above are enforced by `src/hooks/PostToolUse/python_posttooluse_hook.sh` which runs:

1. **Critical Security Check:** Fast pattern matching for immediate vulnerabilities
2. **Ruff Validation:** Enforces syntax, security, and quality rules
3. **Pyright Type Checking:** Validates type annotations (basic mode)

Operations that violate these standards will be **blocked** with detailed error messages.

### Running Validation Manually

Test your code against these standards:

```bash
# Full validation
./src/hooks/PostToolUse/python_posttooluse_hook.sh your_file.py

# Skip specific checks
CHECK_RUFF=0 ./src/hooks/PostToolUse/python_posttooluse_hook.sh your_file.py
CHECK_PYRIGHT=0 ./src/hooks/PostToolUse/python_posttooluse_hook.sh your_file.py
```

### Automatic Deliverable Verification

This project uses automatic verification for multi-step workflows to ensure implementation quality.

#### How It Works

1. **Deliverable Manifests:** The delegation orchestrator generates structured deliverable manifests for each implementation phase, specifying expected files, functions, tests, and acceptance criteria.

2. **Auto-Inserted Verification Phases:** After each implementation phase, the orchestrator automatically inserts a verification phase using the task-completion-verifier agent.

3. **Manifest-Driven Validation:** The verifier performs structured checks:
   - File existence and content validation
   - Function/class presence verification
   - Type hint validation (Python)
   - Test execution and coverage analysis
   - Acceptance criteria validation

4. **Verdict Processing:**
   - **PASS:** Workflow proceeds to next phase
   - **FAIL:** Re-implementation with remediation steps
   - **PASS_WITH_MINOR_ISSUES:** Proceed with warnings tracked

#### Wave Structure

Verification phases are automatically scheduled in the wave after implementation:

```
Wave 0: Implementation phases (can be parallel)
Wave 1: Verification phases (sequential after Wave 0)
Wave 2: Next implementation phases
Wave 3: Verification phases
```

#### Deliverable Manifest Example

```json
{
  "phase_id": "phase_1_1",
  "phase_objective": "Create calculator.py with add and subtract functions",
  "deliverable_manifest": {
    "files": [{
      "path": "calculator.py",
      "must_exist": true,
      "functions": ["add", "subtract"],
      "type_hints_required": true
    }],
    "tests": [{
      "test_command": "pytest test_calculator.py",
      "all_tests_must_pass": true,
      "min_coverage": 0.8
    }],
    "acceptance_criteria": [
      "Functions support int and float inputs",
      "Error handling for invalid inputs"
    ]
  }
}
```

For complete workflow orchestration documentation, see `src/system-prompts/WORKFLOW_ORCHESTRATOR.md`.
