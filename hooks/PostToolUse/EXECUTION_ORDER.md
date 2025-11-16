# PostToolUse Hook Execution Order

This document describes the execution order of PostToolUse hooks registered in `settings.json`.

## Hook Registration Overview

PostToolUse hooks are organized by matcher patterns. Each matcher can have multiple hooks that execute in sequence.

## Registered Hooks (Execution Order)

### Matcher 1: `Edit|Write|MultiEdit`
Triggers on file modification tools.

1. **python_posttooluse_hook.sh**
   - Path: `~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh`
   - Timeout: Not specified (default)
   - Purpose: Python-specific post-processing

### Matcher 2: `Task`
Triggers on Task tool (subagent delegation).

1. **remind_todo_after_task.sh**
   - Path: `~/.claude/hooks/PostToolUse/remind_todo_after_task.sh`
   - Timeout: 2 seconds
   - Purpose: Remind user to update TodoWrite after task completion

### Matcher 3: `*` (ALL TOOLS)
Triggers on every tool invocation.

**EXECUTION ORDER IS CRITICAL:**

1. **retry_handler.sh** (RUNS FIRST)
   - Path: `hooks/PostToolUse/retry_handler.sh`
   - Timeout: 3 seconds
   - Purpose: Update retry state after tool execution
   - **Why first:** State must be updated before logging occurs

2. **execution_logger.sh** (RUNS SECOND)
   - Path: `hooks/PostToolUse/execution_logger.sh`
   - Timeout: 2 seconds
   - Purpose: Log execution metrics to `.claude/logs/execution.log`
   - **Why second:** Logs the final state including retry updates

## Hook Execution Flow

```
Tool Invocation
    ↓
PreToolUse Hooks Execute
    ↓
Tool Executes
    ↓
PostToolUse Hooks Execute (in registration order)
    ↓
[Matcher 1: Edit|Write|MultiEdit]
    → python_posttooluse_hook.sh
    ↓
[Matcher 2: Task]
    → remind_todo_after_task.sh
    ↓
[Matcher 3: * (all tools)]
    → retry_handler.sh (update retry state)
    → execution_logger.sh (log final state)
```

## Ordering Rationale

The execution order for Matcher 3 (`*`) is **retry_handler → execution_logger** because:

1. **State Consistency:** Retry state must be updated before logging
2. **Accurate Metrics:** Execution logger captures final state including retry attempts
3. **Dependency Chain:** Execution logger may read retry state for comprehensive logging

**IMPORTANT:** Do not reorder these hooks. Changing the order will cause:
- Incomplete retry state in logs
- Race conditions between state updates and logging
- Inaccurate execution metrics

## Path Conventions

- **Absolute paths** (`~/.claude/hooks/...`): Used for global hooks in user home directory
- **Relative paths** (`hooks/...`): Used for project-specific hooks (resolved from project root)

## Modification Guide

To add new PostToolUse hooks:

1. **Choose matcher pattern:** `*` (all tools), specific tool name, or regex pattern
2. **Determine execution order:** Place hook in correct position based on dependencies
3. **Update settings.json:** Add to appropriate matcher's hooks array
4. **Set timeout:** Recommend 2-5 seconds for hook scripts
5. **Update this document:** Document the new hook and rationale

## Validation

Verify hook registration with:

```bash
python3 -c "
import json
with open('settings.json') as f:
    data = json.load(f)
    for idx, entry in enumerate(data['hooks']['PostToolUse']):
        print(f'Matcher {idx + 1}: {entry.get(\"matcher\", \"default\")}')
        for hook in entry['hooks']:
            print(f'  → {hook[\"command\"]}')
"
```

## Last Updated

- **Date:** 2025-11-15
- **Change:** Added retry_handler.sh and execution_logger.sh to Matcher 3 (`*`)
- **Modified by:** Phase A.5 - Register new PostToolUse hooks
