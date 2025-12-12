#!/usr/bin/env bash
# PostToolUse hook: Extract JSON task graph from Task output and render DAG
# Non-blocking - errors are logged but don't fail the hook

set +e  # Don't exit on errors

# Read stdin into variable
HOOK_INPUT=$(cat)

# Extract tool_name and tool_output using jq
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_output // empty' 2>/dev/null)

# Only process if tool is Task
if [[ "$TOOL_NAME" != "Task" ]]; then
    exit 0
fi

# Check if tool_output contains JSON code fence
if ! echo "$TOOL_OUTPUT" | grep -q '```json'; then
    exit 0
fi

# Extract JSON between ```json and ``` markers
JSON_CONTENT=$(echo "$TOOL_OUTPUT" | sed -n '/```json/,/```/p' | sed '1d;$d')

# Validate JSON structure using jq
if ! echo "$JSON_CONTENT" | jq empty 2>/dev/null; then
    echo "Warning: Invalid JSON in Task output, skipping DAG visualization" >&2
    exit 0
fi

# Check for workflow or waves structure
HAS_WORKFLOW=$(echo "$JSON_CONTENT" | jq 'has("workflow") or has("waves")' 2>/dev/null)
if [[ "$HAS_WORKFLOW" != "true" ]]; then
    exit 0
fi

# Determine project directory
# Use CLAUDE_PROJECT_DIR (standardized across hooks) with PWD fallback for backward compatibility
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_DIR="$PROJECT_DIR/.claude/state"

# Ensure state directory exists
mkdir -p "$STATE_DIR" 2>/dev/null || {
    echo "Warning: Could not create state directory at $STATE_DIR" >&2
    exit 0
}

# Write validated JSON to state file
STATE_FILE="$STATE_DIR/current_task_graph.json"
echo "$JSON_CONTENT" > "$STATE_FILE" 2>/dev/null || {
    echo "Warning: Could not write task graph to $STATE_FILE" >&2
    exit 0
}

# Render DAG visualization
RENDER_SCRIPT="$PROJECT_DIR/scripts/render_dag.py"
if [[ ! -f "$RENDER_SCRIPT" ]]; then
    # Try alternate location
    RENDER_SCRIPT="$(dirname "$0")/../../scripts/render_dag.py"
fi

if [[ -f "$RENDER_SCRIPT" ]]; then
    # Execute render script and capture output
    DAG_OUTPUT=$(python3 "$RENDER_SCRIPT" "$STATE_FILE" 2>/dev/null || true)

    if [[ -n "$DAG_OUTPUT" ]]; then
        # Output separator and visualization
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Task Execution Graph:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$DAG_OUTPUT"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
fi

# Always exit successfully (non-blocking)
exit 0
