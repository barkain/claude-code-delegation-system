#!/bin/bash
# validate_task_graph_compliance.sh
# PreToolUse hook to enforce task graph compliance
#
# Validates that when an active task graph exists, Task invocations
# include valid phase IDs that match the current execution wave.

set -euo pipefail

# ============================================================================
# INPUT VALIDATION GUARDS
# ============================================================================
# Protects against malformed or excessively large stdin JSON

# Maximum stdin size: 1MB (prevents resource exhaustion)
readonly MAX_STDIN_SIZE=1048576

# Read stdin with size limit
stdin_json=$(head -c "$MAX_STDIN_SIZE")
stdin_size=${#stdin_json}

# Check 1: Detect oversized input
if [[ "$stdin_size" -ge "$MAX_STDIN_SIZE" ]]; then
    echo "ERROR: stdin JSON exceeds maximum size (1MB)" >&2
    echo "Received: $stdin_size bytes" >&2
    exit 1
fi

# Check 2: Detect empty input
if [[ -z "$stdin_json" ]]; then
    echo "ERROR: stdin is empty, expected JSON input from PreToolUse hook" >&2
    exit 1
fi

# Check 3: Validate JSON syntax
if ! echo "$stdin_json" | jq -e . > /dev/null 2>&1; then
    echo "ERROR: stdin is not valid JSON" >&2
    echo "Received first 200 chars: ${stdin_json:0:200}" >&2
    exit 1
fi

# Input validated successfully
TOOL_INPUT="$stdin_json"

# ============================================================================

# Lock file for preventing race conditions
LOCK_FILE=""

# Cleanup function
cleanup() {
    if [[ -n "$LOCK_FILE" && -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
}

trap cleanup EXIT

# Get tool name from first argument
TOOL_NAME="${1:-}"

# Only validate Task tool invocations
if [[ "$TOOL_NAME" != "Task" ]]; then
    exit 0
fi

# Project directory (supports both project and user scope)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
TASK_GRAPH_FILE="${PROJECT_DIR}/.claude/state/active_task_graph.json"
LOCK_FILE="${PROJECT_DIR}/.claude/state/.validate_graph.lock"

# Create lock file directory if needed
mkdir -p "$(dirname "$LOCK_FILE")"

# Critical Section: Check file existence and read task graph
# Use flock to prevent TOCTOU race conditions
(
    # Acquire exclusive lock with 5 second timeout
    if ! flock -x -w 5 200; then
        echo "❌ LOCK TIMEOUT: Could not acquire task graph lock after 5 seconds"
        echo "Another session may be accessing the task graph."
        exit 1
    fi

    # If no active task graph, allow the Task invocation
    if [[ ! -f "$TASK_GRAPH_FILE" ]]; then
        exit 0
    fi

# Extract the prompt from tool input
# Try flat structure first (.prompt), then nested structure (.parameters.prompt)
TASK_PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // .parameters?.prompt // empty' 2>/dev/null || echo "")

if [[ -z "$TASK_PROMPT" ]]; then
    exit 0
fi

# Check if this is a delegation-orchestrator invocation (always allowed)
SUBAGENT_TYPE=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // empty' 2>/dev/null || echo "")
if [[ "$SUBAGENT_TYPE" == "delegation-orchestrator" ]]; then
    exit 0
fi

# Extract phase ID from the prompt (format: "Phase ID: phase_X_Y")
PHASE_ID=$(echo "$TASK_PROMPT" | grep -oE 'Phase ID: phase_[0-9]+_[0-9]+' | head -1 | sed 's/Phase ID: //' || echo "")

# If task graph exists but no phase ID in prompt, this is a compliance violation
if [[ -z "$PHASE_ID" ]]; then
    echo "❌ TASK GRAPH COMPLIANCE VIOLATION"
    echo ""
    echo "An active task graph exists at: $TASK_GRAPH_FILE"
    echo "But this Task invocation is missing a Phase ID marker."
    echo ""
    echo "REQUIRED: Include 'Phase ID: phase_X_Y' at the start of your Task prompt."
    echo ""
    echo "Example:"
    echo "  Phase ID: phase_0_0"
    echo "  Agent: codebase-context-analyzer"
    echo ""
    echo "  [Your task description...]"
    echo ""
    echo "If you believe this task graph is outdated, delete it first:"
    echo "  rm $TASK_GRAPH_FILE"
    exit 1
fi

# Validate phase ID exists in task graph
PHASE_EXISTS=$(jq -r --arg pid "$PHASE_ID" '
    .waves[]?.phases[]? | select(.phase_id == $pid) | .phase_id
' "$TASK_GRAPH_FILE" 2>/dev/null || echo "")

if [[ -z "$PHASE_EXISTS" ]]; then
    echo "❌ INVALID PHASE ID: $PHASE_ID"
    echo ""
    echo "This phase ID does not exist in the active task graph."
    echo ""
    echo "Available phases:"
    jq -r '.waves[]?.phases[]?.phase_id' "$TASK_GRAPH_FILE" 2>/dev/null | sed 's/^/  - /'
    echo ""
    echo "Check your execution plan or clear the task graph:"
    echo "  rm $TASK_GRAPH_FILE"
    exit 1
fi

# Get current wave from task graph
CURRENT_WAVE=$(jq -r '.current_wave // 0' "$TASK_GRAPH_FILE" 2>/dev/null || echo "0")

# Get the wave this phase belongs to
PHASE_WAVE=$(jq -r --arg pid "$PHASE_ID" '
    .waves[] | select(.phases[]?.phase_id == $pid) | .wave_id
' "$TASK_GRAPH_FILE" 2>/dev/null | head -1 || echo "")

# Validate wave order
if [[ -n "$PHASE_WAVE" && "$PHASE_WAVE" -gt "$CURRENT_WAVE" ]]; then
    echo "❌ WAVE ORDER VIOLATION"
    echo ""
    echo "Current wave: $CURRENT_WAVE"
    echo "Attempted phase: $PHASE_ID (wave $PHASE_WAVE)"
    echo ""
    echo "Cannot start Wave $PHASE_WAVE tasks while Wave $CURRENT_WAVE is incomplete."
    echo "Complete all Wave $CURRENT_WAVE phases first."
    exit 1
fi

) 200>"$LOCK_FILE"
# === END CRITICAL SECTION ===

# Validation passed
exit 0
