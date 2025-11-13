#!/bin/bash

# PostToolUse Hook: Remind to update todo list after Task tool completions
# Analyzes todo state and provides friendly reminder for incomplete todos

set -euo pipefail

# Parse hook input from stdin
json_input=$(cat)

# Extract tool_name using Python for reliable JSON parsing
tool_name=$(printf '%s' "$json_input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except:
    print('')
    sys.exit(0)
")

# Only process Task tool invocations
if [ "$tool_name" != "Task" ] && [ "$tool_name" != "SubagentTask" ] && [ "$tool_name" != "AgentTask" ]; then
    exit 0
fi

# Determine project directory
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    project_dir="$CLAUDE_PROJECT_DIR"
else
    project_dir="$PWD"
fi

# Check if todo state file exists
todo_state_file="$project_dir/.claude/state/todos.json"

if [ ! -f "$todo_state_file" ]; then
    # No todo file means no todos to track - exit silently
    exit 0
fi

# Parse todo state and analyze completion status
todo_analysis=$(python3 -c "
import sys, json

try:
    with open('$todo_state_file', 'r') as f:
        data = json.load(f)

    todos = data.get('todos', [])

    if not todos:
        print('EMPTY')
        sys.exit(0)

    pending = sum(1 for t in todos if t.get('status') == 'pending')
    in_progress = sum(1 for t in todos if t.get('status') == 'in_progress')
    completed = sum(1 for t in todos if t.get('status') == 'completed')
    total = len(todos)
    incomplete = pending + in_progress

    print(f'{incomplete}|{total}|{pending}|{in_progress}|{completed}')
except Exception as e:
    print('ERROR')
    sys.exit(0)
")

# Parse analysis result
if [ "$todo_analysis" = "EMPTY" ] || [ "$todo_analysis" = "ERROR" ]; then
    exit 0
fi

IFS='|' read -r incomplete total pending in_progress completed <<< "$todo_analysis"

# Display reminder if there are incomplete todos
if [ "$incomplete" -gt 0 ]; then
    echo "" >&2
    echo "📋 Reminder: You have $incomplete incomplete todo(s) out of $total total." >&2

    if [ "$in_progress" -gt 0 ] && [ "$pending" -gt 0 ]; then
        echo "   ($in_progress in progress, $pending pending)" >&2
    elif [ "$in_progress" -gt 0 ]; then
        echo "   ($in_progress in progress)" >&2
    elif [ "$pending" -gt 0 ]; then
        echo "   ($pending pending)" >&2
    fi

    echo "   Consider updating your todo list with TodoWrite." >&2
    echo "" >&2
fi

# Always exit 0 to allow tool execution to proceed
exit 0
